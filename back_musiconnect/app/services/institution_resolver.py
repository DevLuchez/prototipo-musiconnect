"""
Resolvedor oportunidade → mapa.

Roda como Etapa 3 do pipeline diário (scraper_task.py) e sob demanda via
POST /scheduler/resolve-institutions (backfill), em duas passadas:

Passada 1 — pino da instituição (`opportunities.institution_id`), a partir
do texto livre `opportunities.institution` (a organizadora extraída pelo
scraper/LLM). Regra de correspondência (decisão D1 — "nome igual + mesma
cidade"):
  1. Procura no banco uma instituição com o MESMO nome normalizado
     (sem acentos/maiúsculas/pontuação) a até 50 km da cidade da
     oportunidade. Nome parecido não conta: preferimos um pino duplicado
     a levar o usuário à instituição errada.
  2. Não achou → geocodifica "organizadora, cidade, país" no Nominatim e
     reaproveita/cria o pino (institution_factory.get_or_create_institution).
  3. Não localizou → deixa NULL e tenta de novo na próxima execução.

Passada 2 — centro da cidade (`opportunities.city_location_id`), para as
que ficaram sem pino de instituição: alimenta o marcador "oportunidades por
cidade" do mapa. A maioria das organizadoras (orquestras, concursos) não
existe como lugar no OpenStreetMap, mas a cidade quase sempre vem no edital.

Oportunidades remotas ou invisíveis no app (inativas / confiança < 0.80)
não são processadas — nunca aparecem no mapa.
"""

import logging
import math
from collections import defaultdict
from typing import Optional

import httpx
from sqlalchemy import or_

from app.database import SessionLocal
from app.models import CityLocation, Institution, Opportunity
from app.services.institution_factory import (
    geocode,
    get_or_create_institution,
    normalize_name,
)

logger = logging.getLogger("services.institution_resolver")

# Distância máxima entre a instituição e o centro da cidade da oportunidade
# para considerar "mesma cidade" (a tabela institutions não tem coluna de
# cidade, e as cidades vêm em português do LLM — ex: "Londres").
SAME_CITY_RADIUS_KM = 50

# Só aceita como "centro da cidade" um resultado que seja de fato uma
# localidade — evita, p.ex., "Split" casar com uma loja homônima.
_CITY_NOMINATIM_CATEGORIES = {"place", "boundary"}


def _distance_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Distância em linha reta (haversine)."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _city_key(opp: Opportunity) -> str:
    return "|".join(normalize_name(p) for p in (opp.city, opp.state, opp.country))


class _Resolver:
    def __init__(self, db, client: httpx.AsyncClient):
        self.db = db
        self.client = client
        # nome normalizado → [(osm_id, lat, lng)] — carregado uma vez por
        # execução (~16k linhas), bem mais barato que uma query por oportunidade.
        self.by_name: dict[str, list[tuple[str, float, float]]] = defaultdict(list)
        for osm_id, name, lat, lng in db.query(
            Institution.osm_id, Institution.name, Institution.lat, Institution.lng
        ):
            self.by_name[normalize_name(name)].append((osm_id, lat, lng))
        # chave da cidade → CityLocation, ou None se já tentamos e não achamos
        self._cities: dict[str, Optional[CityLocation]] = {
            c.key: c for c in db.query(CityLocation)
        }
        # (nome, cidade, país) normalizados → osm_id ou None; evita geocodificar
        # a mesma organizadora de novo quando ela tem várias oportunidades.
        self._resolved: dict[tuple[str, str, str], Optional[str]] = {}

    async def city_location(self, opp: Opportunity) -> Optional[CityLocation]:
        """Centro da cidade da oportunidade (cacheado na tabela city_locations)."""
        if not opp.city:
            return None
        key = _city_key(opp)
        if key not in self._cities:
            query = ", ".join(p for p in (opp.city, opp.state, opp.country) if p)
            geo = await geocode(self.client, query)
            if geo and geo.get("category") in _CITY_NOMINATIM_CATEGORIES:
                city = CityLocation(
                    key=key,
                    city=opp.city,
                    state=opp.state,
                    country=opp.country,
                    lat=float(geo["lat"]),
                    lng=float(geo["lon"]),
                )
                self.db.add(city)
                self.db.commit()
                self._cities[key] = city
            else:
                self._cities[key] = None
        return self._cities[key]

    async def _match_existing(self, opp: Opportunity) -> Optional[str]:
        candidates = self.by_name.get(normalize_name(opp.institution))
        # Sem cidade não dá para confirmar que é a mesma instituição — cai na
        # geocodificação, que ainda reaproveita o registro se achar o mesmo
        # objeto OSM.
        if not candidates:
            return None
        center = await self.city_location(opp)
        if not center:
            return None
        distances = [
            (_distance_km(lat, lng, center.lat, center.lng), osm_id)
            for osm_id, lat, lng in candidates
        ]
        nearby = [d for d in distances if d[0] <= SAME_CITY_RADIUS_KM]
        return min(nearby)[1] if nearby else None

    async def resolve(self, opp: Opportunity) -> Optional[str]:
        key = (
            normalize_name(opp.institution),
            normalize_name(opp.city),
            normalize_name(opp.country),
        )
        if key in self._resolved:
            return self._resolved[key]

        osm_id = await self._match_existing(opp)
        if not osm_id:
            osm_id = await get_or_create_institution(
                self.db,
                self.client,
                name=opp.institution,
                city=opp.city,
                country=opp.country,
                category=opp.institution_category,
            )
            if osm_id:
                inst = self.db.get(Institution, osm_id)
                entry = (inst.osm_id, inst.lat, inst.lng)
                bucket = self.by_name[normalize_name(inst.name)]
                if entry not in bucket:
                    bucket.append(entry)

        self._resolved[key] = osm_id
        return osm_id


def _visible_on_map(query):
    """Oportunidades que podem aparecer no mapa: presenciais e visíveis no app.

    Não exige enriched_at: registros ainda não processados pelo LLM (ex:
    cota do Gemini esgotada) já aparecem no app, e cidade/organizadora vêm
    do próprio scraper.
    """
    return (
        query
        .filter(or_(Opportunity.is_remote == False, Opportunity.is_remote == None))  # noqa: E712,E711
        .filter(Opportunity.is_active == True)  # noqa: E712
        .filter(Opportunity.llm_confidence >= 0.80)
    )


async def resolve_opportunity_institutions() -> dict:
    """Vincula ao mapa as oportunidades visíveis: pino da instituição e, na
    falta dele, o centro da cidade."""
    db = SessionLocal()
    linked = 0
    unresolved = 0
    by_city = 0
    try:
        pending = (
            _visible_on_map(db.query(Opportunity))
            .filter(Opportunity.institution != None)  # noqa: E711
            .filter(Opportunity.institution != "")
            .filter(Opportunity.institution_id == None)  # noqa: E711
            .all()
        )
        logger.info(f"[Resolver] {len(pending)} oportunidades para vincular a uma instituição")

        async with httpx.AsyncClient() as client:
            resolver = _Resolver(db, client)

            # ── Passada 1: pino da instituição ──────────────────────────────
            for opp in pending:
                try:
                    osm_id = await resolver.resolve(opp)
                except Exception as exc:
                    db.rollback()
                    logger.error(f"[Resolver] Erro em '{opp.institution}': {exc}")
                    osm_id = None

                if osm_id:
                    opp.institution_id = osm_id
                    db.commit()
                    linked += 1
                else:
                    unresolved += 1
                    logger.info(
                        f"[Resolver] Não localizada: '{opp.institution}' "
                        f"({opp.city or '?'}, {opp.country or '?'})"
                    )

            # ── Passada 2: centro da cidade (sem pino de instituição) ───────
            without_pin = (
                _visible_on_map(db.query(Opportunity))
                .filter(Opportunity.institution_id == None)  # noqa: E711
                .filter(Opportunity.city_location_id == None)  # noqa: E711
                .filter(Opportunity.city != None)  # noqa: E711
                .filter(Opportunity.city != "")
                .all()
            )
            for opp in without_pin:
                try:
                    city = await resolver.city_location(opp)
                except Exception as exc:
                    db.rollback()
                    logger.error(f"[Resolver] Erro ao localizar a cidade '{opp.city}': {exc}")
                    city = None
                if city:
                    opp.city_location_id = city.id
                    db.commit()
                    by_city += 1
                else:
                    logger.info(
                        f"[Resolver] Cidade não localizada: '{opp.city}' "
                        f"({opp.state or '?'}, {opp.country or '?'})"
                    )
    finally:
        db.close()

    logger.info(
        f"[Resolver] Concluído: {linked} vinculadas a uma instituição, "
        f"{unresolved} sem instituição localizada, {by_city} vinculadas à cidade"
    )
    return {
        "pending": linked + unresolved,
        "linked": linked,
        "unresolved": unresolved,
        "linked_to_city": by_city,
    }
