"""Stores flow YAML snapshots and relational metadata in MySQL."""
from __future__ import annotations

from app.repositories.flow_catalog_repository import FlowCatalogRepository


class FlowCatalogService:
    def __init__(self, repository: FlowCatalogRepository):
        self.repository = repository

    async def save_yaml(self, *, tenant_id: str, flow_name: str, yaml_content: str) -> None:
        await self.repository.save_yaml(
            tenant_id=tenant_id,
            flow_name=flow_name,
            yaml_content=yaml_content,
        )

