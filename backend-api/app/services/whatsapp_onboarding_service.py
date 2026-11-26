"""Embedded Signup onboarding for WhatsApp Business accounts."""
from __future__ import annotations

import re
from typing import Any

from app.domain.whatsapp_account import WhatsAppAccount
from app.services.meta_graph_service import MetaGraphService
from app.services.whatsapp_account_service import WhatsAppAccountService
from app.config.settings import settings

# Never inject Atende Ai's own Meta portfolio into a customer Embedded Signup.
_ATENDE_AI_BUSINESS_PORTFOLIO_ID = "506485032393364"
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_HTTP_URL_RE = re.compile(r"^https?://[^\s]+$", re.IGNORECASE)


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


def build_business_setup(
    *,
    tenant_name: str | None = None,
    tenant_email: str | None = None,
    website: str | None = None,
    country: str | None = None,
    timezone: str | None = None,
    business_portfolio_id: str | None = None,
    street_address1: str | None = None,
    city: str | None = None,
    state: str | None = None,
    zip_postal: str | None = None,
) -> dict[str, Any]:
    """Build extras.setup.business using only known, non-empty values. Never invent fields."""
    business: dict[str, Any] = {}
    portfolio = str(business_portfolio_id or "").strip()
    if portfolio and portfolio != _ATENDE_AI_BUSINESS_PORTFOLIO_ID and portfolio.isdigit():
        # Existing customer portfolio: Meta fills the rest; ignore other injected fields.
        return {"id": portfolio}

    name = str(tenant_name or "").strip()
    if name:
        business["name"] = name[:75]
    email = str(tenant_email or "").strip().lower()
    if email and _EMAIL_RE.match(email):
        business["email"] = email
    site = str(website or "").strip()
    if site and _HTTP_URL_RE.match(site):
        business["website"] = site
    tz = str(timezone or "").strip()
    if tz and tz.upper().startswith("UTC"):
        business["timezone"] = tz
    address: dict[str, Any] = {}
    if str(street_address1 or "").strip():
        address["streetAddress1"] = str(street_address1).strip()
    if str(city or "").strip():
        address["city"] = str(city).strip()
    if str(state or "").strip():
        address["state"] = str(state).strip()
    if str(zip_postal or "").strip():
        address["zipPostal"] = str(zip_postal).strip()
    country_code = str(country or "").strip().upper()
    if len(country_code) == 2 and country_code.isalpha():
        address["country"] = country_code
    if address:
        business["address"] = address
    return business


def resolve_messaging_account_id(
    *,
    waba_id: str | None = None,
    messaging_account_id: str | None = None,
    messaging_account_ids: list[str] | None = None,
) -> str:
    """v5 messaging_account_ids replace waba_id; values are the same ID family as legacy WABAs."""
    for candidate in (
        str(messaging_account_id or "").strip(),
        str(waba_id or "").strip(),
    ):
        if candidate.isdigit():
            return candidate
    for item in messaging_account_ids or []:
        value = str(item or "").strip()
        if value.isdigit():
            return value
    raise ValueError("Meta nao retornou messaging_account_id/WABA valido")


class WhatsAppOnboardingService:
    def __init__(
        self,
        meta_graph: MetaGraphService,
        whatsapp_account_service: WhatsAppAccountService,
        database=None,
    ):
        self.meta_graph = meta_graph
        self.whatsapp_account_service = whatsapp_account_service
        self.database = database

    def embedded_signup_config(self, *, tenant_id: str | None = None) -> dict:
        setup: dict[str, Any] = {}
        business = self._tenant_business_setup(tenant_id)
        if business:
            setup["business"] = business
        return {
            "app_id": settings.META_APP_ID,
            "config_id": settings.META_EMBEDDED_CONFIG_ID,
            "coexistence_feature_type": "whatsapp_business_app_onboarding",
            "embedded_signup_version": "v5",
            "website_optional": False,
            "extras": {
                "setup": setup,
                "version": "v5",
            },
        }

    def _tenant_business_setup(self, tenant_id: str | None) -> dict[str, Any]:
        if not tenant_id or self.database is None:
            return {}
        row = self.database.fetch_one(
            "SELECT name, email FROM tenants WHERE external_key=%s LIMIT 1",
            (tenant_id,),
        )
        if not row:
            return {}
        return build_business_setup(
            tenant_name=str(row.get("name") or ""),
            tenant_email=str(row.get("email") or ""),
        )

    def embedded_signup_preflight(self) -> dict:
        app_id = settings.META_APP_ID
        return {
            "app_id": app_id,
            "config_id": settings.META_EMBEDDED_CONFIG_ID,
            "app_secret_configured": bool((settings.META_APP_SECRET or "").strip()),
            "system_user_token_configured": bool((settings.META_SYSTEM_USER_TOKEN or "").strip()),
            "verify_token": settings.META_VERIFY_TOKEN,
            "coexistence_feature_type": "whatsapp_business_app_onboarding",
            "embedded_signup_version": "v5",
            "website_optional": False,
            "meta_links": {
                "app_domains": f"https://developers.facebook.com/apps/{app_id}/settings/basic/",
                "fb_login_for_business": f"https://developers.facebook.com/apps/{app_id}/fb-login/settings/",
                "whatsapp_webhook": f"https://developers.facebook.com/apps/{app_id}/whatsapp-business/wa-settings/",
                "whatsapp_api_setup": f"https://developers.facebook.com/apps/{app_id}/whatsapp-business/wa-dev-console/",
                "login_configurations": f"https://developers.facebook.com/apps/{app_id}/fb-login/configs/",
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
        messaging_account_id: str | None = None,
        messaging_account_ids: list[str] | None = None,
        business_id: str | None = None,
        is_on_biz_app: bool | None = None,
    ) -> dict:
        messaging_id = resolve_messaging_account_id(
            waba_id=waba_id,
            messaging_account_id=messaging_account_id,
            messaging_account_ids=messaging_account_ids,
        )
        if business_id and str(business_id).strip() == _ATENDE_AI_BUSINESS_PORTFOLIO_ID:
            raise ValueError("Portfólio Meta inválido para este tenant")

        access_token = await self.meta_graph.exchange_code_for_token(code, redirect_uri=redirect_uri)
        await self.meta_graph.assert_phone_on_messaging_account(
            messaging_account_id=messaging_id,
            phone_number_id=phone_number_id,
            access_token=access_token,
        )
        await self.meta_graph.subscribe_waba_webhooks(messaging_id, access_token)
        try:
            phone_status = await self.meta_graph.get_phone_number_status(phone_number_id, access_token)
        except ValueError:
            phone_status = {}
        if is_on_biz_app is None and isinstance(phone_status.get("is_on_biz_app"), bool):
            is_on_biz_app = bool(phone_status.get("is_on_biz_app"))
        coexistence_effective = bool(coexistence if is_on_biz_app is None else is_on_biz_app)
        pretty_phone, pretty_name = resolve_signup_display_fields(
            phone_number_id=phone_number_id,
            display_phone_number=display_phone_number,
            display_name=display_name,
            phone_status=phone_status,
        )
        account = await self.whatsapp_account_service.save_account(
            tenant_id,
            account_key=messaging_id,
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
            "coexistence": coexistence_effective,
            "phone_status": phone_status,
            "skip_register": coexistence_effective,
            "messaging_account_id": messaging_id,
            "business_id": business_id,
        }
