"""Domain models for WhatsApp message templates."""
from __future__ import annotations

from pydantic import BaseModel, Field


class WhatsAppTemplate(BaseModel):
    template_id: str | None = None
    name: str
    language: str
    category: str
    status: str = "PENDING"
    body_text: str | None = None

    @classmethod
    def from_graph(cls, row: dict) -> WhatsAppTemplate:
        body_text = None
        components = row.get("components")
        if isinstance(components, list):
            for component in components:
                if isinstance(component, dict) and component.get("type") == "BODY":
                    body_text = component.get("text")
                    break
        return cls(
            template_id=str(row.get("id") or "") or None,
            name=str(row.get("name") or ""),
            language=str(row.get("language") or ""),
            category=str(row.get("category") or ""),
            status=str(row.get("status") or "PENDING"),
            body_text=body_text,
        )


class WhatsAppTemplateCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=512)
    language: str = "pt_BR"
    category: str = "UTILITY"
    body_text: str = Field(..., min_length=1, max_length=1024)
    account_key: str | None = None


class WhatsAppTemplateSend(BaseModel):
    template_name: str = Field(..., min_length=1, max_length=512)
    language: str = "pt_BR"
    to: str | None = None
    account_key: str | None = None


class WhatsAppTemplateSendResult(BaseModel):
    message_id: str | None = None
    template_name: str
    to: str
    status: str = "sent"
    token_refreshed: bool = False
