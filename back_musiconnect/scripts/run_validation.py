"""
Script standalone para validação cruzada com MusicBrainz + Wikidata.

Usa os dados já existentes no banco (coletados pelo ETL OSM) sem re-coletar do OSM.

Uso:
    python -m scripts.run_validation               ← MusicBrainz + Wikidata
    python -m scripts.run_validation --skip-mb     ← só Wikidata
    python -m scripts.run_validation --skip-wd     ← só MusicBrainz
"""

import asyncio
import argparse
import logging
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.musicbrainz_validator import run_musicbrainz_validation
from app.services.wikidata_validator import run_wikidata_validation

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)


def main():
    parser = argparse.ArgumentParser(description="Validação cruzada MusicBrainz + Wikidata")
    parser.add_argument("--skip-mb", action="store_true", help="Pula validação MusicBrainz")
    parser.add_argument("--skip-wd", action="store_true", help="Pula validação Wikidata")
    args = parser.parse_args()

    if not args.skip_mb:
        print("\n[VALIDAÇÃO] Etapa 1/2: MusicBrainz")
        print("Rate-limit: 1 req/seg — pode levar 2-3 horas para 8k registros.\n")
        mb_stats = asyncio.run(run_musicbrainz_validation())
        print(f"\n[VALIDAÇÃO] MusicBrainz: {mb_stats['verified']}/{mb_stats['total']} verificados")
    else:
        print("\n[VALIDAÇÃO] MusicBrainz pulado (--skip-mb)")

    if not args.skip_wd:
        print("\n[VALIDAÇÃO] Etapa 2/2: Wikidata SPARQL")
        wd_stats = asyncio.run(run_wikidata_validation())
        print(f"\n[VALIDAÇÃO] Wikidata: {wd_stats['verified']} verificados")
    else:
        print("\n[VALIDAÇÃO] Wikidata pulado (--skip-wd)")

    print("\n[VALIDAÇÃO] Concluído. Verifique o resultado:")
    print("   SELECT verified, COUNT(*) FROM institutions GROUP BY verified;")


if __name__ == "__main__":
    main()
