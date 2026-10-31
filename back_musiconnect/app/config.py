from typing import Optional
from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str

    # Scheduler (APScheduler) — desative com SCHEDULER_ENABLED=false em dev/testes
    scheduler_enabled: bool = True
    scheduler_etl_hour: int = 0      # ETL às 00:00 (America/Sao_Paulo)
    scheduler_scrapers_hour: int = 6  # Scrapers às 06:00 (ativo após Etapa 4)

    # LLM — Google Gemini para enriquecimento de oportunidades
    gemini_api_key: Optional[str] = None

    # E-mail de confirmação de cadastro (Resend)
    resend_api_key: Optional[str] = None
    resend_from_email: str = "nao-responda@musiconnect.app.br"

    # Chave das rotas de administração (disparo manual de scraper/LLM/ETL
    # e status do agendador) — enviada no header X-Admin-Key. Sem ela
    # configurada, essas rotas ficam sempre bloqueadas. repr=False: não
    # aparece em logs/erros que imprimem as configurações.
    admin_api_key: Optional[str] = Field(default=None, repr=False)

    # Endereço público do app — base dos links dos e-mails
    # (https://musiconnect.app.br/confirmar?token=...).
    public_base_url: str = "https://musiconnect.app.br"

    # App Links do Android (/.well-known/assetlinks.json): pacote do app e
    # impressões digitais SHA-256 das chaves que o assinam, separadas por
    # vírgula. Não são segredo — o Android as publica. Release (APK
    # assinado com a chave de android/key.properties) e debug (flutter run).
    android_package_name: str = "musiconnect.com.prototipo_musiconnect"
    android_cert_fingerprints: str = (
        "1A:87:6A:F3:59:61:67:1A:44:47:BB:45:C0:CA:F9:A2:"
        "6E:4C:36:94:7F:71:BB:C7:EE:DD:14:3B:2A:DE:B3:A6,"
        "1D:7F:4B:21:35:69:65:83:6E:D3:88:CD:49:41:75:27:"
        "7D:66:4B:EE:55:82:27:8B:1D:9F:A0:46:42:51:59:77"
    )

    class Config:
        env_file = ".env"
        # O .env também guarda variáveis que não são da API (ex:
        # TEST_DATABASE_URL, usada só pelos testes).
        extra = "ignore"


settings = Settings()
