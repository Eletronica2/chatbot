"""Durable service for tenant-level chatbot settings."""
from __future__ import annotations

import asyncio
import json
from typing import Dict, List, Optional

from app.db.mysql import MySQLDatabase
from app.domain.tenant import (
    DEFAULT_GEMINI_FALLBACK_MODELS,
    DEFAULT_GEMINI_MODEL,
    TenantSettings,
    normalize_model_list,
)


class TenantSettingsService:
    def __init__(self, database: MySQLDatabase):
        self.database = database

    async def get_or_create(self, tenant_id: str) -> TenantSettings:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _load() -> TenantSettings:
            row = self.database.fetch_one(
                """
                SELECT ts.ai_enabled, ts.flow_editing_enabled, ts.debug_mode,
                       ts.gemini_model, ts.fallback_models, ts.available_models,
                       t.name AS tenant_name
                FROM tenants t
                LEFT JOIN tenant_settings ts ON ts.tenant_id = t.id
                WHERE t.id = %s
                LIMIT 1
                """,
                (tenant_pk,),
            ) or {}
            if row.get("gemini_model") is None:
                self.database.execute(
                    """
                    INSERT INTO tenant_settings (
                        tenant_id, ai_enabled, flow_editing_enabled, debug_mode,
                        gemini_model, fallback_models, available_models
                    ) VALUES (%s, 1, 1, 0, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE updated_at = CURRENT_TIMESTAMP
                    """,
                    (
                        tenant_pk,
                        DEFAULT_GEMINI_MODEL,
                        json.dumps(DEFAULT_GEMINI_FALLBACK_MODELS, ensure_ascii=False),
                        json.dumps(DEFAULT_GEMINI_FALLBACK_MODELS, ensure_ascii=False),
                    ),
                )
                row = self.database.fetch_one(
                    """
                    SELECT ts.ai_enabled, ts.flow_editing_enabled, ts.debug_mode,
                           ts.gemini_model, ts.fallback_models, ts.available_models,
                           t.name AS tenant_name
                    FROM tenants t
                    LEFT JOIN tenant_settings ts ON ts.tenant_id = t.id
                    WHERE t.id = %s
                    LIMIT 1
                    """,
                    (tenant_pk,),
                ) or {}

            fallback_models = self._json_list(row.get("fallback_models"))
            available_models = self._json_list(row.get("available_models"))
            merged_available = normalize_model_list(
                [row.get("gemini_model") or DEFAULT_GEMINI_MODEL, *fallback_models, *available_models, *DEFAULT_GEMINI_FALLBACK_MODELS]
            )
            return TenantSettings(
                tenant_id=tenant_id,
                tenant_name=str(row.get("tenant_name") or f"Tenant {tenant_id}"),
                ai_enabled=bool(row.get("ai_enabled", True)),
                flow_editing_enabled=bool(row.get("flow_editing_enabled", True)),
                debug_mode=bool(row.get("debug_mode", False)),
                gemini_model=str(row.get("gemini_model") or DEFAULT_GEMINI_MODEL),
                fallback_models=fallback_models or list(DEFAULT_GEMINI_FALLBACK_MODELS),
                available_models=merged_available,
            )

        return await asyncio.to_thread(_load)

    async def update(
        self,
        tenant_id: str,
        *,
        tenant_name: Optional[str] = None,
        ai_enabled: Optional[bool] = None,
        flow_editing_enabled: Optional[bool] = None,
        debug_mode: Optional[bool] = None,
        gemini_model: Optional[str] = None,
        fallback_models: Optional[List[str]] = None,
    ) -> TenantSettings:
        current = await self.get_or_create(tenant_id)
        next_tenant_name = tenant_name.strip() if isinstance(tenant_name, str) and tenant_name.strip() else current.tenant_name
        next_ai_enabled = current.ai_enabled if ai_enabled is None else bool(ai_enabled)
        next_flow_editing_enabled = current.flow_editing_enabled if flow_editing_enabled is None else bool(flow_editing_enabled)
        next_debug_mode = current.debug_mode if debug_mode is None else bool(debug_mode)
        next_gemini_model = current.gemini_model
        if gemini_model is not None:
            normalized_primary = normalize_model_list([gemini_model])
            if normalized_primary:
                next_gemini_model = normalized_primary[0]
        next_fallback_models = current.fallback_models
        if fallback_models is not None:
            normalized_fallbacks = normalize_model_list(fallback_models)
            next_fallback_models = normalized_fallbacks or list(DEFAULT_GEMINI_FALLBACK_MODELS)
        next_available_models = normalize_model_list(
            [next_gemini_model, *next_fallback_models, *DEFAULT_GEMINI_FALLBACK_MODELS]
        )
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _write() -> None:
            self.database.execute(
                "UPDATE tenants SET name = %s WHERE id = %s",
                (next_tenant_name, tenant_pk),
            )
            self.database.execute(
                """
                INSERT INTO tenant_settings (
                    tenant_id, ai_enabled, flow_editing_enabled, debug_mode,
                    gemini_model, fallback_models, available_models
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    ai_enabled = VALUES(ai_enabled),
                    flow_editing_enabled = VALUES(flow_editing_enabled),
                    debug_mode = VALUES(debug_mode),
                    gemini_model = VALUES(gemini_model),
                    fallback_models = VALUES(fallback_models),
                    available_models = VALUES(available_models),
                    updated_at = CURRENT_TIMESTAMP
                """,
                (
                    tenant_pk,
                    1 if next_ai_enabled else 0,
                    1 if next_flow_editing_enabled else 0,
                    1 if next_debug_mode else 0,
                    next_gemini_model,
                    json.dumps(next_fallback_models, ensure_ascii=False),
                    json.dumps(next_available_models, ensure_ascii=False),
                ),
            )

        await asyncio.to_thread(_write)
        return await self.get_or_create(tenant_id)

    async def get_ai_metadata(self, tenant_id: str) -> Dict[str, object]:
        settings = await self.get_or_create(tenant_id)
        return settings.as_ai_metadata()

    def _json_list(self, raw_value: object) -> List[str]:
        if isinstance(raw_value, list):
            return normalize_model_list([str(item) for item in raw_value])
        if isinstance(raw_value, str) and raw_value.strip():
            try:
                parsed = json.loads(raw_value)
                if isinstance(parsed, list):
                    return normalize_model_list([str(item) for item in parsed])
            except json.JSONDecodeError:
                pass
        return []

