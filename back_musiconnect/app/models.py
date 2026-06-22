from sqlalchemy import Column, String, Float, DateTime, Index, func
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

    # Categorias: music_school, concert_hall, theatre, music_venue, etc.
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


# Índice espacial GIST — essencial para ST_DWithin ser rápido em milhares de registros
Index("ix_institutions_location", Institution.location, postgresql_using="gist")
