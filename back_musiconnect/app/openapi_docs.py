"""
Textos da documentação interativa da API (Swagger em /docs e ReDoc em
/redoc): descrição geral, grupos de rotas e respostas de erro reutilizadas.

Só documentação — nada aqui muda o comportamento das rotas. Os modelos de
resposta de erro e de status vivem em schemas.py, como os demais.
"""

from app.schemas import ErrorOut

API_VERSION = "1.0.0"

API_DESCRIPTION = """
API do **MusiConnect**, aplicativo que reúne oportunidades musicais (audições,
concursos, vagas, bolsas e cursos), calcula a compatibilidade (*match*) com o
perfil do músico e mapeia as instituições musicais do mundo.

**Autenticação.** As rotas marcadas com cadeado exigem um token de sessão,
obtido em `POST /api/auth/login` (campo `token` da resposta). Para testar aqui,
clique em **Authorize** e informe o token no campo *HTTPBearer*. Sem token, as
rotas públicas funcionam normalmente, mas sem o percentual de match.

**Administração.** As rotas do grupo *Administração* exigem a chave
`X-Admin-Key`, de uso exclusivo da desenvolvedora.

**Visibilidade.** As listagens retornam apenas oportunidades ativas, com prazo
vigente e confiança da interpretação por IA de pelo menos 80%.
"""

OPENAPI_TAGS = [
    {
        "name": "Autenticação",
        "description": "Cadastro, confirmação de e-mail, login, recuperação de senha, perfil e exclusão da conta.",
    },
    {
        "name": "Oportunidades",
        "description": "Listagem, busca, filtros e detalhe das oportunidades, com o percentual de match para o usuário autenticado.",
    },
    {
        "name": "Instituições",
        "description": "Instituições musicais do mapa: busca por proximidade, nome, detalhe e oportunidades vinculadas.",
    },
    {
        "name": "Início",
        "description": "Resumo exibido na tela inicial do aplicativo.",
    },
    {
        "name": "Favoritos",
        "description": "Oportunidades e instituições favoritas do usuário autenticado.",
    },
    {
        "name": "Notificações",
        "description": "Registro do aparelho para notificações e preferências de aviso.",
    },
    {
        "name": "Aplicativo",
        "description": "Informações sobre a versão mais recente do aplicativo.",
    },
    {
        "name": "Administração",
        "description": "Disparo manual das rotinas do pipeline e status do agendador. Exige a chave `X-Admin-Key`.",
    },
    {
        "name": "Sistema",
        "description": "Verificação de disponibilidade da API.",
    },
]


def error(description: str) -> dict:
    """Resposta de erro no formato padrão do FastAPI ({"detail": "..."})."""
    return {"description": description, "model": ErrorOut}


UNAUTHORIZED = {401: error("Sessão ausente ou inválida. É preciso fazer login novamente.")}
ADMIN_ONLY = {403: error("Chave de administração ausente ou incorreta.")}
