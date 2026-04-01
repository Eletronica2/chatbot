"""Domain models for tenant WhatsApp accounts."""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class WhatsAppAccount(BaseModel):
    account_id: str
    tenant_id: str
    account_key: str
    display_name: str
    phone_number_id: str
    display_phone_number: str
    verify_token: str | None = None
    status: str = "active"
    is_default: bool = False
    has_access_token: bool = False
    masked_access_token: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class WhatsAppAccountSecret(BaseModel):
    account: WhatsAppAccount
    access_token: str | None = None


class WhatsAppAccountCreate(BaseModel):
    account_key: str
    display_name: str
    phone_number_id: str
    display_phone_number: str
    access_token: str | None = None
    verify_token: str | None = None
    status: str = "active"
    is_default: bool = False


class WhatsAppAccountUpdate(BaseModel):
    display_name: str | None = None
    phone_number_id: str | None = None
    display_phone_number: str | None = None
    access_token: str | None = None
    verify_token: str | None = None
    status: str | None = None
    is_default: bool | None = None

