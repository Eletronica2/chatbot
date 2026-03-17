"""
Pydantic schemas for WhatsApp Gateway
"""
from pydantic import BaseModel, Field
from typing import Optional, List, Any
from datetime import datetime
from enum import Enum


# ============== Enums ==============

class MessageType(str, Enum):
    TEXT = "text"
    IMAGE = "image"
    AUDIO = "audio"
    VIDEO = "video"
    DOCUMENT = "document"
    STICKER = "sticker"
    LOCATION = "location"
    CONTACTS = "contacts"
    INTERACTIVE = "interactive"
    BUTTON = "button"
    UNKNOWN = "unknown"


class MessageDirection(str, Enum):
    INCOMING = "incoming"
    OUTGOING = "outgoing"


# ============== Incoming Message Schemas (from Meta) ==============

class TextContent(BaseModel):
    body: str


class ImageContent(BaseModel):
    id: str
    mime_type: Optional[str] = None
    sha256: Optional[str] = None
    caption: Optional[str] = None


class AudioContent(BaseModel):
    id: str
    mime_type: Optional[str] = None


class VideoContent(BaseModel):
    id: str
    mime_type: Optional[str] = None
    caption: Optional[str] = None


class DocumentContent(BaseModel):
    id: str
    mime_type: Optional[str] = None
    filename: Optional[str] = None
    caption: Optional[str] = None


class LocationContent(BaseModel):
    latitude: float
    longitude: float
    name: Optional[str] = None
    address: Optional[str] = None


class ContactName(BaseModel):
    formatted_name: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None


class ContactInfo(BaseModel):
    name: ContactName
    phones: Optional[List[dict]] = None


class InteractiveReply(BaseModel):
    id: str
    title: Optional[str] = None


class InteractiveContent(BaseModel):
    type: str
    button_reply: Optional[InteractiveReply] = None
    list_reply: Optional[InteractiveReply] = None


class ButtonContent(BaseModel):
    text: str
    payload: str


class WebhookMessage(BaseModel):
    """Raw message from WhatsApp webhook"""
    from_: str = Field(..., alias="from")
    id: str
    timestamp: str
    type: str
    text: Optional[TextContent] = None
    image: Optional[ImageContent] = None
    audio: Optional[AudioContent] = None
    video: Optional[VideoContent] = None
    document: Optional[DocumentContent] = None
    location: Optional[LocationContent] = None
    contacts: Optional[List[ContactInfo]] = None
    interactive: Optional[InteractiveContent] = None
    button: Optional[ButtonContent] = None
    
    class Config:
        populate_by_name = True


class WebhookContact(BaseModel):
    """Contact info from webhook"""
    wa_id: str
    profile: Optional[dict] = None


class WebhookMetadata(BaseModel):
    """Metadata from webhook"""
    display_phone_number: str
    phone_number_id: str


class WebhookValue(BaseModel):
    """Value object in webhook payload"""
    messaging_product: str
    metadata: WebhookMetadata
    contacts: Optional[List[WebhookContact]] = None
    messages: Optional[List[WebhookMessage]] = None
    statuses: Optional[List[dict]] = None


class WebhookChange(BaseModel):
    """Change object in webhook payload"""
    field: str
    value: WebhookValue


class WebhookEntry(BaseModel):
    """Entry in webhook payload"""
    id: str
    changes: List[WebhookChange]


class WebhookPayload(BaseModel):
    """Full webhook payload from Meta"""
    object: str
    entry: List[WebhookEntry]


# ============== Normalized Message Schema ==============

class NormalizedMessage(BaseModel):
    """Normalized message to send to backend"""
    message_id: str
    tenant_id: str
    phone_number: str
    phone_number_id: str
    display_phone_number: str
    contact_name: Optional[str] = None
    message_type: MessageType
    direction: MessageDirection = MessageDirection.INCOMING
    content: str
    raw_content: Optional[dict] = None
    media_id: Optional[str] = None
    media_mime_type: Optional[str] = None
    timestamp: datetime
    metadata: Optional[dict] = None
    
    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }


# ============== Outgoing Message Schemas ==============

class OutgoingTextMessage(BaseModel):
    """Text message to send via WhatsApp"""
    to: str
    text: str
    preview_url: bool = False


class OutgoingImageMessage(BaseModel):
    """Image message to send via WhatsApp"""
    to: str
    image_url: Optional[str] = None
    image_id: Optional[str] = None
    caption: Optional[str] = None


class OutgoingDocumentMessage(BaseModel):
    """Document message to send via WhatsApp"""
    to: str
    document_url: Optional[str] = None
    document_id: Optional[str] = None
    filename: Optional[str] = None
    caption: Optional[str] = None


class InteractiveButton(BaseModel):
    """Button for interactive message"""
    id: str
    title: str


class InteractiveListRow(BaseModel):
    """Row in interactive list"""
    id: str
    title: str
    description: Optional[str] = None


class InteractiveListSection(BaseModel):
    """Section in interactive list"""
    title: str
    rows: List[InteractiveListRow]


class OutgoingInteractiveButtonsMessage(BaseModel):
    """Interactive buttons message"""
    to: str
    body_text: str
    buttons: List[InteractiveButton]
    header_text: Optional[str] = None
    footer_text: Optional[str] = None


class OutgoingInteractiveListMessage(BaseModel):
    """Interactive list message"""
    to: str
    body_text: str
    button_text: str
    sections: List[InteractiveListSection]
    header_text: Optional[str] = None
    footer_text: Optional[str] = None


class OutgoingTemplateMessage(BaseModel):
    """Template message to send via WhatsApp"""
    to: str
    template_name: str
    language_code: str = "pt_BR"
    components: Optional[List[dict]] = None


# ============== Response Schemas ==============

class SendMessageResponse(BaseModel):
    """Response after sending a message"""
    success: bool
    message_id: Optional[str] = None
    error: Optional[str] = None


class WebhookVerificationResponse(BaseModel):
    """Response for webhook verification"""
    challenge: str


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    service: str
    version: str
    timestamp: datetime
