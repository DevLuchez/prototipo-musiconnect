"""
Router da versão do app — o app consulta ao abrir (e a cada volta a ele)
e, se houver versão mais nova que a instalada, só segue depois de
atualizar (toda versão nova é obrigatória — decisão da Laura, 06/11/2026).

Endpoint:
  GET /api/app/version → {"latest", "minimum", "download_url"}

- latest: versão mais recente publicada — a tag do último release do
  GitHub (o mesmo que o link de download baixa), sem o "v". Publicar uma
  tag já atualiza o aviso, sem mexer no servidor. Guardada por
  CACHE_TTL; se o GitHub não responder, vale a última conhecida (ou null:
  o app não avisa nada).
- minimum: versão mínima aceita (APP_MINIMUM_VERSION no .env, vazia por
  padrão) — reserva para quando o GitHub não responder (latest null).
"""

import logging
import time
from typing import Optional

import httpx
from fastapi import APIRouter
from pydantic import BaseModel

from app.config import settings

logger = logging.getLogger("routers.app_version")

router = APIRouter(prefix="/api/app", tags=["app"])

GITHUB_LATEST_RELEASE = (
    "https://api.github.com/repos/DevLuchez/prototipo-musiconnect/releases/latest"
)
# A API do GitHub sem login aceita 60 consultas por hora por IP.
CACHE_TTL = 10 * 60

# fetched_at None = nunca consultado (não dá para usar 0: o relógio
# monotônico conta desde que a máquina ligou, e pode estar perto de 0).
_cache: dict = {"version": None, "fetched_at": None}


class AppVersionOut(BaseModel):
    latest: Optional[str] = None
    minimum: Optional[str] = None
    download_url: str


def fetch_latest_release() -> Optional[str]:
    """Versão do último release do GitHub ("v1.2.2" → "1.2.2")."""
    response = httpx.get(GITHUB_LATEST_RELEASE, timeout=10)
    response.raise_for_status()
    return response.json()["tag_name"].lstrip("v")


# Última versão do app que não informava a versão instalada ao registrar
# o aparelho: aparelho sem versão está nela (ou antes).
LAST_UNREPORTED_VERSION = "1.2.5"


def is_older(version: Optional[str], than: str) -> bool:
    """"1.2.9" é mais antiga que "1.2.10"? Versão desconhecida (None) conta
    como LAST_UNREPORTED_VERSION — quem está na 1.2.5 não é avisado da
    própria 1.2.5, só a partir da seguinte."""
    version = version or LAST_UNREPORTED_VERSION

    def parts(v: str) -> list[int]:
        return [int(p) if p.isdigit() else 0 for p in v.split(".")]

    a, b = parts(version), parts(than)
    size = max(len(a), len(b))
    return a + [0] * (size - len(a)) < b + [0] * (size - len(b))


def latest_version() -> Optional[str]:
    fetched_at = _cache["fetched_at"]
    if fetched_at is not None and time.monotonic() - fetched_at < CACHE_TTL:
        return _cache["version"]
    try:
        _cache["version"] = fetch_latest_release()
    except Exception as e:
        logger.warning("[Versão] GitHub não respondeu: %s", e)
    # Mesmo com falha: tenta de novo só depois do CACHE_TTL.
    _cache["fetched_at"] = time.monotonic()
    return _cache["version"]


@router.get("/version", response_model=AppVersionOut)
def app_version():
    return AppVersionOut(
        latest=latest_version(),
        minimum=settings.app_minimum_version or None,
        download_url=settings.app_download_url,
    )
