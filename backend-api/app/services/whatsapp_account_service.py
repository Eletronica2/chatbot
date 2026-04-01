"""Service for tenant WhatsApp account management and resolution."""
from __future__ import annotations

from app.domain.whatsapp_account import (
    WhatsAppAccount,
    WhatsAppAccountCreate,
    WhatsAppAccountSecret,
    WhatsAppAccountUpdate,
)
from app.repositories.whatsapp_account_repository import WhatsAppAccountRepository
from app.security.crypto import TokenCipher


class WhatsAppAccountService:
    def __init__(self, repository: WhatsAppAccountRepository, cipher: TokenCipher):
        self.repository = repository
        self.cipher = cipher

    async def list_accounts(self, tenant_id: str) -> list[WhatsAppAccount]:
        rows = await self.repository.list_by_tenant(tenant_id)
        return [self._to_domain(row) for row in rows]

    async def save_account(
        self,
        tenant_id: str,
        *,
        account_key: str,
        display_name: str,
        phone_number_id: str,
        display_phone_number: str,
        verify_token: str | None,
        access_token: str | None,
        status: str,
        is_default: bool,
    ) -> WhatsAppAccount:
        encrypted = self.cipher.encrypt(access_token) if access_token else None
        await self.repository.upsert(
            tenant_id=tenant_id,
            account_key=account_key,
            display_name=display_name,
            phone_number_id=phone_number_id,
            display_phone_number=display_phone_number,
            verify_token=verify_token,
            encrypted_access_token=encrypted,
            status=status,
            is_default=is_default,
        )
        row = await self.repository.get_for_tenant(tenant_id, account_key)
        return self._to_domain(row or {})

    async def create_account(self, tenant_id: str, payload: WhatsAppAccountCreate) -> WhatsAppAccount:
        return await self.save_account(
            tenant_id,
            account_key=payload.account_key,
            display_name=payload.display_name,
            phone_number_id=payload.phone_number_id,
            display_phone_number=payload.display_phone_number,
            verify_token=payload.verify_token,
            access_token=payload.access_token,
            status=payload.status,
            is_default=payload.is_default,
        )

    async def update_account(
        self,
        tenant_id: str,
        account_key: str,
        payload: WhatsAppAccountUpdate,
    ) -> WhatsAppAccount:
        current = await self.repository.get_for_tenant(tenant_id, account_key)
        if current is None:
            raise ValueError("Conta WhatsApp nao encontrada")
        return await self.save_account(
            tenant_id,
            account_key=account_key,
            display_name=payload.display_name or str(current.get("display_name") or account_key),
            phone_number_id=payload.phone_number_id or str(current.get("phone_number_id") or ""),
            display_phone_number=payload.display_phone_number or str(current.get("display_phone_number") or ""),
            verify_token=payload.verify_token if payload.verify_token is not None else current.get("verify_token"),
            access_token=payload.access_token,
            status=payload.status or str(current.get("status") or "active"),
            is_default=bool(current.get("is_default")) if payload.is_default is None else bool(payload.is_default),
        )

    async def resolve_for_phone_number_id(self, phone_number_id: str) -> WhatsAppAccountSecret | None:
        row = await self.repository.resolve_active_account(phone_number_id=phone_number_id)
        if row is None:
            return None
        return self._to_secret(row)

    async def resolve_for_tenant(self, tenant_id: str) -> WhatsAppAccountSecret | None:
        row = await self.repository.resolve_active_account(tenant_id=tenant_id)
        if row is None:
            return None
        return self._to_secret(row)

    async def validate_verify_token(self, verify_token: str) -> bool:
        row = await self.repository.resolve_active_account(verify_token=verify_token)
        return row is not None

    def _to_domain(self, row: dict) -> WhatsAppAccount:
        encrypted = row.get("access_token_encrypted")
        masked = None
        if encrypted:
            decrypted = self.cipher.decrypt(str(encrypted))
            masked = self._mask_token(decrypted)
        return WhatsAppAccount(
            account_id=str(row.get("id") or ""),
            tenant_id=str(row.get("tenant_id") or ""),
            account_key=str(row.get("account_key") or ""),
            display_name=str(row.get("display_name") or ""),
            phone_number_id=str(row.get("phone_number_id") or ""),
            display_phone_number=str(row.get("display_phone_number") or ""),
            verify_token=row.get("verify_token"),
            status=str(row.get("status") or "active"),
            is_default=bool(row.get("is_default")),
            has_access_token=bool(encrypted),
            masked_access_token=masked,
            created_at=row.get("created_at"),
            updated_at=row.get("updated_at"),
        )

    def _to_secret(self, row: dict) -> WhatsAppAccountSecret:
        account = self._to_domain(row)
        access_token = self.cipher.decrypt(row.get("access_token_encrypted")) if row.get("access_token_encrypted") else None
        return WhatsAppAccountSecret(account=account, access_token=access_token)

    def _mask_token(self, token: str | None) -> str | None:
        if not token:
            return None
        if len(token) <= 10:
            return "*" * len(token)
        return f"{token[:4]}...{token[-4:]}"

