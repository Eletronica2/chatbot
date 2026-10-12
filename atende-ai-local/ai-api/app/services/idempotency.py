import asyncio
import time
from collections import OrderedDict
from typing import Awaitable, Callable, TypeVar

T = TypeVar("T")


class IdempotencyCache:
    """Successful results keyed by (caller, tenant, request_id). Failures are not cached so a retry runs again."""

    def __init__(self, ttl_s: float, max_entries: int = 2000):
        self.ttl_s = ttl_s
        self.max_entries = max_entries
        self._done: OrderedDict[str, tuple[float, object]] = OrderedDict()
        self._inflight: dict[str, asyncio.Future] = {}
        self.hits = 0

    def _evict(self, now: float) -> None:
        while self._done and (len(self._done) > self.max_entries or next(iter(self._done.values()))[0] < now):
            self._done.popitem(last=False)

    async def run(self, key: str, fn: Callable[[], Awaitable[T]]) -> tuple[T, bool]:
        now = time.monotonic()
        self._evict(now)
        cached = self._done.get(key)
        if cached and cached[0] >= now:
            self.hits += 1
            return cached[1], True
        pending = self._inflight.get(key)
        if pending is not None:
            self.hits += 1
            return await asyncio.shield(pending), True
        future: asyncio.Future = asyncio.get_running_loop().create_future()
        self._inflight[key] = future
        try:
            result = await fn()
        except asyncio.CancelledError:
            future.cancel()
            raise
        except BaseException as exc:
            future.set_exception(exc)
            future.exception()
            raise
        finally:
            self._inflight.pop(key, None)
        future.set_result(result)
        self._done[key] = (time.monotonic() + self.ttl_s, result)
        return result, False
