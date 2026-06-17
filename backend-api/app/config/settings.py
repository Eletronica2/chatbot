"""Application settings for Backend API."""
from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Centralized configuration loaded from environment variables."""

    APP_NAME: str = "Backend API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    HOST: str = "0.0.0.0"
    PORT: int = 8000

    FLOW_ENGINE_URL: str = "http://flow-engine:8002"
    FLOW_ENGINE_TIMEOUT: int = 15

    AI_ENGINE_URL: str = "http://ai-engine:8003"
    AI_ENGINE_TIMEOUT: int = 20

    DATABASE_URL: str = "mysql+pymysql://chatbot:chatbot@mysql:3306/chatbot"

    SESSION_TTL_SECONDS: int = 3600
    DEFAULT_TENANT_ID: str = "default"
    DEFAULT_TENANT_NAME: str = "Operacao SaaS"
    DEFAULT_TENANT_EMAIL: str = "operacao@chatbot.local"

    DEFAULT_ADMIN_EMAIL: str = "arthurlaranjo@hotmail.com"
    DEFAULT_ADMIN_PASSWORD: str = "adminpanel"
    DEFAULT_ADMIN_NAME: str = "Arthur Laranjo"
    DEFAULT_ADMIN_ROLE: str = "superadmin"
    BOOTSTRAP_COMPANY_TENANT_ID: str = "loja_centro_demo"
    BOOTSTRAP_COMPANY_NAME: str = "Loja Centro Demo"
    BOOTSTRAP_COMPANY_EMAIL: str = "contato@lojacentro.local"
    BOOTSTRAP_COMPANY_ADMIN_NAME: str = "Admin Loja Centro"
    BOOTSTRAP_COMPANY_ADMIN_EMAIL: str = "admin@lojacentro.local"
    BOOTSTRAP_COMPANY_ADMIN_PASSWORD: str = "empresa123"
    BOOTSTRAP_COMPANY_PLAN: str = "starter"
    BOOTSTRAP_COMPANY_MONTHLY_MESSAGE_LIMIT: int = 1000

    APP_SECRET_KEY: str = "change-me-backend-secret"
    JWT_EXPIRES_MINUTES: int = 720
    INTERNAL_API_KEY: str = "internal-chatbot-key"
    ADMIN_PANEL_URL: str = "http://localhost:8000"
    INVITE_TOKEN_TTL_HOURS: int = 72
    RESET_TOKEN_TTL_HOURS: int = 2
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM_EMAIL: str = "no-reply@chatbot.local"
    SMTP_FROM_NAME: str = "Chatbot SaaS"
    SMTP_USE_TLS: bool = True
    SMTP_USE_SSL: bool = False

    BILLING_PROVIDER: str = "stripe"
    BILLING_GRACE_DAYS: int = 3
    BILLING_SUCCESS_URL: str = "http://localhost:8000/#/billing/success?session_id={CHECKOUT_SESSION_ID}"
    BILLING_CANCEL_URL: str = "http://localhost:8000/#/billing/cancel"
    BILLING_PORTAL_RETURN_URL: str = "http://localhost:8000/#/billing"
    STRIPE_SECRET_KEY: str = ""
    STRIPE_WEBHOOK_SECRET: str = ""
    STRIPE_PRICE_STARTER: str = ""
    STRIPE_PRICE_GROWTH: str = ""
    STRIPE_PRICE_PRO: str = ""
    STRIPE_PRICE_ENTERPRISE: str = ""
    STRIPE_DEFAULT_CURRENCY: str = "brl"

    GATEWAY_API_URL: str = "http://whatsapp-gateway:40000"
    GATEWAY_API_TIMEOUT: int = 15

    META_APP_ID: str = ""
    META_APP_SECRET: str = ""
    META_EMBEDDED_CONFIG_ID: str = ""
    META_API_VERSION: str = "v22.0"
    META_API_BASE_URL: str = "https://graph.facebook.com"
    META_API_TIMEOUT: int = 30
    META_VERIFY_TOKEN: str = "super-secret-webhook-token"
    META_DATA_DELETION_BASE_URL: str = "https://eletronica2.github.io/chatbot/data-deletion.html"
    META_TEST_RECIPIENT: str = "5534992665547"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

