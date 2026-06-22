"""
Exporta todas as instituições do PostgreSQL para um JSON compacto
que será bundled como asset no app Flutter.

Uso:
    cd back_musiconnect
    .\\venv\\Scripts\\python.exe scripts\\export_to_json.py

Saída:
    ../front_musiconnect/assets/data/music_institutions.json
"""

import json
import os
import sys
from pathlib import Path

# Adiciona o diretório raiz ao path para importar app.database
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.database import SessionLocal
from sqlalchemy import text

OUTPUT_PATH = Path(__file__).parent.parent.parent / "front_musiconnect" / "assets" / "data" / "music_institutions.json"

def export():
    print("Conectando ao banco de dados...")
    db = SessionLocal()

    try:
        # Busca todas as instituições com nome e coordenadas válidos
        rows = db.execute(text("""
            SELECT
                osm_id   AS id,
                name,
                lat,
                lng,
                category AS c,
                address  AS a
            FROM institutions
            WHERE name IS NOT NULL
              AND lat IS NOT NULL
              AND lng IS NOT NULL
            ORDER BY osm_id
        """)).fetchall()

        print(f"Encontradas {len(rows)} instituições no banco.")

        # Formato compacto: chaves curtas para minimizar tamanho do arquivo
        institutions = [
            {
                "id": row.id,
                "n":  row.name,
                "lat": round(row.lat, 6),
                "lng": round(row.lng, 6),
                "c":  row.c,
                # Endereço é opcional — omite se nulo para economizar espaço
                **({"a": row.a} if row.a else {}),
            }
            for row in rows
        ]

        payload = {
            "version":  "2026-05-30",
            "total":    len(institutions),
            "institutions": institutions,
        }

        OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
            # separators compactos reduzem o tamanho sem comprometer a leitura
            json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

        size_kb = OUTPUT_PATH.stat().st_size / 1024
        print(f"✅ Exportado: {OUTPUT_PATH}")
        print(f"   Tamanho:   {size_kb:.1f} KB")
        print(f"   Total:     {len(institutions)} instituições")

    finally:
        db.close()

if __name__ == "__main__":
    export()
