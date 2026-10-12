from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="ignore")

    app_name: str = "Atende Ai Local AI API"
    app_version: str = "0.1.0"

    ollama_url: str = "http://ollama:11434"
    llm_model: str = "qwen3:4b-instruct-2507-q4_K_M"
    allowed_models: str = "qwen3:4b-instruct-2507-q4_K_M,qwen3:1.7b-q4_K_M"
    llm_num_ctx: int = 4096
    llm_temperature: float = 0.3
    llm_max_tokens: int = 192
    llm_keep_alive: str = "30m"
    llm_timeout_s: float = 120.0

    llm_concurrency: int = Field(1, ge=1, le=4)
    llm_max_queue: int = Field(3, ge=0, le=32)
    llm_queue_timeout_s: float = 90.0

    qdrant_url: str = "http://qdrant:6333"
    qdrant_api_key: str = ""
    qdrant_collection: str = "atende_knowledge"

    embedding_model: str = "google/embeddinggemma-2"
    embedding_dim: int = 768
    embedding_threads: int = 4

    retrieval_top_k: int = 3
    retrieval_min_score: float = 0.0
    retrieval_mode: str = "hybrid"

    history_max_messages: int = 6
    history_max_chars: int = 1500
    message_max_chars: int = 1000

    credentials_file: str = "/config/credentials.json"
    tenants_file: str = "/config/tenants.json"

    ready_inference_ttl_s: float = 600.0
    log_level: str = "INFO"

    @property
    def allowed_model_list(self) -> list[str]:
        return [m.strip() for m in self.allowed_models.split(",") if m.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
