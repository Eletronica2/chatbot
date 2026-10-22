"""Link the Atende Ai (verified portfolio) Meta test number to the Bella Massa demo tenant via the official API.

Additive only: creates one whatsapp_accounts row (audited as whatsapp_account.create) with is_default=false, so the
existing 3594 account is untouched. Uses the Atende Ai System User token from settings; never prints it.
Usage inside backend-api:  python - < scripts/ia03_link_atendeai_test_number.py
"""
import json
import urllib.request

from app.config.settings import settings
from app.security.jwt_tools import create_access_token

TENANT = "pizzaria_bella_massa"
payload = {
    "account_key": "27281965408107469",
    "display_name": "Atende Ai — número de teste Meta",
    "phone_number_id": "1201264079728608",
    "display_phone_number": "+1 555-656-7513",
    "access_token": (settings.META_SYSTEM_USER_TOKEN or "").strip(),
    "status": "active",
    "is_default": False,
}
if not payload["access_token"]:
    raise SystemExit("META_SYSTEM_USER_TOKEN ausente")
token = create_access_token(
    {"sub": "ia03-operator", "tenant_id": settings.DEFAULT_TENANT_ID, "email": "ia03-operator@meuatendeai.com.br",
     "display_name": "IA-03 Operator", "role": "superadmin"},
    secret_key=settings.APP_SECRET_KEY, expires_in_minutes=5,
)
request = urllib.request.Request(
    f"http://127.0.0.1:8000/api/v1/tenants/{TENANT}/whatsapp-accounts", data=json.dumps(payload).encode(),
    method="POST", headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
with urllib.request.urlopen(request, timeout=20) as response:
    body = json.loads(response.read())
print(f"HTTP {response.status} account_key={body.get('account_key')} phone_number_id={body.get('phone_number_id')} "
      f"status={body.get('status')} is_default={body.get('is_default')} has_token={body.get('has_access_token')}")
