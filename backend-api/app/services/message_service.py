"""Service wrapper around durable message storage."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from app.repositories.message_repository import MessageRepository


class MessageService:
    def __init__(self, repository: MessageRepository):
        self.repository = repository

    async def was_processed(self, *, tenant_id: str, external_message_id: str | None, direction: str) -> bool:
        return await self.repository.was_processed(
            tenant_id=tenant_id,
            external_message_id=external_message_id,
            direction=direction,
        )

    async def append(
        self,
        *,
        tenant_id: str,
        session_id: str,
        direction: str,
        role: str,
        content: str,
        source: str,
        metadata: dict[str, Any] | None,
        external_message_id: str | None = None,
        phone_number_id: str | None = None,
    ) -> None:
        await self.repository.append_message(
            tenant_id=tenant_id,
            session_id=session_id,
            direction=direction,
            role=role,
            content=content,
            source=source,
            metadata=metadata,
            external_message_id=external_message_id,
            phone_number_id=phone_number_id,
        )

    async def list_messages(self, *, tenant_id: str, session_id: str, limit: int = 200) -> list[dict[str, Any]]:
        return await self.repository.list_messages(tenant_id=tenant_id, session_id=session_id, limit=limit)

    async def count_incoming_since(self, *, tenant_id: str, since: datetime) -> int:
        return await self.repository.count_incoming_since(tenant_id=tenant_id, since=since)

