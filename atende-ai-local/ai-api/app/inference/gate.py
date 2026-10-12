import asyncio
import time
from contextlib import asynccontextmanager


class Saturated(Exception):
    def __init__(self, reason: str, retry_after_s: int):
        super().__init__(reason)
        self.reason = reason
        self.retry_after_s = retry_after_s


class InferenceGate:
    """Bounded concurrency + bounded queue. Over capacity -> Saturated (HTTP 503)."""

    def __init__(self, concurrency: int, max_queue: int, queue_timeout_s: float):
        self._sem = asyncio.Semaphore(concurrency)
        self.concurrency = concurrency
        self.max_queue = max_queue
        self.queue_timeout_s = queue_timeout_s
        self.waiting = 0
        self.active = 0
        self.rejected = 0

    def snapshot(self) -> dict:
        return {
            "concurrency": self.concurrency,
            "active": self.active,
            "waiting": self.waiting,
            "max_queue": self.max_queue,
            "rejected_total": self.rejected,
        }

    @asynccontextmanager
    async def slot(self):
        if self.active >= self.concurrency and self.waiting >= self.max_queue:
            self.rejected += 1
            raise Saturated("queue_full", retry_after_s=15)
        self.waiting += 1
        started = time.perf_counter()
        try:
            await asyncio.wait_for(self._sem.acquire(), timeout=self.queue_timeout_s)
        except asyncio.TimeoutError:
            self.rejected += 1
            raise Saturated("queue_timeout", retry_after_s=30) from None
        finally:
            self.waiting -= 1
        self.active += 1
        try:
            yield int((time.perf_counter() - started) * 1000)
        finally:
            self.active -= 1
            self._sem.release()
