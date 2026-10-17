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
        "5C:00:89:89:49:A8:99:90:18:9B:7A:FC:93:FB:00:25:"
        "09:A2:AA:86:5D:5D:23:D1:A6:AD:C3:11:B6:22:F4:40,"
        "66:57:2B:37:AF:36:19:1E:42:FE:20:62:29:D8:80:7F:"
        "AE:98:FF:54:41:5B:20:66:71:E0:E1:54:F7:0C:E9:EC"
    )

    class Config:
        env_file = ".env"
        # O .env também guarda variáveis que não são da API (ex:
        # TEST_DATABASE_URL, usada só pelos testes).
        extra = "ignore"


settings = Settings()
