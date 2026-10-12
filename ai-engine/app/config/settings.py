"""Application settings for AI Engine"""
from functools import lru_cache
from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    APP_NAME: str = "AI Engine"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"
    HOST: str = "0.0.0.0"
    PORT: int = 8003

    AI_PROVIDER: str = "gemini"

    OPENAI_API_KEY: Optional[str] = None
    OPENAI_MODEL: str = "gpt-4o-mini"
    OPENAI_TIMEOUT: int = 30

    GEMINI_API_KEY: Optional[str] = None
    GEMINI_MODEL: str = "gemini-1.5-flash-latest"
    GEMINI_TIMEOUT: int = 30
    AI_FALLBACK_REPLY: str = (
        "Nao tenho como responder no momento. "
        "Tente novamente em instantes."
    )
    AI_DEBUG_PROMPTS: bool = False
    BLOCK_REALTIME_FACTS: bool = True
    REALTIME_GUARD_REPLY: str = (
        "Nao consigo confirmar eventos ou dados em tempo real agora. "
        "Posso ajudar com informacoes gerais ou transferir para um atendente."
    )

    MOCK_AI: bool = False

    SYSTEM_PROMPT: str = (
        "You are a helpful AI assistant for a WhatsApp chatbot. "
        "Keep answers concise, empathetic, and always in Brazilian Portuguese. "
        "You do not have internet access and cannot verify recent real-world events. "
        "If the user asks for recent scores, prices, or news, clearly state this limitation "
        "instead of guessing."
    )
    MAX_HISTORY_MESSAGES: int = 6

    # Local AI server (Ollama + RAG) reached through the private WireGuard tunnel.
    # Master switch only: each tenant still has to be set to provider "local" by a Super Admin.
    LOCAL_AI_ENABLED: bool = False
    LOCAL_AI_BASE_URL: str = "http://10.77.0.2:8100"
    LOCAL_AI_KEY_ID: Optional[str] = None
    LOCAL_AI_SECRET_B64: Optional[str] = None
    LOCAL_AI_MODEL: Optional[str] = None
    LOCAL_AI_CONNECT_TIMEOUT_S: float = 3.0
    LOCAL_AI_TOTAL_BUDGET_S: float = 45.0
    LOCAL_AI_MAX_ATTEMPTS: int = 2
    LOCAL_AI_BACKOFF_BASE_S: float = 0.5
    LOCAL_AI_BACKOFF_MAX_S: float = 4.0
    LOCAL_AI_BREAKER_THRESHOLD: int = 3
    LOCAL_AI_BREAKER_COOLDOWN_S: float = 30.0
    LOCAL_AI_STATUS_TTL_S: float = 15.0
    INTERNAL_API_KEY: Optional[str] = None

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

