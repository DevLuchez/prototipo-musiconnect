from pydantic import BaseModel
from typing import Optional


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
    description: Optional[str] = None
    mb_id: Optional[str] = None       # MusicBrainz Place ID
    wikidata_id: Optional[str] = None  # Wikidata QID (ex: Q4944615)

    model_config = {"from_attributes": True}


class NearbySearchParams(BaseModel):
    """Parâmetros da busca por proximidade."""

    lat: float
    lng: float
    radius_m: int = 50_000   # raio padrão: 50km
    limit: int = 500          # máximo de resultados por chamada
