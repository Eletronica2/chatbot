"""Manage WhatsApp message templates via Meta Graph API."""
from __future__ import annotations

import re
from typing import TYPE_CHECKING, Any
from uuid import uuid4

import httpx

from app.config.settings import settings
from app.utils.phone_utils import normalize_whatsapp_phone
from app.domain.whatsapp_template import (
    WhatsAppTemplate,
    WhatsAppTemplateCreate,
    WhatsAppTemplateSend,
    WhatsAppTemplateSendResult,
)
from app.services.meta_graph_service import MetaGraphService
from app.services.whatsapp_account_service import WhatsAppAccountService

if TYPE_CHECKING:
    from app.services.whatsapp_template_status_service import WhatsAppTemplateStatusService


class WhatsAppTemplateService:
    def __init__(
        self,
        meta_graph: MetaGraphService,
        whatsapp_account_service: WhatsAppAccountService,
        template_status_service: WhatsAppTemplateStatusService | None = None,
    ):
        self.meta_graph = meta_graph
        self.whatsapp_account_service = whatsapp_account_service
        self.template_status_service = template_status_service

    @staticmethod
    def _body_variable_count(body_text: str | None) -> int:
        if not body_text:
            return 0
        matches = re.findall(r"\{\{(\d+)\}\}", body_text)
        if not matches:
            return 0
        return max(int(item) for item in matches)

    async def _access_token(
        self,
        tenant_id: str,
        account_key: str | None,
    ) -> tuple[str, str, bool]:
        resolved_key, token, refreshed = await self.whatsapp_account_service.ensure_fresh_access_token(
            tenant_id,
            account_key,
        )
        return resolved_key, token, refreshed

    async def _messaging_account_token(
        self,
        tenant_id: str,
        account_key: str | None,
    ) -> tuple[str, str]:
        """Token OAuth da conta do tenant (não substitui por system user). account_key = messaging/WABA id."""
        accounts = await self.whatsapp_account_service.list_accounts(tenant_id)
        if not accounts:
            raise ValueError("Nenhuma conta WhatsApp vinculada a esta empresa")
        selected = None
        if account_key:
            selected = next((item for item in accounts if item.account_key == account_key), None)
            if selected is None:
                raise ValueError("Conta WhatsApp nao encontrada")
        else:
            selected = next((item for item in accounts if item.is_default), None) or accounts[0]
        messaging_id = selected.account_key.strip()
        secret = await self.whatsapp_account_service.resolve_for_account_key(tenant_id, messaging_id)
        token = (secret.access_token or "").strip() if secret else ""
        if not token:
            raise ValueError(
                "Token de integracao da conta WhatsApp ausente. Reconecte via Embedded Signup (token BISU/USER)."
            )
        await self._assert_template_token(token, messaging_id)
        return messaging_id, token

    @staticmethod
    def _token_manages_waba(debug_data: dict[str, Any], messaging_id: str) -> bool:
        waba = messaging_id.strip()
        granular = debug_data.get("granular_scopes")
        if isinstance(granular, list):
            for item in granular:
                if not isinstance(item, dict):
                    continue
                if str(item.get("scope") or "") != "whatsapp_business_management":
                    continue
                target_ids = [str(x) for x in (item.get("target_ids") or [])]
                if waba in target_ids:
                    return True
        scopes = debug_data.get("scopes")
        if isinstance(scopes, list) and "whatsapp_business_management" in scopes:
            return True
        return False

    async def _assert_template_token(self, token: str, messaging_id: str) -> None:
        dbg = await self.meta_graph.debug_token(token)
        data = dbg.get("data") if isinstance(dbg.get("data"), dict) else {}
        token_type = str(data.get("type") or "n/d")
        if not data.get("is_valid", True):
            raise ValueError(
                f"Token invalido para WABA {messaging_id} (type={token_type}). "
                "Reconecte via Embedded Signup."
            )
        platform_token = (settings.META_SYSTEM_USER_TOKEN or "").strip()
        if platform_token and token == platform_token:
            raise ValueError(
                f"(#100) Token global da plataforma (META_SYSTEM_USER_TOKEN) gravado na conta {messaging_id}. "
                "Use Embedded Signup para persistir o token BISU/integracao desta WABA (USER, SYSTEM_USER ou "
                "BUSINESS_INTEGRATION_SYSTEM_USER com escopo granular na WABA)."
            )
        if not self._token_manages_waba(data, messaging_id):
            raise ValueError(
                f"Token type={token_type} sem whatsapp_business_management na WABA {messaging_id}. "
                "Reautorize via Embedded Signup ou atribua o ativo ao usuario/token no Business Manager."
            )

    async def list_templates(
        self,
        tenant_id: str,
        account_key: str | None = None,
    ) -> list[WhatsAppTemplate]:
        messaging_id, token = await self._messaging_account_token(tenant_id, account_key)
        rows = await self.meta_graph.list_message_templates(messaging_id, token)
        templates = [WhatsAppTemplate.from_graph(row) for row in rows]
        if self.template_status_service is not None:
            try:
                await self.template_status_service.sync_graph_templates(
                    tenant_id=tenant_id,
                    account_key=messaging_id,
                    templates=templates,
                )
            except Exception:
                pass
        return templates

    async def create_template(
        self,
        tenant_id: str,
        payload: WhatsAppTemplateCreate,
    ) -> WhatsAppTemplate:
        messaging_id, token = await self._messaging_account_token(tenant_id, payload.account_key)
        header = None
        if payload.header:
            header = {
                "format": payload.header.format,
                "text": payload.header.text,
                "media_url": payload.header.media_url,
            }
        buttons = [b.model_dump() for b in (payload.buttons or [])]
        if len(buttons) > 3:
            raise ValueError("Máximo de 3 botões por template")
        components = self.meta_graph.build_template_components(
            body_text=payload.body_text,
            footer_text=payload.footer_text,
            header=header,
            buttons=buttons,
            body_examples=payload.body_examples or None,
        )
        row = await self.meta_graph.create_message_template(
            waba_id=messaging_id,
            access_token=token,
            name=payload.name,
            language=payload.language,
            category=payload.category,
            body_text=payload.body_text,
            components=components,
        )
        return WhatsAppTemplate.from_graph(
            {
                "id": row.get("id"),
                "name": payload.name,
                "language": payload.language,
                "category": payload.category,
                "status": row.get("status") or "PENDING",
                "components": [{"type": "BODY", "text": payload.body_text}],
            }
        )

    @staticmethod
    def _normalize_phone(value: str) -> str:
        return normalize_whatsapp_phone(value)

    async def send_template(
        self,
        tenant_id: str,
        payload: WhatsAppTemplateSend,
    ) -> WhatsAppTemplateSendResult:
        allowed = self._normalize_phone(settings.META_TEST_RECIPIENT)
        target = self._normalize_phone(payload.to or settings.META_TEST_RECIPIENT)
        if not target:
            raise ValueError("Destinatario invalido")
        if target != allowed:
            raise ValueError(
                f"Envio de teste permitido apenas para {settings.META_TEST_RECIPIENT}"
            )

        resolved_key, _, token_refreshed = await self._access_token(tenant_id, payload.account_key)

        accounts = await self.whatsapp_account_service.list_accounts(tenant_id)
        selected = next((item for item in accounts if item.account_key == resolved_key), None)
        if selected is None:
            raise ValueError("Conta WhatsApp nao encontrada")

        templates = await self.list_templates(tenant_id, account_key=resolved_key)
        template = next(
            (
                item
                for item in templates
                if item.name == payload.template_name and item.language == payload.language
            ),
            None,
        )
        if template is None:
            raise ValueError("Modelo WhatsApp nao encontrado para este idioma")
        if template.status.upper() != "APPROVED":
            raise ValueError("Somente modelos com status APPROVED podem ser enviados")

        expected_vars = self._body_variable_count(template.body_text)
        params = [str(item).strip() for item in (payload.body_parameters or [])]
        if expected_vars > 0:
            if len(params) != expected_vars or any(not item for item in params):
                raise ValueError(
                    f"Este modelo exige {expected_vars} variavel(is) de corpo preenchida(s)"
                )
        elif params:
            raise ValueError("Este modelo nao aceita parametros de corpo")

        components = None
        if params:
            components = [
                {
                    "type": "body",
                    "parameters": [{"type": "text", "text": item} for item in params],
                }
            ]

        from app.services.outbound_billing import (
            finalize_outbound,
            gateway_billing_fields,
            reserve_outbound,
        )

        billing = await reserve_outbound(
            tenant_id,
            category=str(template.category or "UTILITY"),
            category_source="template_approved_category",
            source_path="template",
            idempotency_key=f"template:{uuid4()}",
            phone_number_id=selected.phone_number_id,
            template_name=payload.template_name,
        )
        provider_message_id: str | None = None
        try:
            async with httpx.AsyncClient(timeout=settings.GATEWAY_API_TIMEOUT) as client:
                gw_resp = await client.post(
                    f"{settings.GATEWAY_API_URL}/send-template",
                    headers={"x-internal-api-key": settings.INTERNAL_API_KEY},
                    json={
                        "tenant_id": tenant_id,
                        "to": target,
                        "template_name": payload.template_name,
                        "language_code": payload.language,
                        "phone_number_id": selected.phone_number_id,
                        "components": components,
                        **gateway_billing_fields(billing),
                    },
                )
            if gw_resp.status_code != 200:
                detail = gw_resp.text
                try:
                    detail = gw_resp.json().get("detail") or detail
                except Exception:
                    pass
                raise ValueError(str(detail))
            data = gw_resp.json()
            provider_message_id = data.get("message_id")
        except httpx.RequestError as exc:
            raise ValueError(f"Gateway indisponivel: {exc}") from exc
        finally:
            await finalize_outbound(tenant_id, billing, provider_message_id=provider_message_id)

        return WhatsAppTemplateSendResult(
            message_id=data.get("message_id"),
            template_name=payload.template_name,
            to=target,
            token_refreshed=token_refreshed,
        )

    async def send_production_template(
        self,
        *,
        tenant_id: str,
        account_key: str | None,
        template_name: str,
        language: str,
        to: str,
        body_parameters: list[str],
        billing_reservation_id: str | None = None,
        charge_meta: bool = True,
    ) -> WhatsAppTemplateSendResult:
        target = self._normalize_phone(to)
        if not target:
            raise ValueError("Destinatario invalido")

        resolved_key, _, token_refreshed = await self._access_token(tenant_id, account_key)
        accounts = await self.whatsapp_account_service.list_accounts(tenant_id)
        selected = next((item for item in accounts if item.account_key == resolved_key), None)
        if selected is None:
            raise ValueError("Conta WhatsApp nao encontrada")

        templates = await self.list_templates(tenant_id, account_key=resolved_key)
        template = next(
            (item for item in templates if item.name == template_name and item.language == language),
            None,
        )
        if template is None:
            raise ValueError("Modelo nao encontrado")
        if template.status.upper() != "APPROVED":
            raise ValueError("Somente modelos APPROVED podem ser enviados")

        expected_vars = self._body_variable_count(template.body_text)
        params = [str(item).strip() for item in (body_parameters or [])]
        if expected_vars > 0:
            if len(params) != expected_vars or any(not item for item in params):
                raise ValueError(f"Modelo exige {expected_vars} variavel(is)")
        components = None
        if params:
            components = [
                {"type": "body", "parameters": [{"type": "text", "text": item} for item in params]},
            ]

        billing: dict[str, Any] = {"billing_enforced": False}
        if charge_meta:
            from app.services.outbound_billing import finalize_outbound, gateway_billing_fields, reserve_outbound

            if billing_reservation_id:
                billing = {
                    "billing_enforced": True,
                    "billing_reservation_id": billing_reservation_id,
                }
            else:
                billing = await reserve_outbound(
                    tenant_id,
                    category=str(template.category or "UTILITY"),
                    category_source="template_approved_category",
                    source_path="campaign",
                    idempotency_key=f"campaign:{uuid4()}",
                    phone_number_id=selected.phone_number_id,
                    template_name=template_name,
                )
        provider_message_id: str | None = None
        try:
            async with httpx.AsyncClient(timeout=settings.GATEWAY_API_TIMEOUT) as client:
                payload: dict[str, Any] = {
                    "tenant_id": tenant_id,
                    "to": target,
                    "template_name": template_name,
                    "language_code": language,
                    "phone_number_id": selected.phone_number_id,
                    "components": components,
                }
                if charge_meta:
                    payload.update(gateway_billing_fields(billing))
                else:
                    payload["billing_enforced"] = False
                gw_resp = await client.post(
                    f"{settings.GATEWAY_API_URL}/send-template",
                    headers={"x-internal-api-key": settings.INTERNAL_API_KEY},
                    json=payload,
                )
            if gw_resp.status_code != 200:
                detail = gw_resp.text
                try:
                    detail = gw_resp.json().get("detail") or detail
                except Exception:
                    pass
                raise ValueError(str(detail))
            data = gw_resp.json()
            provider_message_id = data.get("message_id")
        except httpx.RequestError as exc:
            raise ValueError(f"Gateway indisponivel: {exc}") from exc
        finally:
            if charge_meta:
                from app.services.outbound_billing import finalize_outbound

                await finalize_outbound(tenant_id, billing, provider_message_id=provider_message_id)

        return WhatsAppTemplateSendResult(
            message_id=provider_message_id,
            template_name=template_name,
            to=target,
            token_refreshed=token_refreshed,
        )
