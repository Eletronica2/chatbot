"""Hand the Bella Massa pilot conversation back to the AI via the official route (audited conversation.return_to_ai).

A manual reply from the panel makes the conversation human-owned, so the bot stays silent there by design.
Only the conversation of the allowlisted pilot number is touched. Prints masked data only.
Usage inside backend-api:  python - < scripts/ia03_bella_return_to_ai.py
"""
import json
import urllib.parse
import urllib.request

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.security.jwt_tools import create_access_token

TENANT, PILOT = "pizzaria_bella_massa", "5534992665547"

db = MySQLDatabase(settings.DATABASE_URL)
row = db.fetch_one("SELECT s.phone_number, s.assignment_mode FROM sessions s JOIN tenants t ON t.id=s.tenant_id "
                   "WHERE t.external_key=%s AND s.phone_number=%s", (TENANT, PILOT))
if row is None:
    raise SystemExit("conversa piloto não encontrada")
print(f"antes: assignment_mode={row['assignment_mode']}")
token = create_access_token(
    {"sub": "ia03-operator", "tenant_id": settings.DEFAULT_TENANT_ID, "email": "ia03-operator@meuatendeai.com.br",
     "display_name": "IA-03 Operator", "role": "superadmin"},
    secret_key=settings.APP_SECRET_KEY, expires_in_minutes=5,
)
conversation_id = urllib.parse.quote(f"{TENANT}:{PILOT}", safe="")
request = urllib.request.Request(f"http://127.0.0.1:8000/api/v1/conversations/{conversation_id}/return-to-ai",
                                 data=b"{}", method="POST",
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
with urllib.request.urlopen(request, timeout=20) as response:
    body = json.loads(response.read())
after = db.fetch_one("SELECT s.assignment_mode, s.assigned_user_id FROM sessions s JOIN tenants t ON t.id=s.tenant_id "
                     "WHERE t.external_key=%s AND s.phone_number=%s", (TENANT, PILOT))
print(f"HTTP {response.status} ai_enabled={body.get('ai_enabled')} depois: assignment_mode={after['assignment_mode']} "
      f"assigned_user_id={after['assigned_user_id']}")
