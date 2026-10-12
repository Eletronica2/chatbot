import asyncio
import time
from collections import defaultdict
from contextlib import asynccontextmanager


class Saturated(Exception):
    def __init__(self, reason: str, retry_after_s: int):
        super().__init__(reason)
        self.reason = reason
        self.retry_after_s = retry_after_s


class InferenceGate:
    """Bounded concurrency + bounded queue + per-tenant cap. Over capacity -> Saturated (HTTP 503).

    The per-tenant cap counts active + waiting requests, so one company cannot occupy every slot.
    """

    def __init__(self, concurrency: int, max_queue: int, queue_timeout_s: float, max_per_tenant: int | None = None):
        self._sem = asyncio.Semaphore(concurrency)
        self.concurrency = concurrency
        self.max_queue = max_queue
        self.queue_timeout_s = queue_timeout_s
        self.max_per_tenant = max_per_tenant or (concurrency + max_queue)
        self.waiting = 0
        self.active = 0
        self.rejected = 0
        self.rejected_by_reason: dict[str, int] = defaultdict(int)
        self.per_tenant: dict[str, int] = defaultdict(int)

    def snapshot(self) -> dict:
        return {
            "concurrency": self.concurrency,
            "active": self.active,
            "waiting": self.waiting,
            "max_queue": self.max_queue,
            "max_per_tenant": self.max_per_tenant,
            "rejected_total": self.rejected,
            "rejected_by_reason": dict(self.rejected_by_reason),
        }

    def _reject(self, reason: str, retry_after_s: int) -> Saturated:
        self.rejected += 1
        self.rejected_by_reason[reason] += 1
        return Saturated(reason, retry_after_s=retry_after_s)

    @asynccontextmanager
    async def slot(self, tenant_id: str = "", timeout_s: float | None = None):
        if self.active >= self.concurrency and self.waiting >= self.max_queue:
            raise self._reject("queue_full", 15)
        if tenant_id and self.per_tenant[tenant_id] >= self.max_per_tenant:
            raise self._reject("tenant_limit", 15)
        wait_limit = self.queue_timeout_s if timeout_s is None else max(0.0, min(self.queue_timeout_s, timeout_s))
        self.per_tenant[tenant_id] += 1
        self.waiting += 1
        started = time.perf_counter()
        try:
            try:
                await asyncio.wait_for(self._sem.acquire(), timeout=wait_limit)
            except asyncio.TimeoutError:
                raise self._reject("queue_timeout", 30) from None
            finally:
                self.waiting -= 1
            self.active += 1
            try:
                yield int((time.perf_counter() - started) * 1000)
            finally:
                self.active -= 1
                self._sem.release()
        finally:
            self.per_tenant[tenant_id] -= 1
            if self.per_tenant[tenant_id] <= 0:
                self.per_tenant.pop(tenant_id, None)
