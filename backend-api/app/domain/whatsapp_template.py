"""Domain models for WhatsApp message templates."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.domain.template_content_rules import (
    validate_body_text,
    validate_button_label,
    validate_footer_text,
    validate_header_text,
)


class TemplateListButton(BaseModel):
    type: str
    text: str


class WhatsAppTemplate(BaseModel):
    template_id: str | None = None
    name: str
    language: str
    category: str
    status: str = "PENDING"
    rejected_reason: str | None = None
    body_text: str | None = None
    header_format: str | None = None
    header_text: str | None = None
    footer_text: str | None = None
    body_examples: list[str] = Field(default_factory=list)
    buttons: list[TemplateListButton] = Field(default_factory=list)

    @classmethod
    def from_graph(cls, row: dict) -> WhatsAppTemplate:
        body_text: str | None = None
        header_format: str | None = None
        header_text: str | None = None
        footer_text: str | None = None
        body_examples: list[str] = []
        buttons: list[TemplateListButton] = []
        components = row.get("components")
        if isinstance(components, list):
            for component in components:
                if not isinstance(component, dict):
                    continue
                ctype = str(component.get("type") or "").upper()
                if ctype == "BODY":
                    body_text = component.get("text")
                    example = component.get("example")
                    if isinstance(example, dict):
                        body_text_rows = example.get("body_text")
                        if isinstance(body_text_rows, list) and body_text_rows:
                            first = body_text_rows[0]
                            if isinstance(first, list):
                                body_examples = [str(item) for item in first if str(item).strip()]
                elif ctype == "HEADER":
                    header_format = str(component.get("format") or "TEXT").upper()
                    header_text = component.get("text")
                elif ctype == "FOOTER":
                    footer_text = component.get("text")
                elif ctype == "BUTTONS":
                    for btn in component.get("buttons") or []:
                        if not isinstance(btn, dict):
                            continue
                        label = str(btn.get("text") or "").strip()
                        if not label:
                            continue
                        buttons.append(
                            TemplateListButton(
                                type=str(btn.get("type") or "QUICK_REPLY").upper(),
                                text=label,
                            )
                        )
        rejected = row.get("rejected_reason")
        if rejected is not None:
            rejected = str(rejected).strip()
            if rejected.upper() == "NONE":
                rejected = None
        return cls(
            template_id=str(row.get("id") or "") or None,
            name=str(row.get("name") or ""),
            language=str(row.get("language") or ""),
            category=str(row.get("category") or ""),
            status=str(row.get("status") or "PENDING"),
            rejected_reason=rejected,
            body_text=body_text,
            header_format=header_format,
            header_text=header_text,
            footer_text=footer_text,
            body_examples=body_examples,
            buttons=buttons,
        )


class TemplateHeaderInput(BaseModel):
    format: Literal["TEXT", "IMAGE", "VIDEO", "DOCUMENT"]
    text: str | None = None
    media_url: str | None = None


class TemplateButtonInput(BaseModel):
    type: Literal["QUICK_REPLY", "PHONE_NUMBER", "URL", "COPY_CODE"]
    text: str = Field(..., min_length=1, max_length=25)
    phone_number: str | None = None
    url: str | None = None
    example: list[str] | None = None


class WhatsAppTemplateCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=512)
    language: str = "pt_BR"
    category: str = "UTILITY"
    body_text: str = Field(..., min_length=1, max_length=1024)
    account_key: str | None = None
    footer_text: str | None = Field(None, max_length=60)
    header: TemplateHeaderInput | None = None
    buttons: list[TemplateButtonInput] = Field(default_factory=list)
    body_examples: list[str] = Field(default_factory=list)

    @field_validator("category")
    @classmethod
    def _category(cls, value: str) -> str:
        allowed = {"MARKETING", "UTILITY", "AUTHENTICATION"}
        upper = value.upper()
        if upper not in allowed:
            raise ValueError("Categoria deve ser MARKETING, UTILITY ou AUTHENTICATION")
        return upper

    @model_validator(mode="after")
    def _content_rules(self) -> "WhatsAppTemplateCreate":
        if self.header and self.header.format == "TEXT" and self.header.text:
            err = validate_header_text(self.header.text)
            if err:
                raise ValueError(err)
        err = validate_body_text(self.body_text, examples=self.body_examples or None)
        if err:
            raise ValueError(err)
        err = validate_footer_text(self.footer_text)
        if err:
            raise ValueError(err)
        if self.category == "AUTHENTICATION" and self.buttons:
            raise ValueError("Templates AUTHENTICATION não suportam botões neste fluxo.")
        for i, btn in enumerate(self.buttons or []):
            err = validate_button_label(btn.text, field=f"Botão {i + 1}")
            if err:
                raise ValueError(err)
            if btn.type == "PHONE_NUMBER" and not (btn.phone_number or "").strip():
                raise ValueError(f"Botão {i + 1}: informe telefone E.164.")
            if btn.type == "URL" and not (btn.url or "").strip():
                raise ValueError(f"Botão {i + 1}: informe URL.")
            if btn.type == "COPY_CODE" and self.category != "MARKETING":
                raise ValueError("COPY_CODE só é permitido em MARKETING.")
        if len(self.buttons or []) > 3:
            raise ValueError("Máximo de 3 botões por template.")
        return self


class WhatsAppTemplateSend(BaseModel):
    template_name: str = Field(..., min_length=1, max_length=512)
    language: str = "pt_BR"
    to: str | None = None
    account_key: str | None = None
    body_parameters: list[str] = Field(default_factory=list)


class WhatsAppTemplateSendResult(BaseModel):
    message_id: str | None = None
    template_name: str
    to: str
    status: str = "sent"
    token_refreshed: bool = False
