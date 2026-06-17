"""Manage WhatsApp message templates via Meta Graph API."""
from __future__ import annotations

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

    async def _access_token(self, tenant_id: str, account_key: str | None) -> tuple[str, str]:
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
        secret = await self.whatsapp_account_service.resolve_for_account_key(
            tenant_id,
            selected.account_key,
        )
        if secret is None or not secret.access_token:
            raise ValueError("Token de acesso da conta WhatsApp nao configurado")
        return selected.account_key, secret.access_token

    async def list_templates(self, tenant_id: str, account_key: str | None = None) -> list[WhatsAppTemplate]:
        waba_id, token = await self._access_token(tenant_id, account_key)
        rows = await self.meta_graph.list_message_templates(waba_id, token)
        return [WhatsAppTemplate.from_graph(row) for row in rows]

    async def create_template(
        self,
        tenant_id: str,
        payload: WhatsAppTemplateCreate,
    ) -> WhatsAppTemplate:
        waba_id, token = await self._access_token(tenant_id, payload.account_key)
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

        accounts = await self.whatsapp_account_service.list_accounts(tenant_id)
        if not accounts:
            raise ValueError("Nenhuma conta WhatsApp vinculada a esta empresa")
        selected = None
        if payload.account_key:
            selected = next((item for item in accounts if item.account_key == payload.account_key), None)
            if selected is None:
                raise ValueError("Conta WhatsApp nao encontrada")
        else:
            selected = next((item for item in accounts if item.is_default), None) or accounts[0]

        templates = await self.list_templates(tenant_id, account_key=selected.account_key)
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
        if template.body_text and "{{" in template.body_text:
            raise ValueError("Modelos com variaveis nao sao suportados nesta tela de teste")

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
        )
