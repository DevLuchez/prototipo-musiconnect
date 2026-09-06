"""
Backfill de institution/deadline/description para oportunidades do Musical
Chairs já gravadas no banco antes de o scraper passar a visitar a página
individual de cada anúncio (ver `_enrich_with_details` em
musical_chairs_scraper.py).

Revisita a página de cada oportunidade e corrige institution/deadline/
description/raw_text com os dados estruturados do site — inclusive
sobrescrevendo uma instituição errada já salva (ex.: nome de sala/endereço
que uma extração antiga do LLM confundiu com a organização responsável).
Instituição só é sobrescrita quando a página realmente tem esse campo
(vagas/empregos); competições e cursos não têm instituição estruturada no
site e são deixados como estão.

Quando a página não existe mais (404 — vaga preenchida, competição/curso
encerrado e removido pela fonte), a oportunidade é EXCLUÍDA do banco. Não
faz sentido só desativar: o pipeline diário nunca revisita a página de
detalhe de um source_url que já existe no banco (só de URLs novas), então
se o anúncio voltar ao ar mais tarde, marcá-lo como inativo o deixaria
escondido para sempre — excluindo, se o link reaparecer no RSS dentro da
janela recente, o scraper o trata como novo de novo e refaz a busca certa.

Uso:
    python -m scripts.backfill_opportunity_details               ← aplica e salva
    python -m scripts.backfill_opportunity_details --dry-run      ← só mostra o que mudaria
    python -m scripts.backfill_opportunity_details --reenrich     ← também marca as
                                                                     corrigidas para
                                                                     reprocessar no Gemini
                                                                     (título/tipo/instrumentos/
                                                                     país/estado/cidade), já
                                                                     que agora têm um raw_text
                                                                     melhor. Rode depois:
                                                                     POST /api/opportunities/enrich
"""

import argparse
import asyncio
import logging
import os
import sys

import httpx

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import SessionLocal
from app.models import Opportunity
from app.services.scrapers.musical_chairs_scraper import (
    _DETAIL_CONCURRENCY,
    _fetch_detail,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("scripts.backfill_opportunity_details")


async def backfill(dry_run: bool = False, reenrich: bool = False) -> None:
    db = SessionLocal()
    try:
        opps = (
            db.query(Opportunity)
            .filter(Opportunity.source_name == "Musical Chairs")
            .filter(Opportunity.source_url.isnot(None))
            .all()
        )
        logger.info(f"{len(opps)} oportunidades do Musical Chairs para revisitar.")

        sem = asyncio.Semaphore(_DETAIL_CONCURRENCY)
        async with httpx.AsyncClient(
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (compatible; MusiConnectBot/1.0; "
                    "+https://musiconnect.app)"
                )
            }
        ) as client:
            details = await asyncio.gather(
                *(_fetch_detail(client, opp.source_url, sem) for opp in opps)
            )

        updated = 0
        removed = 0
        for opp, detail in zip(opps, details):
            if not detail:
                continue

            if detail.get("not_found"):
                logger.info(f"[{opp.id}] fonte removeu o anúncio (404) — excluindo")
                db.delete(opp)
                removed += 1
                continue

            changed = False

            if detail.get("institution") and detail["institution"] != opp.institution:
                logger.info(
                    f"[{opp.id}] institution: {opp.institution!r} -> {detail['institution']!r}"
                )
                opp.institution = detail["institution"]
                changed = True

            if detail.get("deadline") and detail["deadline"] != opp.deadline:
                logger.info(f"[{opp.id}] deadline: {opp.deadline!r} -> {detail['deadline']!r}")
                opp.deadline = detail["deadline"]
                changed = True

            # Só mexe em description/raw_text se ainda não foi enriquecido —
            # depois do enrichment, description já está traduzida/limpa pelo
            # LLM, e sobrescrever aqui reverteria isso para o texto bruto.
            full_desc = detail.get("description")
            if opp.enriched_at is None and full_desc and full_desc != opp.description:
                opp.description = full_desc
                opp.raw_text = (
                    f"Título: {opp.title}\n\n"
                    f"Local: {detail.get('location_raw') or 'não informado'}\n\n"
                    f"Descrição:\n{full_desc}"
                )
                changed = True

            if changed:
                updated += 1
                if reenrich:
                    opp.enriched_at = None

        logger.info(f"{updated}/{len(opps)} oportunidades com dados corrigidos.")
        logger.info(f"{removed}/{len(opps)} excluídas (fonte removeu o anúncio).")

        if dry_run:
            db.rollback()
            logger.info("--dry-run: nada foi salvo.")
        else:
            db.commit()
            logger.info("Alterações salvas.")
            if reenrich and updated:
                logger.info(
                    "Dispare o reenriquecimento com: "
                    "POST /api/opportunities/enrich (ou aguarde o job diário)."
                )
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Backfill de institution/deadline/description via página de detalhe do Musical Chairs"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Mostra o que mudaria sem salvar no banco"
    )
    parser.add_argument(
        "--reenrich",
        action="store_true",
        help="Reseta enriched_at das oportunidades corrigidas para reprocessar no Gemini",
    )
    args = parser.parse_args()
    asyncio.run(backfill(dry_run=args.dry_run, reenrich=args.reenrich))
