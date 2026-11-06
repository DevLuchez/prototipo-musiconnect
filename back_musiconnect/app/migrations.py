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
    # ── Data de entrada da oportunidade ("Novas para você" do Início) ─────
    # Coluna criada SEM default pra não marcar as antigas como "agora";
    # as existentes recebem a melhor estimativa disponível (enriched_at,
    # senão scraped_at) e só então o default vale para as novas.
    "ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS created_at TIMESTAMP",
    """
    UPDATE opportunities
       SET created_at = COALESCE(enriched_at, scraped_at)
     WHERE created_at IS NULL
    """,
    "ALTER TABLE opportunities ALTER COLUMN created_at SET DEFAULT now()",
    # ── Consentimento com a Política de privacidade (LGPD) ────────────────
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_accepted_at TIMESTAMP",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_policy_version VARCHAR(20)",
    # ── Notificações (chaves do Perfil, ligadas por padrão) ───────────────
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS notify_new_matches BOOLEAN NOT NULL DEFAULT TRUE",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS notify_deadlines BOOLEAN NOT NULL DEFAULT TRUE",
    # ── Aviso de versão nova do app (06/11/2026) ──────────────────────────
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS notify_app_updates BOOLEAN NOT NULL DEFAULT TRUE",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS app_update_notified VARCHAR(20)",
    "ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS app_version VARCHAR(20)",
    # ── Participação ativa (02/11/2026) ───────────────────────────────────
    # O Gemini passou a responder se a pessoa participa fazendo música (só
    # vale para quem não informa instrumento) e a listar os instrumentos de
    # formações (quarteto de cordas...). Volta para o Gemini só o que pode
    # mudar com isso: as visíveis sem instrumento, enriquecidas antes da
    # mudança — depois de refeitas, não casam mais (roda em todo startup sem
    # efeito).
    """
    UPDATE opportunities
       SET enriched_at = NULL
     WHERE is_active
       AND enriched_at < '2026-11-02 21:00:00'
       AND (instruments IS NULL OR cardinality(instruments) = 0)
    """,
]


def run_migrations(engine: Engine) -> None:
    with engine.begin() as conn:
        for stmt in _STATEMENTS:
            conn.execute(text(stmt))
    logger.info("Migrações verificadas/aplicadas.")
