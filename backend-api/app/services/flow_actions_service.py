"""Flow Actions Service – CRUD for per-tenant reusable action catalog."""
from __future__ import annotations

import base64
import io
import json
from datetime import datetime
from typing import Any, Dict, List, Optional

from app.db.mysql import MySQLDatabase

try:
    from PIL import Image as PILImage

    _HAS_PILLOW = True
except ImportError:  # pragma: no cover
    _HAS_PILLOW = False

_MAX_IMAGE_DIM = 1280
_VALID_ACTION_TYPES = {
    "send_image",
    "send_link",
    "http_request",
    "delay",
    "send_document",
}


def _resize_image(image_b64: str) -> tuple[str, int, int]:
    """Resize a base64 image to at most _MAX_IMAGE_DIM px on the longest side.

    Returns (new_b64_jpeg, width, height).
    """
    if not _HAS_PILLOW:
        return image_b64, 0, 0
    raw = base64.b64decode(image_b64)
    img = PILImage.open(io.BytesIO(raw)).convert("RGB")
    w, h = img.size
    if max(w, h) > _MAX_IMAGE_DIM:
        if w >= h:
            new_w, new_h = _MAX_IMAGE_DIM, max(1, int(h * _MAX_IMAGE_DIM / w))
        else:
            new_w, new_h = max(1, int(w * _MAX_IMAGE_DIM / h)), _MAX_IMAGE_DIM
        img = img.resize((new_w, new_h), PILImage.LANCZOS)
    else:
        new_w, new_h = w, h
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85)
    return base64.b64encode(buf.getvalue()).decode(), new_w, new_h


def _row_to_dict(row: dict) -> Dict[str, Any]:
    config_raw = row.get("config") or "{}"
    config = json.loads(config_raw) if isinstance(config_raw, str) else (config_raw or {})
    created = row.get("created_at")
    updated = row.get("updated_at")
    return {
        "id": row["id"],
        "tenant_id": row["tenant_id"],
        "name": row["name"],
        "action_type": row["action_type"],
        "config": config,
        "created_at": created.isoformat() if isinstance(created, datetime) else str(created or ""),
        "updated_at": updated.isoformat() if isinstance(updated, datetime) else str(updated or ""),
    }


class FlowActionsService:
    def __init__(self, database: MySQLDatabase) -> None:
        self.db = database

    # ── public API ────────────────────────────────────────────────────────────

    def list_actions(self, tenant_key: str) -> List[Dict[str, Any]]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        rows = self.db.fetch_all(
            "SELECT id, tenant_id, name, action_type, config, created_at, updated_at "
            "FROM flow_actions WHERE tenant_id = %s ORDER BY created_at DESC",
            (tenant_pk,),
        )
        return [_row_to_dict(r) for r in rows]

    def get_action(self, action_id: int, tenant_key: str) -> Optional[Dict[str, Any]]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        row = self.db.fetch_one(
            "SELECT id, tenant_id, name, action_type, config, created_at, updated_at "
            "FROM flow_actions WHERE id = %s AND tenant_id = %s",
            (action_id, tenant_pk),
        )
        return _row_to_dict(row) if row else None

    def create_action(
        self,
        tenant_key: str,
        name: str,
        action_type: str,
        config: Dict[str, Any],
    ) -> Dict[str, Any]:
        if action_type not in _VALID_ACTION_TYPES:
            raise ValueError(f"Invalid action_type: {action_type}")
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        config = self._process_config(action_type, config)
        config_json = json.dumps(config, ensure_ascii=False)
        self.db.execute(
            "INSERT INTO flow_actions (tenant_id, name, action_type, config) VALUES (%s, %s, %s, %s)",
            (tenant_pk, name, action_type, config_json),
        )
        row = self.db.fetch_one(
            "SELECT id, tenant_id, name, action_type, config, created_at, updated_at "
            "FROM flow_actions WHERE tenant_id = %s AND name = %s "
            "ORDER BY created_at DESC LIMIT 1",
            (tenant_pk, name),
        )
        return _row_to_dict(row)  # type: ignore[arg-type]

    def update_action(
        self,
        action_id: int,
        tenant_key: str,
        name: Optional[str],
        config: Optional[Dict[str, Any]],
    ) -> Optional[Dict[str, Any]]:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        existing = self.db.fetch_one(
            "SELECT id, action_type, config FROM flow_actions WHERE id = %s AND tenant_id = %s",
            (action_id, tenant_pk),
        )
        if not existing:
            return None
        updates: list[str] = []
        params: list[Any] = []
        if name is not None:
            updates.append("name = %s")
            params.append(name)
        if config is not None:
            merged = json.loads(existing["config"] or "{}") if isinstance(existing["config"], str) else {}
            merged.update(config)
            merged = self._process_config(str(existing["action_type"]), merged)
            updates.append("config = %s")
            params.append(json.dumps(merged, ensure_ascii=False))
        if not updates:
            return self.get_action(action_id, tenant_key)
        params += [action_id, tenant_pk]
        self.db.execute(
            f"UPDATE flow_actions SET {', '.join(updates)} WHERE id = %s AND tenant_id = %s",
            tuple(params),
        )
        return self.get_action(action_id, tenant_key)

    def delete_action(self, action_id: int, tenant_key: str) -> bool:
        tenant_pk = self.db.resolve_tenant_pk(tenant_key)
        existing = self.db.fetch_one(
            "SELECT id FROM flow_actions WHERE id = %s AND tenant_id = %s",
            (action_id, tenant_pk),
        )
        if not existing:
            return False
        self.db.execute(
            "DELETE FROM flow_actions WHERE id = %s AND tenant_id = %s",
            (action_id, tenant_pk),
        )
        return True

    # ── internal helpers ──────────────────────────────────────────────────────

    def _process_config(self, action_type: str, config: Dict[str, Any]) -> Dict[str, Any]:
        """For send_image, resize the image if Pillow is available."""
        if action_type == "send_image" and "image_data" in config:
            try:
                new_b64, w, h = _resize_image(str(config["image_data"]))
                config = {**config, "image_data": new_b64, "mime_type": "image/jpeg"}
                if w:
                    config["width"] = w
                if h:
                    config["height"] = h
            except Exception:
                pass  # keep original if resize fails
        return config
