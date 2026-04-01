"""
API endpoints for sending messages via WhatsApp
This module can be imported by the backend or exposed as separate endpoints
"""
import logging
from fastapi import APIRouter, HTTPException, Depends

from schemas import (
    OutgoingTextMessage,
    OutgoingImageMessage,
    OutgoingDocumentMessage,
    OutgoingInteractiveButtonsMessage,
    OutgoingInteractiveListMessage,
    OutgoingTemplateMessage,
    SendMessageResponse
)
from meta_client import MetaAPIClient, get_meta_client

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/send", tags=["Send Messages"])


@router.post("/text", response_model=SendMessageResponse)
async def send_text(
    message: OutgoingTextMessage,
    client: MetaAPIClient = Depends(get_meta_client)
):
    """Send a text message"""
    result = await client.send_text_message(message)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.error)
    return result


@router.post("/image", response_model=SendMessageResponse)
async def send_image(
    message: OutgoingImageMessage,
    client: MetaAPIClient = Depends(get_meta_client)
):
    """Send an image message"""
    result = await client.send_image_message(message)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.error)
    return result


@router.post("/document", response_model=SendMessageResponse)
async def send_document(
    message: OutgoingDocumentMessage,
    client: MetaAPIClient = Depends(get_meta_client)
):
    """Send a document message"""
    result = await client.send_document_message(message)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.error)
    return result


@router.post("/interactive/buttons", response_model=SendMessageResponse)
async def send_interactive_buttons(
    message: OutgoingInteractiveButtonsMessage,
    client: MetaAPIClient = Depends(get_meta_client)
):
    """Send an interactive message with buttons"""
    result = await client.send_interactive_buttons(message)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.error)
    return result


@router.post("/interactive/list", response_model=SendMessageResponse)
async def send_interactive_list(
    message: OutgoingInteractiveListMessage,
    client: MetaAPIClient = Depends(get_meta_client)
):
    """Send an interactive message with list"""
    result = await client.send_interactive_list(message)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.error)
    return result


@router.post("/template", response_model=SendMessageResponse)
async def send_template(
    message: OutgoingTemplateMessage,
    client: MetaAPIClient = Depends(get_meta_client)
):
    """Send a template message"""
    result = await client.send_template_message(message)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.error)
    return result

