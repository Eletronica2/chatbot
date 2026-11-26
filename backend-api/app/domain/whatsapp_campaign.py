from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


class CampaignCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    account_key: str | None = None
    template_name: str
    template_language: str = "pt_BR"
    template_category: str = "UTILITY"


class CampaignValidateRequest(BaseModel):
    """Rows parsed client-side or from upload metadata."""
    pass


class CampaignConfirmRequest(BaseModel):
    confirm: bool = True


class CampaignRecipientPreview(BaseModel):
    row_number: int
    phone: str
    body_params: dict[str, str] = Field(default_factory=dict)
    consent_ok: bool = False
    errors: list[str] = Field(default_factory=list)


class CampaignPlanSnapshot(BaseModel):
    plan: str = ""
    status: str = ""
    used_messages: int = 0
    monthly_message_limit: int = 0
    renewal_date: Optional[datetime] = None


class CampaignSendReadiness(BaseModel):
    sends_enabled: bool = False
    sends_blocked_code: str | None = None
    sends_blocked_reason: str | None = None
    plan_snapshot: CampaignPlanSnapshot | None = None
    spreadsheet_valid: bool | None = None


class CampaignValidationResult(BaseModel):
    campaign_id: str | None = None
    total_rows: int = 0
    valid_rows: int = 0
    duplicate_phones: int = 0
    invalid_rows: int = 0
    consent_missing_rows: int = 0
    recipients: list[CampaignRecipientPreview] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)
    estimate: dict[str, Any] = Field(default_factory=dict)
    meta_disclaimer: str | None = None
    sends_enabled: bool = False
    sends_blocked_reason: str | None = None
    sends_blocked_code: str | None = None
    plan_snapshot: CampaignPlanSnapshot | None = None


class CampaignSummary(BaseModel):
    id: str
    name: str
    status: str
    account_key: str | None = None
    template_name: str
    template_language: str
    template_category: str
    total_recipients: int
    pending_count: int = 0
    sent_count: int
    delivered_count: int = 0
    read_count: int = 0
    failed_count: int
    uncertain_count: int = 0
    meta_estimate: dict[str, Any] = Field(default_factory=dict)
    meta_disclaimer: str | None = None
    created_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None


class CampaignRecipientRow(BaseModel):
    row_number: int
    phone: str
    status: str
    body_params: dict[str, str] = Field(default_factory=dict)
    consent_ok: bool = False
    error_message: str | None = None
    sent_at: Optional[datetime] = None
    delivered_at: Optional[datetime] = None
    read_at: Optional[datetime] = None


class CampaignDetail(BaseModel):
    campaign: CampaignSummary
    recipients: list[CampaignRecipientRow] = Field(default_factory=list)