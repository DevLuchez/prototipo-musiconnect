from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import date, datetime


class InstitutionOut(BaseModel):
    """Schema de saída — o que o Flutter recebe."""

    osm_id: str
    name: str
    address: Optional[str] = None
    lat: float
    lng: float
    category: str
    source: str

    # Campos de validação cruzada
    verified: bool = False
    website: Optional[str] = None
    email: Optional[str] = None
    mb_id: Optional[str] = None       # MusicBrainz Place ID
    wikidata_id: Optional[str] = None  # Wikidata QID (ex: Q4944615)

    # Oportunidades visíveis no app vinculadas a este pino — > 0 destaca o
    # marcador no mapa.
    active_opportunities_count: int = 0

    model_config = {"from_attributes": True}


class NearbySearchParams(BaseModel):
    """Parâmetros da busca por proximidade."""

    lat: float
    lng: float
    radius_m: int = 50_000   # raio padrão: 50km
    limit: int = 500          # máximo de resultados por chamada


class MatchBreakdownOut(BaseModel):
    """Detalhamento do match_percentage — cada campo é quantos pontos esse
    fator contribuiu, de um máximo próprio (`*_max`, pesos diferentes por
    fator); a soma dos quatro é o match_percentage."""

    instrument: int
    affinity: int
    location: int
    confidence: int
    instrument_max: int
    affinity_max: int
    location_max: int
    confidence_max: int

    model_config = {"from_attributes": True}


class CityOpportunitiesOut(BaseModel):
    """Marcador "oportunidades por cidade" do mapa: oportunidades visíveis
    daquela cidade cuja organizadora não pôde ser localizada."""

    id: int  # city_locations.id
    city: str
    state: Optional[str] = None
    country: Optional[str] = None
    lat: float
    lng: float
    opportunities_count: int


class OpportunityOut(BaseModel):
    """Schema de saída de oportunidade — o que o Flutter recebe na aba Matcher."""

    id: int
    title: str
    type: Optional[str] = None
    source_url: Optional[str] = None
    source_name: Optional[str] = None
    instruments: Optional[List[str]] = None
    level: Optional[str] = None
    deadline: Optional[date] = None
    country: Optional[str] = None
    state: Optional[str] = None
    city: Optional[str] = None
    is_remote: Optional[bool] = None
    description: Optional[str] = None
    institution: Optional[str] = None
    # Pino do mapa da organizadora (osm_id) — None quando remota ou não localizada
    institution_id: Optional[str] = None
    # Centro da cidade no mapa (marcador "oportunidades por cidade") — só
    # usado quando não há institution_id
    city_location_id: Optional[int] = None
    scraped_at: Optional[datetime] = None
    enriched_at: Optional[datetime] = None
    is_active: bool = True
    llm_confidence: float = 1.0

    # Percentual de compatibilidade (0-100) com o usuário logado — None
    # quando a requisição não veio autenticada.
    match_percentage: Optional[int] = None
    match_breakdown: Optional[MatchBreakdownOut] = None

    model_config = {"from_attributes": True}


class SignupIn(BaseModel):
    """Schema de entrada do cadastro — dados coletados nos 3 passos do wizard."""

    email: EmailStr
    password: str
    name: str

    instruments: List[str] = []
    is_professional: bool = False
    is_student: bool = False

    country: Optional[str] = None
    state: Optional[str] = None
    city: Optional[str] = None


class ResendIn(BaseModel):
    email: EmailStr


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class ForgotPasswordIn(BaseModel):
    email: EmailStr


class ResetPasswordIn(BaseModel):
    token: str
    password: str


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str


class DeleteAccountIn(BaseModel):
    # Confirmação de senha antes de excluir — ação irreversível.
    password: str


class ProfileUpdateIn(BaseModel):
    """Edição de perfil — substitui o registro inteiro (mesmo padrão do
    signup). E-mail fica de fora: trocar e-mail exigiria reconfirmação,
    um fluxo à parte que não existe ainda."""

    name: str
    instruments: List[str] = []
    is_professional: bool = False
    is_student: bool = False
    country: Optional[str] = None
    state: Optional[str] = None
    city: Optional[str] = None


class UserOut(BaseModel):
    id: int
    email: str
    name: str
    instruments: List[str] = []
    is_professional: bool = False
    is_student: bool = False
    country: Optional[str] = None
    state: Optional[str] = None
    city: Optional[str] = None
    # Só vem preenchido nas respostas de login/troca de senha — o cliente
    # usa esse valor pra atualizar o token guardado localmente.
    token: Optional[str] = None

    model_config = {"from_attributes": True}


class ConfirmIn(BaseModel):
    token: str


class ConfirmStatusOut(BaseModel):
    confirmed: bool
