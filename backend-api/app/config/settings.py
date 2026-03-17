"""Application settings for Backend API"""
from functools import lru_cache
from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """Centralized configuration loaded from environment variables"""

    # App metadata
    APP_NAME: str = "Backend API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    # Server configuration
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # Flow engine integration
    FLOW_ENGINE_URL: str = "http://flow-engine:8002"
    FLOW_ENGINE_TIMEOUT: int = 15

    # AI engine integration
    AI_ENGINE_URL: str = "http://ai-engine:8003"
    AI_ENGINE_TIMEOUT: int = 20

    # Session management
    SESSION_TTL_SECONDS: int = 3600

    # Multi-tenant defaults
    DEFAULT_TENANT_ID: str = "default"

    # WhatsApp Gateway integration (for admin panel reply)
    GATEWAY_API_URL: str = "http://whatsapp-gateway:40000"
    GATEWAY_API_TIMEOUT: int = 15

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    """Return cached settings instance"""
    return Settings()


settings = get_settings()
