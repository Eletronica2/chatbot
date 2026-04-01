"""Email delivery domain objects."""
from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel


EmailDeliveryStatus = Literal["sent", "skipped", "failed"]


class EmailDispatchResult(BaseModel):
    kind: str
    to_email: str
    subject: str
    status: EmailDeliveryStatus
    error: str | None = None
    sent_at: datetime | None = None

