"""Embedded Signup onboarding for WhatsApp Business accounts."""
from __future__ import annotations

from app.domain.whatsapp_account import WhatsAppAccount
from app.services.meta_graph_service import MetaGraphService
from app.services.whatsapp_account_service import WhatsAppAccountService
from app.config.settings import settings


def resolve_signup_display_fields(
    *,
    phone_number_id: str,
    display_phone_number: str,
    display_name: str,
    phone_status: dict | None,
) -> tuple[str, str]:
    status = phone_status or {}
    graph_phone = str(status.get("display_phone_number") or "").strip()
    graph_name = str(status.get("verified_name") or "").strip()
    incoming_phone = str(display_phone_number or "").strip()
    phone = graph_phone or incoming_phone
    if not phone or phone == phone_number_id:
        phone = graph_phone or incoming_phone or phone_number_id
    incoming_name = str(display_name or "").strip()
    placeholder_names = {
        "",
        "WhatsApp",
        f"WhatsApp {phone_number_id}",
        f"WhatsApp {incoming_phone}",
    }
    if incoming_name in placeholder_names or incoming_name.endswith(phone_number_id):
        name = graph_name or (f"WhatsApp {phone}" if phone else "WhatsApp")
    else:
        name = incoming_name
    return phone, name


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
            "embedded_signup_version": "v3",
            "extras": {
                "setup": {},
                "featureType": "whatsapp_business_app_onboarding",
                "sessionInfoVersion": "3",
                "version": "v3",
            },
        }

    def embedded_signup_preflight(self) -> dict:
        app_id = settings.META_APP_ID
        return {
            "app_id": app_id,
            "config_id": settings.META_EMBEDDED_CONFIG_ID,
            "app_secret_configured": bool((settings.META_APP_SECRET or "").strip()),
            "system_user_token_configured": bool((settings.META_SYSTEM_USER_TOKEN or "").strip()),
            "verify_token": settings.META_VERIFY_TOKEN,
            "coexistence_feature_type": "whatsapp_business_app_onboarding",
            "session_info_version": "3",
            "meta_links": {
                "app_domains": f"https://developers.facebook.com/apps/{app_id}/settings/basic/",
                "fb_login_for_business": f"https://developers.facebook.com/apps/{app_id}/fb-login/settings/",
                "whatsapp_webhook": f"https://developers.facebook.com/apps/{app_id}/whatsapp-business/wa-settings/",
                "whatsapp_api_setup": f"https://developers.facebook.com/apps/{app_id}/whatsapp-business/wa-dev-console/",
            },
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
        try:
            phone_status = await self.meta_graph.get_phone_number_status(phone_number_id, access_token)
        except ValueError:
            phone_status = {}
        pretty_phone, pretty_name = resolve_signup_display_fields(
            phone_number_id=phone_number_id,
            display_phone_number=display_phone_number,
            display_name=display_name,
            phone_status=phone_status,
        )
        account = await self.whatsapp_account_service.save_account(
            tenant_id,
            account_key=waba_id,
            display_name=pretty_name,
            phone_number_id=phone_number_id,
            display_phone_number=pretty_phone,
            verify_token=verify_token or settings.META_VERIFY_TOKEN,
            access_token=access_token,
            status="active",
            is_default=True,
        )
        return {
            "account": account,
            "coexistence": coexistence,
            "phone_status": phone_status,
            "skip_register": coexistence,
        }
