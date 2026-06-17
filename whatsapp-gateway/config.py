"""Configuration settings for WhatsApp Gateway."""
import os
from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    META_VERIFY_TOKEN: str = "your_verify_token_here"
    META_ACCESS_TOKEN: str = "your_access_token_here"
    META_PHONE_NUMBER_ID: str = "your_phone_number_id"
    META_APP_SECRET: str = ""
    META_API_VERSION: str = "v18.0"
    META_API_BASE_URL: str = "https://graph.facebook.com"

    BACKEND_API_URL: str = "http://backend-api:8000"
    BACKEND_API_TIMEOUT: int = 30
    BACKEND_INTERNAL_API_KEY: str = "internal-chatbot-key"

    APP_NAME: str = "WhatsApp Gateway"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    HOST: str = "0.0.0.0"
    PORT: int = 40000

    DEFAULT_TENANT_ID: str = "default"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

