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

    model_config = {"from_attributes": True}


class NearbySearchParams(BaseModel):
    """Parâmetros da busca por proximidade."""

    lat: float
    lng: float
    radius_m: int = 50_000   # raio padrão: 50km
    limit: int = 500          # máximo de resultados por chamada
