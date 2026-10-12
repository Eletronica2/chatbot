import json
import os
import statistics
import uuid
from pathlib import Path

import httpx

API = os.environ.get("BENCH_API", "http://127.0.0.1:8100")
FIXTURES = Path(__file__).resolve().parent.parent / "fixtures"
TENANTS = ("pizzaria_bella_massa", "pastelaria_do_ze")


def token(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"variável {name} ausente (carregar secrets/tokens.env)")
    return value


TOKENS = {"pizzaria_bella_massa": "TOKEN_BELLA", "pastelaria_do_ze": "TOKEN_ZE"}


def client(timeout: float = 300.0) -> httpx.Client:
    return httpx.Client(base_url=API, timeout=timeout)


def headers(token_env: str) -> dict:
    return {"Authorization": f"Bearer {token(token_env)}"}


def business(tenant: str) -> dict:
    return json.loads((FIXTURES / tenant / "business_context.json").read_text(encoding="utf-8"))


def documents(tenant: str) -> list[dict]:
    return json.loads((FIXTURES / tenant / "documents.json").read_text(encoding="utf-8"))


def respond_payload(tenant: str | None, message: str, **extra) -> dict:
    body = {"request_id": str(uuid.uuid4()), "conversation_id": str(uuid.uuid4()), "message": message,
            "recent_history": extra.pop("history", []), "flow_context": extra.pop("flow_context", {}),
            "business_context": extra.pop("business_context", business(tenant) if tenant else {}),
            "options": extra.pop("options", {})}
    if tenant is not None:
        body["tenant_id"] = tenant
    body.update(extra)
    return body


def seed(c: httpx.Client) -> dict:
    out = {}
    for tenant in TENANTS:
        r = c.post("/v1/knowledge/upsert", headers=headers(TOKENS[tenant]),
                   json={"tenant_id": tenant, "documents": documents(tenant)})
        r.raise_for_status()
        out[tenant] = r.json()["results"]
    return out


def pct(values: list[float], p: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    k = (len(values) - 1) * p
    lo, hi = int(k), min(int(k) + 1, len(values) - 1)
    return round(values[lo] + (values[hi] - values[lo]) * (k - lo), 1)


def summary(values: list[float]) -> dict:
    if not values:
        return {}
    return {"n": len(values), "mean": round(statistics.mean(values), 1), "p50": pct(values, 0.5),
            "p95": pct(values, 0.95), "min": round(min(values), 1), "max": round(max(values), 1)}
