"""Embedded Signup onboarding for WhatsApp Business accounts."""
from __future__ import annotations

from app.domain.whatsapp_account import WhatsAppAccount
from app.services.meta_graph_service import MetaGraphService
from app.services.whatsapp_account_service import WhatsAppAccountService
from app.config.settings import settings


class WhatsAppOnboardingService:
    def __init__(
        self,
        meta_graph: MetaGraphService,
        whatsapp_account_service: WhatsAppAccountService,
    ):
        self.meta_graph = meta_graph
        self.whatsapp_account_service = whatsapp_account_service

    def embedded_signup_config(self) -> dict:
        return {
            "app_id": settings.META_APP_ID,
            "config_id": settings.META_EMBEDDED_CONFIG_ID,
            "coexistence_feature_type": "whatsapp_business_app_onboarding",
            "session_info_version": "3",
        }

    async def complete_embedded_signup(
        self,
        *,
        tenant_id: str,
        code: str,
        waba_id: str,
        phone_number_id: str,
        display_phone_number: str,
        display_name: str,
        verify_token: str | None,
        coexistence: bool = True,
        redirect_uri: str | None = None,
    ) -> dict:
        access_token = await self.meta_graph.exchange_code_for_token(code, redirect_uri=redirect_uri)
        await self.meta_graph.subscribe_waba_webhooks(waba_id, access_token)
        account = await self.whatsapp_account_service.save_account(
            tenant_id,
            account_key=waba_id,
            display_name=display_name,
            phone_number_id=phone_number_id,
            display_phone_number=display_phone_number,
            verify_token=verify_token or settings.META_VERIFY_TOKEN,
            access_token=access_token,
            status="active",
            is_default=True,
        )
        phone_status = await self.meta_graph.get_phone_number_status(phone_number_id, access_token)
        return {
            "account": account,
            "coexistence": coexistence,
            "phone_status": phone_status,
            "skip_register": coexistence,
        }
