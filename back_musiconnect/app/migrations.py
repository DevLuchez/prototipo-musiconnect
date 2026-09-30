"""
Migrações idempotentes rodadas no startup, logo após `create_all`.

`Base.metadata.create_all` só cria tabelas que ainda não existem — não
adiciona colunas novas em tabelas já existentes. Cada comando aqui precisa
poder rodar em todo startup sem efeito colateral (IF NOT EXISTS / UPDATE
que não casa mais nada na segunda vez).
"""

import logging

from sqlalchemy import text
from sqlalchemy.engine import Engine

logger = logging.getLogger("migrations")

_STATEMENTS = [
    # ── Vínculo oportunidade ↔ instituição ───────────────────────────────
    """
    ALTER TABLE opportunities
        ADD COLUMN IF NOT EXISTS institution_id VARCHAR
        REFERENCES institutions(osm_id) ON DELETE SET NULL
    """,
    """
    CREATE INDEX IF NOT EXISTS ix_opportunities_institution_id
        ON opportunities (institution_id)
    """,
    """
    ALTER TABLE opportunities
        ADD COLUMN IF NOT EXISTS institution_category VARCHAR(50)
    """,
    # ── Oportunidades por cidade (tabela city_locations vem do create_all) ─
    """
    ALTER TABLE opportunities
        ADD COLUMN IF NOT EXISTS city_location_id INTEGER
        REFERENCES city_locations(id) ON DELETE SET NULL
    """,
    """
    CREATE INDEX IF NOT EXISTS ix_opportunities_city_location_id
        ON opportunities (city_location_id)
    """,
    # ── Busca do mapa sem diferenciar acentos ("joacaba" → "Joaçaba") ─────
    "CREATE EXTENSION IF NOT EXISTS unaccent",
    # ── Contato vindo das tags do OSM ─────────────────────────────────────
    "ALTER TABLE institutions ADD COLUMN IF NOT EXISTS email VARCHAR",
    # Descrição curta do Wikidata removida: ~97% só repetia tipo + cidade
    # ("theatre in Melbourne, Australia"), em inglês, sem uso no app.
    "ALTER TABLE institutions DROP COLUMN IF EXISTS description",
    # ── Dados antigos do fluxo "adicionar ao mapa" (removido) ────────────
    # source='musiconnect' virou 'pipeline'; category='music' não existe
    # entre os filtros do mapa e fazia o pino sumir ao filtrar.
    "UPDATE institutions SET source = 'pipeline' WHERE source = 'musiconnect'",
    "UPDATE institutions SET category = 'music_org' WHERE source = 'pipeline' AND category = 'music'",
    "ALTER TABLE institutions ALTER COLUMN category DROP DEFAULT",
]


def run_migrations(engine: Engine) -> None:
    with engine.begin() as conn:
        for stmt in _STATEMENTS:
            conn.execute(text(stmt))
    logger.info("Migrações verificadas/aplicadas.")
