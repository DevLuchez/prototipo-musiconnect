"""
Script para executar o ETL e (opcionalmente) a validação cruzada.

Uso:
    python -m scripts.run_etl                   ← só OSM
    python -m scripts.run_etl --validate        ← OSM + MusicBrainz + Wikidata
    python -m scripts.run_etl --concurrency 6   ← OSM com mais paralelismo
"""

import asyncio
import logging
import argparse
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.overpass_etl import run_etl
from app.services.musicbrainz_validator import run_musicbrainz_validation
from app.services.wikidata_validator import run_wikidata_validation

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)


def main():
    parser = argparse.ArgumentParser(description="ETL MusicConnect: OSM + validação")
    parser.add_argument(
        "--concurrency",
        type=int,
        default=4,
        help="Células OSM processadas em paralelo (padrão: 4)",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Roda validação MusicBrainz + Wikidata após o ETL do OSM",
    )
    args = parser.parse_args()

    # ── Etapa 1: OSM ──────────────────────────────────────────────────────────
    print(f"\n[ETL] MusicConnect — Etapa 1/3: OpenStreetMap (concorrência: {args.concurrency})")
    print("Isso pode levar alguns minutos para cobertura global completa...\n")

    stats = asyncio.run(run_etl(concurrency=args.concurrency))

    print(f"\n[ETL] OSM concluído!")
    print(f"   Células processadas: {stats['cells_processed']}")
    print(f"   Registros no banco:  {stats['records_upserted']}")

    if not args.validate:
        print("\nDica: use --validate para cruzar com MusicBrainz e Wikidata.")
        return

    # ── Etapa 2: MusicBrainz ──────────────────────────────────────────────────
    print("\n[VALIDAÇÃO] Etapa 2/3: MusicBrainz")
    print("Rate-limit: 1 req/seg — pode levar 2-3 horas para o banco completo.\n")

    mb_stats = asyncio.run(run_musicbrainz_validation())
    print(f"\n[VALIDAÇÃO] MusicBrainz: {mb_stats['verified']}/{mb_stats['total']} verificados")

    # ── Etapa 3: Wikidata ─────────────────────────────────────────────────────
    print("\n[VALIDAÇÃO] Etapa 3/3: Wikidata SPARQL")

    wd_stats = asyncio.run(run_wikidata_validation())
    print(f"\n[VALIDAÇÃO] Wikidata: {wd_stats['verified']} verificados")

    print("\n[ETL] Pipeline completo! Consulte o banco para ver o resultado:")
    print("   SELECT verified, COUNT(*) FROM institutions GROUP BY verified;")


if __name__ == "__main__":
    main()
