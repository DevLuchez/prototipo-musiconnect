from sqlalchemy import (
    Column, String, Float, DateTime, Boolean, Text, Index,
    Integer, Date, func
)
from sqlalchemy.dialects.postgresql import ARRAY
from geoalchemy2 import Geography
from app.database import Base


class Institution(Base):
    """
    Representa uma instituição musical no banco de dados.

    O campo `location` usa o tipo Geography do PostGIS (POINT, SRID 4326),
    que permite consultas de distância precisas em metros sobre a superfície
    real da Terra — sem depender de zoom ou bounding box da tela.
    """

    __tablename__ = "institutions"

    # Identificador único do OSM (ex: "node_123456" ou "way_789")
    osm_id = Column(String, primary_key=True)

    name = Column(String, nullable=False)
    address = Column(String, nullable=True)

    # Coordenadas brutas para leitura direta no response
    lat = Column(Float, nullable=False)
    lng = Column(Float, nullable=False)

    # Categorias: music_school, concert_hall, theatre, music_venue, arts_centre
    category = Column(String, nullable=False, default="music")

    # Fonte de onde veio (osm, google_places, curated)
    source = Column(String, nullable=False, default="osm")

    # Coluna geoespacial com índice GIST para buscas por raio ultra-rápidas
    location = Column(
        Geography(geometry_type="POINT", srid=4326),
        nullable=False,
    )

    # Timestamp da última atualização via ETL
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # ── Campos de validação cruzada (MusicBrainz + Wikidata) ─────────────────
    # True se confirmada por MusicBrainz ou Wikidata
    verified = Column(Boolean, nullable=False, default=False)

    # Site oficial (enriquecido via MusicBrainz ou Wikidata)
    website = Column(String, nullable=True)

    # Descrição curta da instituição (enriquecida via Wikidata, útil para RAG)
    description = Column(Text, nullable=True)

    # ID único no MusicBrainz (ex: "a2d3f7e0-...")
    mb_id = Column(String, nullable=True, unique=True)

    # ID único no Wikidata (ex: "Q123456")
    wikidata_id = Column(String, nullable=True, unique=True)


# Índice espacial GIST — essencial para ST_DWithin ser rápido em milhares de registros
Index("ix_institutions_location", Institution.location, postgresql_using="gist")


class Opportunity(Base):
    """
    Representa uma oportunidade musical coletada pelos scrapers.

    Tipos: audicao, emprego, curso, competicao
    Níveis: iniciante, intermediario, avancado, profissional
    """

    __tablename__ = "opportunities"

    id = Column(Integer, primary_key=True, autoincrement=True)

    title = Column(Text, nullable=False)

    # Tipo de oportunidade
    type = Column(String(50), nullable=True)

    # URL original — usada como chave de deduplicação (UPSERT)
    source_url = Column(Text, nullable=True, unique=True)

    # Nome da fonte (ex: "DOU", "Funarte", "Musical Chairs")
    source_name = Column(String(100), nullable=True)

    # Lista de instrumentos exigidos (ex: ["violino", "piano"])
    instruments = Column(ARRAY(String), nullable=True)

    # Nível de experiência exigido
    level = Column(String(50), nullable=True)

    # Prazo de inscrição
    deadline = Column(Date, nullable=True)

    # Localização
    country = Column(String(100), nullable=True)
    state = Column(String(100), nullable=True)
    city = Column(String(100), nullable=True)

    # True para oportunidades online/remotas
    is_remote = Column(Boolean, nullable=True, default=False)

    description = Column(Text, nullable=True)

    # Texto bruto original (reservado para RAG na Fase 2)
    raw_text = Column(Text, nullable=True)

    scraped_at = Column(DateTime, server_default=func.now())

    # False quando prazo expirou, fonte removeu, ou usuário reportou
    is_active = Column(Boolean, nullable=False, default=True)

    # Confiança do LLM na extração (0.0–1.0). Abaixo de 0.80 não é exibido.
    # Fontes estruturadas (API oficial) recebem 1.0 por padrão.
    llm_confidence = Column(Float, nullable=False, default=1.0)

    # Instituição organizadora (ex: "Orquestra Sinfônica do Estado de SP")
    # Diferente de source_name (plataforma onde foi encontrado)
    institution = Column(Text, nullable=True)

    # Data/hora em que o LLM enriqueceu o registro (NULL = ainda não processado)
    enriched_at = Column(DateTime, nullable=True)


class User(Base):
    """
    Usuário cadastrado no app (fluxo de Cadastre-se do Flutter).

    O registro já é criado no signup (com email_confirmed=False) — o
    `confirmation_token` é o que valida o dono do e-mail. Confirmar não
    cria um segundo registro; só marca este como confirmado.
    """

    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)

    email = Column(String, nullable=False, unique=True, index=True)
    password_hash = Column(String, nullable=False)

    # Nome de exibição — só cosmético (ex: "Olá, Laura"), não substitui o
    # e-mail em nada relacionado a login/autenticação.
    name = Column(String, nullable=False)

    # Sessão — token opaco sem expiração (mesmo padrão do token de
    # confirmação), gerado no login e invalidado no logout ou ao trocar de
    # senha por qualquer via.
    session_token = Column(String, nullable=True, unique=True, index=True)

    # Passo 1: interesses
    instruments = Column(ARRAY(String), nullable=True)
    is_professional = Column(Boolean, nullable=False, default=False)
    is_student = Column(Boolean, nullable=False, default=False)

    # Passo 2: localização
    country = Column(String, nullable=True)
    state = Column(String, nullable=True)
    city = Column(String, nullable=True)

    # Confirmação de e-mail
    email_confirmed = Column(Boolean, nullable=False, default=False)
    confirmation_token = Column(String, nullable=True, unique=True, index=True)
    confirmation_sent_at = Column(DateTime, nullable=True)
    confirmed_at = Column(DateTime, nullable=True)

    # Esqueci minha senha — token de uso único que expira em 30min
    # (diferente do de confirmação, que não expira).
    password_reset_token = Column(String, nullable=True, unique=True, index=True)
    password_reset_sent_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, server_default=func.now())
