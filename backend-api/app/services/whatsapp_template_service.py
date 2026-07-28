"""Manage WhatsApp message templates via Meta Graph API."""
from __future__ import annotations

import re

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


class WhatsAppTemplateService:
    def __init__(
        self,
        meta_graph: MetaGraphService,
        whatsapp_account_service: WhatsAppAccountService,
    ):
        self.meta_graph = meta_graph
        self.whatsapp_account_service = whatsapp_account_service

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

    async def list_templates(
        self,
        tenant_id: str,
        account_key: str | None = None,
    ) -> list[WhatsAppTemplate]:
        waba_id, token, _ = await self._access_token(tenant_id, account_key)
        rows = await self.meta_graph.list_message_templates(waba_id, token)
        return [WhatsAppTemplate.from_graph(row) for row in rows]

    async def create_template(
        self,
        tenant_id: str,
        payload: WhatsAppTemplateCreate,
    ) -> WhatsAppTemplate:
        waba_id, token, _ = await self._access_token(tenant_id, payload.account_key)
        row = await self.meta_graph.create_message_template(
            waba_id=waba_id,
            access_token=token,
            name=payload.name,
            language=payload.language,
            category=payload.category,
            body_text=payload.body_text,
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
        except httpx.RequestError as exc:
            raise ValueError(f"Gateway indisponivel: {exc}") from exc

        return WhatsAppTemplateSendResult(
            message_id=data.get("message_id"),
            template_name=payload.template_name,
            to=target,
            token_refreshed=token_refreshed,
        )
