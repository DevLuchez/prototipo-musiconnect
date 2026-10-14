"""
Proteção das rotas de administração (disparo manual de scraper, LLM, ETL
e resolvedor, e status do agendador).

Não há usuário "administrador" no app: essas rotas são usadas só pela
desenvolvedora (curl ou /docs do FastAPI), com a chave ADMIN_API_KEY do
.env enviada no header `X-Admin-Key`. O agendador diário roda dentro do
servidor e não passa por elas.
"""

import secrets

from fastapi import HTTPException, Security
from fastapi.security import APIKeyHeader

from app.config import settings

# auto_error=False: a ausência do header cai no mesmo 403 da chave errada.
# Declarado via APIKeyHeader para o /docs mostrar o botão "Authorize".
_admin_key_header = APIKeyHeader(name="X-Admin-Key", auto_error=False)


def require_admin_key(key: str | None = Security(_admin_key_header)) -> None:
    """Dependência das rotas de administração: libera só com a chave certa.
    Sem ADMIN_API_KEY configurada no servidor, bloqueia sempre — esquecer
    de configurar nunca deixa as rotas abertas."""
    expected = settings.admin_api_key
    # compare_digest: comparação em tempo constante (não revela, pelo tempo
    # de resposta, quantos caracteres iniciais da chave estão certos).
    if not expected or not key or not secrets.compare_digest(key, expected):
        raise HTTPException(status_code=403, detail="Acesso restrito à administração.")
