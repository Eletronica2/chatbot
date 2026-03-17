"""
Configuration settings for WhatsApp Gateway
"""
import os
from functools import lru_cache
from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """Application settings loaded from environment variables"""
    
    # Meta/WhatsApp API Configuration
    META_VERIFY_TOKEN: str = "your_verify_token_here"
    META_ACCESS_TOKEN: str = "your_access_token_here"
    META_PHONE_NUMBER_ID: str = "your_phone_number_id"
    META_API_VERSION: str = "v18.0"
    META_API_BASE_URL: str = "https://graph.facebook.com"
    
    # Backend API Configuration
    BACKEND_API_URL: str = "http://backend-api:8000"
    BACKEND_API_TIMEOUT: int = 30
    
    # Application Settings
    APP_NAME: str = "WhatsApp Gateway"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"
    
    # Server Configuration
    HOST: str = "0.0.0.0"
    PORT: int = 40000
    
    # Multi-tenant
    DEFAULT_TENANT_ID: str = "default"
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance"""
    return Settings()


settings = get_settings()
