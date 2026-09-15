"""Fiscal document provider abstraction — never invent NF-e data."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class FiscalProvider(ABC):
    """Pluggable fiscal/NFS-e provider."""

    @property
    @abstractmethod
    def configured(self) -> bool:
        ...

    @property
    @abstractmethod
    def provider_name(self) -> str:
        ...

    @abstractmethod
    async def list_documents(self, tenant_id: str) -> list[dict[str, Any]]:
        ...


class NotConfiguredFiscalProvider(FiscalProvider):
    """Default stub when FISCAL_PROVIDER is unset or not ready."""

    @property
    def configured(self) -> bool:
        return False

    @property
    def provider_name(self) -> str:
        return "none"

    async def list_documents(self, tenant_id: str) -> list[dict[str, Any]]:
        # Intentionally empty — never fabricate fiscal documents / NF.
        return []


def build_fiscal_provider(*, provider: str, ready: bool) -> FiscalProvider:
    name = (provider or "none").strip().lower()
    if name in {"", "none", "null"} or not ready:
        return NotConfiguredFiscalProvider()
    # Future providers (Focus NFe, etc.) register here when ready=true.
    return NotConfiguredFiscalProvider()
