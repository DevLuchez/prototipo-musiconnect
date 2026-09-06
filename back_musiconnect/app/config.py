from typing import Optional
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str

    # Scheduler (APScheduler) — desative com SCHEDULER_ENABLED=false em dev/testes
    scheduler_enabled: bool = True
    scheduler_etl_hour: int = 0      # ETL às 00:00 (America/Sao_Paulo)
    scheduler_scrapers_hour: int = 6  # Scrapers às 06:00 (ativo após Etapa 4)

    # LLM — Google Gemini para enriquecimento de oportunidades
    gemini_api_key: Optional[str] = None

    class Config:
        env_file = ".env"


settings = Settings()
