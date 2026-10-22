"""Set the Bella Massa auto-reply mode through the Superadmin API (audited as tenant.auto_reply.update).

Usage inside backend-api:  python - allowlist 5534992665547 < scripts/ia03_bella_auto_reply.py
                           python - off < scripts/ia03_bella_auto_reply.py
Prints only the mode and the allowlist count returned by the API.
"""
import json
import sys
import urllib.request

from app.config.settings import settings
from app.security.jwt_tools import create_access_token

TENANT = "pizzaria_bella_massa"
mode, numbers = sys.argv[1], sys.argv[2:]
if mode not in ("off", "allowlist") or (mode == "allowlist" and not numbers):
    raise SystemExit("modo: off | allowlist <numeros>")
token = create_access_token(
    {"sub": "ia03-operator", "tenant_id": settings.DEFAULT_TENANT_ID, "email": "ia03-operator@meuatendeai.com.br",
     "display_name": "IA-03 Operator", "role": "superadmin"},
    secret_key=settings.APP_SECRET_KEY, expires_in_minutes=5,
)
payload = {"auto_reply_mode": mode}
if numbers:
    payload["auto_reply_allowlist"] = numbers
request = urllib.request.Request(
    f"http://127.0.0.1:8000/api/v1/tenants/{TENANT}/settings", data=json.dumps(payload).encode(), method="PATCH",
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
with urllib.request.urlopen(request, timeout=20) as response:
    body = json.loads(response.read())
print(f"HTTP {response.status} mode={body['auto_reply_mode']} allowlist_count={body['auto_reply_allowlist_count']} "
      f"ai_provider={body.get('ai_provider')} local_ai_enabled={body.get('local_ai_enabled')}")
