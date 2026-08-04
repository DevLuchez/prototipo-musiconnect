from sqlalchemy import Column, String, Float, DateTime, Boolean, Text, Index, func
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
