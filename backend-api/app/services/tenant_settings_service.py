"""In-memory service for tenant-level chatbot settings."""
from __future__ import annotations

from threading import RLock
from typing import Dict, List, Optional

from app.domain.tenant import (
    DEFAULT_GEMINI_FALLBACK_MODELS,
    DEFAULT_GEMINI_MODEL,
    TenantSettings,
    normalize_model_list,
)


class TenantSettingsService:
    """Stores tenant settings with sane defaults for new tenants."""

    def __init__(self):
        self._items: Dict[str, TenantSettings] = {}
        self._lock = RLock()

    def get_or_create(self, tenant_id: str) -> TenantSettings:
        with self._lock:
            current = self._items.get(tenant_id)
            if current:
                return current

            defaults = TenantSettings(
                tenant_id=tenant_id,
                tenant_name=f"Tenant {tenant_id}",
                gemini_model=DEFAULT_GEMINI_MODEL,
                fallback_models=list(DEFAULT_GEMINI_FALLBACK_MODELS),
                available_models=list(DEFAULT_GEMINI_FALLBACK_MODELS),
            )
            self._items[tenant_id] = defaults
            return defaults

    def update(
        self,
        tenant_id: str,
        *,
        tenant_name: Optional[str] = None,
        ai_enabled: Optional[bool] = None,
        flow_editing_enabled: Optional[bool] = None,
        gemini_model: Optional[str] = None,
        fallback_models: Optional[List[str]] = None,
    ) -> TenantSettings:
        with self._lock:
            current = self.get_or_create(tenant_id)
            changes: Dict[str, object] = {}

            if tenant_name is not None and tenant_name.strip():
                changes["tenant_name"] = tenant_name.strip()
            if ai_enabled is not None:
                changes["ai_enabled"] = bool(ai_enabled)
            if flow_editing_enabled is not None:
                changes["flow_editing_enabled"] = bool(flow_editing_enabled)

            if gemini_model is not None:
                normalized_primary = normalize_model_list([gemini_model])
                if normalized_primary:
                    changes["gemini_model"] = normalized_primary[0]

            if fallback_models is not None:
                normalized_fallbacks = normalize_model_list(fallback_models)
                changes["fallback_models"] = (
                    normalized_fallbacks
                    if normalized_fallbacks
                    else list(DEFAULT_GEMINI_FALLBACK_MODELS)
                )

            next_value = current.model_copy(update=changes)
            merged_available = normalize_model_list(
                [next_value.gemini_model, *next_value.fallback_models, *DEFAULT_GEMINI_FALLBACK_MODELS]
            )
            next_value = next_value.model_copy(update={"available_models": merged_available})
            self._items[tenant_id] = next_value
            return next_value

    def get_ai_metadata(self, tenant_id: str) -> Dict[str, object]:
        settings = self.get_or_create(tenant_id)
        return settings.as_ai_metadata()
