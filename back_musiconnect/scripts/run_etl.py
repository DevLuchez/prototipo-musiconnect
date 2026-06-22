"""
Script para executar o ETL manualmente.

Uso:
    python -m scripts.run_etl
    python -m scripts.run_etl --concurrency 6
"""

import asyncio
import logging
import argparse
import sys
import os

# Garante que o diretório raiz está no path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.overpass_etl import run_etl

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)


def main():
    parser = argparse.ArgumentParser(description="ETL: coleta instituições musicais do OSM")
    parser.add_argument(
        "--concurrency",
        type=int,
        default=4,
        help="Células processadas em paralelo (padrão: 4)",
    )
    args = parser.parse_args()

    print(f"\n[ETL] MusicOnnect ETL — concorrência: {args.concurrency}")
    print("Isso pode levar alguns minutos para cobertura global completa...\n")

    stats = asyncio.run(run_etl(concurrency=args.concurrency))

    print(f"\n[ETL] Concluído!")
    print(f"   Células processadas: {stats['cells_processed']}")
    print(f"   Registros no banco:  {stats['records_upserted']}")


if __name__ == "__main__":
    main()
