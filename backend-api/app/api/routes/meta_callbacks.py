"""Public Meta platform callbacks (data deletion, status pages)."""
from __future__ import annotations

import logging

from fastapi import APIRouter, Form, HTTPException, Query
from fastapi.responses import HTMLResponse, JSONResponse

from app.config.settings import settings
from app.security.meta_callbacks import new_confirmation_code, parse_signed_request

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/meta", tags=["Meta Callbacks"])


@router.get("/data-deletion")
async def meta_data_deletion_callback_probe() -> JSONResponse:
    """Lets Meta (and dashboards) verify the callback URL is reachable."""
    return JSONResponse(
        {
            "status": "ok",
            "callback": "POST /api/v1/meta/data-deletion",
            "content_type": "application/x-www-form-urlencoded",
            "field": "signed_request",
        }
    )


@router.post("/data-deletion")
async def meta_data_deletion_callback(
    signed_request: str = Form(...),
) -> JSONResponse:
    """Meta Data Deletion Callback — required for App Review."""
    if not settings.META_APP_SECRET:
        raise HTTPException(status_code=503, detail="META_APP_SECRET not configured")

    payload = parse_signed_request(signed_request, settings.META_APP_SECRET)
    if payload is None:
        raise HTTPException(status_code=400, detail="Invalid signed_request")

    user_id = str(payload.get("user_id") or "unknown")
    confirmation_code = new_confirmation_code()
    status_url = (
        f"{settings.META_DATA_DELETION_BASE_URL.rstrip('/')}"
        f"?id={confirmation_code}&user_id={user_id}"
    )
    logger.info("Meta data deletion request received for user_id=%s code=%s", user_id, confirmation_code)
    return JSONResponse(
        {
            "url": status_url,
            "confirmation_code": confirmation_code,
        }
    )


@router.get("/data-deletion/status", response_class=HTMLResponse)
async def meta_data_deletion_status(
    id: str = Query(..., alias="id"),
    user_id: str = Query(default=""),
) -> HTMLResponse:
    """Simple status page linked from Meta data deletion callback response."""
    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <title>Solicitação de exclusão de dados | Atenda Ai</title>
</head>
<body style="font-family: sans-serif; max-width: 640px; margin: 40px auto; line-height: 1.6;">
  <h1>Solicitação registrada</h1>
  <p>Sua solicitação de exclusão de dados foi recebida pela Atenda Ai.</p>
  <p><strong>Código de confirmação:</strong> {id}</p>
  <p>Se precisar de suporte, envie este código para
    <a href="mailto:atendaai@gmail.com">atendaai@gmail.com</a>.</p>
  <p><a href="https://eletronica2.github.io/chatbot/privacy.html">Política de Privacidade</a></p>
</body>
</html>"""
    return HTMLResponse(html)
