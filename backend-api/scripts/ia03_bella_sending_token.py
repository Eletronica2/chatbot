"""Pilot measure (temporary, reversible): Bella Massa account sends with the partner System User token.

Why: the Embedded Signup business token is rejected by Meta for sending (#10 granular permission) while the app
lacks Advanced Access for whatsapp_business_messaging; the partner System User token is accepted for this WABA.
Scope: only whatsapp_accounts row of tenant pizzaria_bella_massa / WABA 1299741078262298. Nothing global changes.

Usage inside backend-api:
    python - apply   < scripts/ia03_bella_sending_token.py   -> prints the previous ENCRYPTED value for backup
    python - restore < ...  (reads the previous encrypted value from env PREVIOUS_ENCRYPTED_TOKEN)
Never prints a plaintext token.
"""
import asyncio
import os
import sys

from app.config.settings import settings
from app.db.mysql import MySQLDatabase
from app.domain.whatsapp_account import WhatsAppAccountUpdate
from app.repositories.whatsapp_account_repository import WhatsAppAccountRepository
from app.security.crypto import TokenCipher
from app.services.admin_audit_service import AdminAuditService
from app.services.meta_graph_service import MetaGraphService
from app.services.whatsapp_account_service import WhatsAppAccountService

TENANT, WABA, PHONE_NUMBER_ID = "pizzaria_bella_massa", "1299741078262298", "1155710810954749"


async def main(mode: str) -> None:
    db = MySQLDatabase(settings.DATABASE_URL)
    service = WhatsAppAccountService(WhatsAppAccountRepository(db), TokenCipher(settings.APP_SECRET_KEY), MetaGraphService())
    row = db.fetch_one("SELECT wa.id, wa.access_token_encrypted FROM whatsapp_accounts wa JOIN tenants t ON t.id=wa.tenant_id "
                       "WHERE t.external_key=%s AND wa.account_key=%s AND wa.phone_number_id=%s",
                       (TENANT, WABA, PHONE_NUMBER_ID))
    if row is None:
        raise SystemExit("conta Bella não encontrada")
    if mode == "apply":
        partner = (settings.META_SYSTEM_USER_TOKEN or "").strip()
        if not partner:
            raise SystemExit("META_SYSTEM_USER_TOKEN ausente")
        print("PREVIOUS_ENCRYPTED_TOKEN=" + str(row["access_token_encrypted"]))
        await service.update_account(TENANT, WABA, WhatsAppAccountUpdate(access_token=partner))
        action, summary = "whatsapp_account.sending_token.pilot_partner", (
            "Piloto: conta Bella envia com o token System User do parceiro (Embedded Signup recusado pela Meta #10)")
    elif mode == "restore":
        previous = os.environ.get("PREVIOUS_ENCRYPTED_TOKEN", "").strip()
        if not previous:
            raise SystemExit("PREVIOUS_ENCRYPTED_TOKEN ausente")
        db.execute("UPDATE whatsapp_accounts SET access_token_encrypted=%s WHERE id=%s", (previous, row["id"]))
        action, summary = "whatsapp_account.sending_token.restore", "Token de envio da conta Bella restaurado"
    else:
        raise SystemExit("modo: apply | restore")
    await AdminAuditService(db).append(tenant_id=TENANT, action=action, entity_type="whatsapp_account", entity_key=WABA,
                                       summary=summary, metadata={"phone_number_id": PHONE_NUMBER_ID, "temporary": True})
    print(f"{mode}: ok")


asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else ""))
