import json
import re
import time
from dataclasses import dataclass

import httpx

_THINK_RE = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)


def strip_thinking(text: str) -> str:
    text = _THINK_RE.sub("", text)
    if "<think>" in text.lower():
        text = text[: text.lower().index("<think>")]
    return text.replace("</think>", "").strip()


@dataclass
class Generation:
    text: str
    model: str
    prompt_tokens: int
    completion_tokens: int
    load_ms: int
    first_token_ms: int | None
    total_ms: int
    eval_ms: int
    prompt_eval_ms: int

    @property
    def tokens_per_s(self) -> float | None:
        if self.eval_ms <= 0 or self.completion_tokens <= 0:
            return None
        return round(self.completion_tokens / (self.eval_ms / 1000), 2)


class OllamaError(Exception):
    pass


class OllamaClient:
    def __init__(self, base_url: str, timeout_s: float):
        self.base_url = base_url.rstrip("/")
        self._client = httpx.AsyncClient(base_url=self.base_url, timeout=httpx.Timeout(timeout_s, connect=5.0))
        self._capabilities: dict[str, set[str]] = {}

    async def close(self) -> None:
        await self._client.aclose()

    async def list_models(self) -> list[str]:
        r = await self._client.get("/api/tags")
        r.raise_for_status()
        return [m["name"] for m in r.json().get("models", [])]

    async def show(self, model: str) -> dict:
        r = await self._client.post("/api/show", json={"model": model})
        r.raise_for_status()
        return r.json()

    async def capabilities(self, model: str) -> set[str]:
        if model not in self._capabilities:
            info = await self.show(model)
            self._capabilities[model] = set(info.get("capabilities") or [])
        return self._capabilities[model]

    async def chat(
        self,
        model: str,
        messages: list[dict],
        *,
        num_ctx: int,
        temperature: float,
        max_tokens: int,
        keep_alive: str,
    ) -> Generation:
        payload: dict = {
            "model": model,
            "messages": messages,
            "stream": True,
            "keep_alive": keep_alive,
            "options": {
                "num_ctx": num_ctx,
                "temperature": temperature,
                "num_predict": max_tokens,
                "top_p": 0.8,
                "top_k": 20,
                "repeat_penalty": 1.05,
            },
        }
        if "thinking" in await self.capabilities(model):
            payload["think"] = False

        started = time.perf_counter()
        first_token_ms: int | None = None
        parts: list[str] = []
        final: dict = {}
        async with self._client.stream("POST", "/api/chat", json=payload) as resp:
            if resp.status_code != 200:
                body = (await resp.aread()).decode("utf-8", "replace")[:300]
                raise OllamaError(f"ollama_http_{resp.status_code}: {body}")
            async for line in resp.aiter_lines():
                if not line:
                    continue
                chunk = json.loads(line)
                if "error" in chunk:
                    raise OllamaError(str(chunk["error"])[:300])
                piece = chunk.get("message", {}).get("content", "")
                if piece:
                    if first_token_ms is None:
                        first_token_ms = int((time.perf_counter() - started) * 1000)
                    parts.append(piece)
                if chunk.get("done"):
                    final = chunk
        total_ms = int((time.perf_counter() - started) * 1000)
        return Generation(
            text=strip_thinking("".join(parts)),
            model=final.get("model", model),
            prompt_tokens=int(final.get("prompt_eval_count", 0)),
            completion_tokens=int(final.get("eval_count", 0)),
            load_ms=int(final.get("load_duration", 0) / 1e6),
            first_token_ms=first_token_ms,
            total_ms=total_ms,
            eval_ms=int(final.get("eval_duration", 0) / 1e6),
            prompt_eval_ms=int(final.get("prompt_eval_duration", 0) / 1e6),
        )
