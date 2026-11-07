from pydantic import BaseModel, EmailStr, Field, field_validator
from typing import Dict, Optional, List
from datetime import date, datetime

# As docstrings das classes e as docstrings logo abaixo de cada campo viram
# as descrições do Swagger (/docs) — `use_attribute_docstrings`. Escritas
# para quem consome a API; notas internas ficam em comentários (#).


class InstitutionOut(BaseModel):
    """Instituição musical exibida no mapa."""

    # Schema de saída — o que o Flutter recebe.

    osm_id: str
    """Identificador da instituição no OpenStreetMap (ex.: `way_256649111`)."""
    name: str
    """Nome da instituição."""
    address: Optional[str] = None
    """Endereço, quando informado no OpenStreetMap."""
    lat: float
    """Latitude."""
    lng: float
    """Longitude."""
    category: str
    """Categoria: `music_school` (escola de música), `arts_centre` (centro cultural), `theatre` (teatro ou ópera), `concert_hall` (sala de concerto), `music_venue` (música ao vivo) ou `music_org` (orquestra, festival ou organização)."""
    source: str
    """Origem do registro: `osm` (atualização diária do mapa) ou `pipeline` (criada a partir de uma oportunidade)."""

    # Campos de validação cruzada
    verified: bool = False
    """Se a instituição foi confirmada no MusicBrainz ou no Wikidata."""
    website: Optional[str] = None
    """Site da instituição."""
    email: Optional[str] = None
    """E-mail de contato."""
    mb_id: Optional[str] = None       # MusicBrainz Place ID
    """Identificador no MusicBrainz."""
    wikidata_id: Optional[str] = None  # Wikidata QID (ex: Q4944615)
    """Identificador no Wikidata (ex.: `Q4944615`)."""

    # Oportunidades visíveis no app vinculadas a este pino — > 0 destaca o
    # marcador no mapa.
    active_opportunities_count: int = 0
    """Quantidade de oportunidades abertas vinculadas à instituição (acima de 0, o marcador recebe estrela)."""

    # Quando o usuário favoritou — só vem na lista de favoritos.
    saved_at: Optional[datetime] = None
    """Data em que o usuário favoritou a instituição (somente na lista de favoritos)."""

    model_config = {"from_attributes": True, "use_attribute_docstrings": True}


class NearbySearchParams(BaseModel):
    """Parâmetros da busca por proximidade."""

    lat: float
    lng: float
    radius_m: int = 50_000   # raio padrão: 50km
    limit: int = 500          # máximo de resultados por chamada


class MatchBreakdownOut(BaseModel):
    """Detalhamento do percentual de match: pontos obtidos em cada fator e o
    máximo de cada um. A soma dos quatro fatores é o `match_percentage`."""

    instrument: int
    """Pontos do fator instrumento."""
    affinity: int
    """Pontos do fator ramo de atuação × tipo de oportunidade."""
    location: int
    """Pontos do fator localização."""
    confidence: int
    """Pontos do fator confiança da interpretação por IA."""
    instrument_max: int
    """Máximo do fator instrumento (45)."""
    affinity_max: int
    """Máximo do fator ramo de atuação (20)."""
    location_max: int
    """Máximo do fator localização (20)."""
    confidence_max: int
    """Máximo do fator confiança (15)."""

    model_config = {"from_attributes": True, "use_attribute_docstrings": True}


class CityOpportunitiesOut(BaseModel):
    """Marcador de cidade no mapa: oportunidades abertas da cidade cuja
    instituição não possui endereço exato."""

    id: int  # city_locations.id
    """Identificador da cidade."""
    city: str
    """Nome da cidade."""
    state: Optional[str] = None
    """Estado ou região."""
    country: Optional[str] = None
    """País."""
    lat: float
    """Latitude do centro da cidade."""
    lng: float
    """Longitude do centro da cidade."""
    opportunities_count: int
    """Quantidade de oportunidades abertas agrupadas no marcador."""

    model_config = {"use_attribute_docstrings": True}


class OpportunityOut(BaseModel):
    """Oportunidade musical interpretada pela IA."""

    # Schema de saída de oportunidade — o que o Flutter recebe na aba Matcher.

    id: int
    """Identificador da oportunidade."""
    title: str
    """Título em português."""
    type: Optional[str] = None
    """Tipo: `audicao`, `competicao`, `emprego` ou `curso`."""
    source_url: Optional[str] = None
    """Link para o edital original."""
    source_name: Optional[str] = None
    """Fonte de onde o edital foi coletado (ex.: Musical Chairs, WFIMC)."""
    instruments: Optional[List[str]] = None
    """Instrumentos exigidos. Vazio quando o edital não especifica (aberto a qualquer instrumento)."""
    level: Optional[str] = None
    """Nível técnico, quando informado no edital (não usado no match)."""
    deadline: Optional[date] = None
    """Prazo de inscrição."""
    country: Optional[str] = None
    """País."""
    state: Optional[str] = None
    """Estado ou região."""
    city: Optional[str] = None
    """Cidade."""
    is_remote: Optional[bool] = None
    """Se a oportunidade é remota (online)."""
    description: Optional[str] = None
    """Resumo do edital em português, gerado pela IA."""
    institution: Optional[str] = None
    """Nome da instituição responsável, como consta no edital."""
    # Pino do mapa da organizadora (osm_id) — None quando remota ou não localizada
    institution_id: Optional[str] = None
    """Identificador da instituição no mapa (`osm_id`), quando localizada."""
    # Centro da cidade no mapa (marcador "oportunidades por cidade") — só
    # usado quando não há institution_id
    city_location_id: Optional[int] = None
    """Identificador do marcador de cidade, quando a instituição não foi localizada."""
    scraped_at: Optional[datetime] = None
    """Data da última coleta."""
    enriched_at: Optional[datetime] = None
    """Data da interpretação pela IA."""
    is_active: bool = True
    """Se a oportunidade continua disponível na fonte."""
    llm_confidence: float = 1.0
    """Confiança da interpretação pela IA, de 0 a 1 (somente oportunidades a partir de 0,8 são exibidas)."""

    # Percentual de compatibilidade (0-100) com o usuário logado — None
    # quando a requisição não veio autenticada.
    match_percentage: Optional[int] = None
    """Percentual de compatibilidade com o usuário autenticado (0 a 100). Nulo sem autenticação."""
    match_breakdown: Optional[MatchBreakdownOut] = None
    """Detalhamento do match por fator. Nulo sem autenticação."""

    # Quando o usuário salvou — só vem na lista de oportunidades salvas.
    saved_at: Optional[datetime] = None
    """Data em que o usuário favoritou a oportunidade (somente na lista de favoritos)."""

    model_config = {"from_attributes": True, "use_attribute_docstrings": True}


class FavoriteIdsOut(BaseModel):
    """Identificadores das oportunidades e instituições favoritas do usuário."""

    # O app usa pra desenhar os corações.

    opportunities: List[int] = []
    """Identificadores das oportunidades favoritas."""
    institutions: List[str] = []
    """Identificadores (`osm_id`) das instituições favoritas."""

    model_config = {"use_attribute_docstrings": True}


class SignupIn(BaseModel):
    """Dados do cadastro."""

    # Dados coletados nos passos do wizard de cadastro do app.

    email: EmailStr
    """E-mail, usado no login e na confirmação."""
    password: str
    """Senha: no mínimo 8 caracteres e ao menos dois critérios entre maiúsculas e minúsculas, números e caracteres especiais."""
    name: str
    """Nome de usuário."""

    instruments: List[str] = []
    """Instrumentos do músico (nomes da lista oficial do app)."""
    is_professional: bool = False
    """Se busca oportunidades como profissional."""
    is_student: bool = False
    """Se busca oportunidades como estudante."""

    country: Optional[str] = None
    """País."""
    state: Optional[str] = None
    """Estado."""
    city: Optional[str] = None
    """Cidade."""

    # Consentimento explícito com a Política de privacidade (LGPD) —
    # obrigatório e precisa ser True; sem ele o cadastro é recusado.
    privacy_accepted: bool
    """Aceite da política de privacidade. Obrigatório e precisa ser `true`."""

    # Versão da Política de privacidade que a pessoa leu no app (data, ex:
    # "2026-10-31"). O app v1.0.0 não envia — vale LEGACY_PRIVACY_POLICY_VERSION.
    privacy_policy_version: Optional[str] = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    """Versão da política aceita (data no formato `AAAA-MM-DD`)."""

    model_config = {"use_attribute_docstrings": True}

    @field_validator("privacy_accepted")
    @classmethod
    def _must_accept_privacy(cls, value: bool) -> bool:
        if not value:
            raise ValueError("É preciso aceitar a Política de privacidade.")
        return value


class PrivacyAcceptIn(BaseModel):
    """Novo aceite da política de privacidade."""

    privacy_policy_version: Optional[str] = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    """Versão da política lida pelo usuário (data no formato `AAAA-MM-DD`)."""

    model_config = {"use_attribute_docstrings": True}


class ResendIn(BaseModel):
    """Pedido de reenvio do e-mail de confirmação."""

    email: EmailStr
    """E-mail cadastrado."""

    model_config = {"use_attribute_docstrings": True}


class LoginIn(BaseModel):
    """Credenciais de acesso."""

    email: EmailStr
    """E-mail cadastrado."""
    password: str
    """Senha."""

    model_config = {"use_attribute_docstrings": True}


class ForgotPasswordIn(BaseModel):
    """Pedido de redefinição de senha."""

    email: EmailStr
    """E-mail cadastrado."""

    model_config = {"use_attribute_docstrings": True}


class ResetPasswordIn(BaseModel):
    """Nova senha definida a partir do link enviado por e-mail."""

    token: str
    """Código de redefinição recebido no link do e-mail (válido por 15 minutos)."""
    password: str
    """Nova senha, seguindo a mesma regra do cadastro."""

    model_config = {"use_attribute_docstrings": True}


class ChangePasswordIn(BaseModel):
    """Troca de senha pelo usuário autenticado."""

    current_password: str
    """Senha atual."""
    new_password: str
    """Nova senha, seguindo a mesma regra do cadastro."""

    model_config = {"use_attribute_docstrings": True}


class DeleteAccountIn(BaseModel):
    """Confirmação da exclusão da conta."""

    # Confirmação de senha antes de excluir — ação irreversível.
    password: str
    """Senha atual, exigida porque a exclusão é irreversível."""

    model_config = {"use_attribute_docstrings": True}


class ProfileUpdateIn(BaseModel):
    """Edição do perfil. Substitui todos os campos; o e-mail não pode ser alterado."""

    # Substitui o registro inteiro (mesmo padrão do signup). E-mail fica de
    # fora: trocar e-mail exigiria reconfirmação, um fluxo à parte que não
    # existe ainda.

    name: str
    """Nome de usuário."""
    instruments: List[str] = []
    """Instrumentos do músico."""
    is_professional: bool = False
    """Se busca oportunidades como profissional."""
    is_student: bool = False
    """Se busca oportunidades como estudante."""
    country: Optional[str] = None
    """País."""
    state: Optional[str] = None
    """Estado."""
    city: Optional[str] = None
    """Cidade."""

    model_config = {"use_attribute_docstrings": True}


class UserOut(BaseModel):
    """Dados do usuário autenticado."""

    id: int
    """Identificador do usuário."""
    email: str
    """E-mail."""
    name: str
    """Nome de usuário."""
    instruments: List[str] = []
    """Instrumentos do músico."""
    is_professional: bool = False
    """Se busca oportunidades como profissional."""
    is_student: bool = False
    """Se busca oportunidades como estudante."""
    country: Optional[str] = None
    """País."""
    state: Optional[str] = None
    """Estado."""
    city: Optional[str] = None
    """Cidade."""
    # Versão da Política de privacidade que o usuário aceitou — o app
    # compara com a atual e pede um novo aceite quando a política muda.
    privacy_policy_version: Optional[str] = None
    """Versão da política de privacidade aceita. O aplicativo pede novo aceite quando a política muda."""
    # Chaves de notificação do Perfil.
    notify_new_matches: bool = True
    """Se recebe avisos de novas oportunidades com match a partir de 85%."""
    notify_deadlines: bool = True
    """Se recebe avisos de prazos dos favoritos."""
    notify_app_updates: bool = True
    """Se recebe avisos de nova versão do aplicativo."""
    # Só vem preenchido nas respostas de login/troca de senha — o cliente
    # usa esse valor pra atualizar o token guardado localmente.
    token: Optional[str] = None
    """Token de sessão. Retornado somente no login e na troca de senha; deve ser enviado no cabeçalho `Authorization: Bearer <token>`."""

    model_config = {"from_attributes": True, "use_attribute_docstrings": True}


class ConfirmIn(BaseModel):
    """Confirmação do e-mail a partir do link recebido."""

    token: str
    """Código de confirmação recebido no link do e-mail (válido por 24 horas)."""

    model_config = {"use_attribute_docstrings": True}


class ConfirmStatusOut(BaseModel):
    """Situação da confirmação do e-mail."""

    confirmed: bool
    """Se o e-mail já foi confirmado."""

    model_config = {"use_attribute_docstrings": True}


class DeviceTokenIn(BaseModel):
    """Identificador do aparelho no Firebase Cloud Messaging."""

    token: str = Field(min_length=1, max_length=4096)
    """Token do aparelho gerado pelo Firebase Cloud Messaging."""
    # Versão do app instalada ("1.2.6"). Apps até a 1.2.5 não enviam.
    app_version: Optional[str] = Field(default=None, max_length=20)
    """Versão do aplicativo instalada no aparelho (ex.: `1.2.6`)."""

    model_config = {"use_attribute_docstrings": True}


class NotificationPreferencesIn(BaseModel):
    """Preferências de notificação do perfil."""

    notify_new_matches: bool
    """Receber avisos de novas oportunidades com match a partir de 85%."""
    notify_deadlines: bool
    """Receber avisos de prazos dos favoritos."""
    # Apps até a 1.2.5 não têm essa chave — sem ela, fica como está.
    notify_app_updates: Optional[bool] = None
    """Receber avisos de nova versão do aplicativo (opcional; ausente, mantém o valor atual)."""

    model_config = {"use_attribute_docstrings": True}


# ── Respostas documentadas no Swagger ───────────────────────────────────
# Rotas que devolvem dicionários usam estes modelos só na documentação
# (`responses=`), sem mudar o que retornam.


class ErrorOut(BaseModel):
    """Erro retornado pela API."""

    detail: str
    """Mensagem de erro, em português."""

    model_config = {"use_attribute_docstrings": True}


class HealthOut(BaseModel):
    """Situação da API."""

    status: str
    """`ok` quando a API está disponível."""
    service: str
    """Nome do serviço."""
    version: str
    """Versão da API."""

    model_config = {"use_attribute_docstrings": True}


class StatusOut(BaseModel):
    """Resultado de uma operação."""

    status: str
    """Situação da operação (ex.: `sent`, `confirmed`, `reset`, `logged_out`, `deleted`)."""
    email: Optional[str] = None
    """E-mail envolvido na operação, quando houver."""
    message: Optional[str] = None
    """Mensagem complementar, quando houver."""

    model_config = {"use_attribute_docstrings": True}


class InstitutionStatsOut(BaseModel):
    """Estatísticas das instituições do mapa."""

    total: int
    """Total de instituições."""
    by_category: Dict[str, int]
    """Quantidade de instituições por categoria."""
    with_active_opportunities: int
    """Instituições com pelo menos uma oportunidade aberta."""
    last_etl_run: Optional[str] = None
    """Data da última atualização do mapa."""

    model_config = {"use_attribute_docstrings": True}


class StateOptionOut(BaseModel):
    """Estado disponível no filtro."""

    value: str
    """Código usado no filtro (ex.: `SC`)."""
    label: str
    """Nome por extenso (ex.: `Santa Catarina`)."""

    model_config = {"use_attribute_docstrings": True}


class FilterOptionsOut(BaseModel):
    """Valores disponíveis nos filtros de oportunidades."""

    instruments: List[str]
    """Instrumentos presentes nas oportunidades abertas."""
    countries: List[str]
    """Países."""
    states: List[StateOptionOut]
    """Estados."""
    cities: List[str]
    """Cidades."""

    model_config = {"use_attribute_docstrings": True}


class MatchCountOut(BaseModel):
    """Quantidade de oportunidades compatíveis com o usuário."""

    count: int
    """Oportunidades abertas com match igual ou superior ao limite."""
    threshold: int
    """Limite de alta compatibilidade (85)."""

    model_config = {"use_attribute_docstrings": True}


class AdminTaskOut(BaseModel):
    """Rotina iniciada em segundo plano."""

    status: str
    """`started` quando a rotina foi iniciada."""
    message: str
    """Orientação sobre o acompanhamento da rotina."""

    model_config = {"use_attribute_docstrings": True}


class SchedulerJobOut(BaseModel):
    """Rotina agendada."""

    id: str
    """Identificador da rotina."""
    name: str
    """Descrição da rotina."""
    next_run: Optional[str] = None
    """Próxima execução (data e hora)."""
    status: str
    """`active` ou `paused`."""

    model_config = {"use_attribute_docstrings": True}


class SchedulerStatusOut(BaseModel):
    """Situação do agendador de rotinas."""

    status: str
    """`running` ou `stopped`."""
    timezone: Optional[str] = None
    """Fuso horário das rotinas."""
    total_jobs: Optional[int] = None
    """Quantidade de rotinas agendadas."""
    jobs: List[SchedulerJobOut]
    """Rotinas agendadas."""

    model_config = {"use_attribute_docstrings": True}
