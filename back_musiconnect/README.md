# MusicOnnect — Backend

Backend em **Python + FastAPI + PostgreSQL/PostGIS** para descoberta global de instituições musicais.

## Pré-requisitos

- Python 3.11+
- PostgreSQL 15+ com extensão **PostGIS** instalada

## Setup inicial

### 1. Instale o PostGIS no PostgreSQL

Se ainda não tiver o PostGIS, após criar o banco rode:
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
```

### 2. Crie o banco de dados

```sql
CREATE DATABASE musiconnect;
\c musiconnect
CREATE EXTENSION postgis;
```

### 3. Configure o ambiente

```bash
# No diretório back_musiconnect/
cp .env.example .env
# Edite .env com sua string de conexão:
# DATABASE_URL=postgresql://usuario:senha@localhost:5432/musiconnect
```

### 4. Instale as dependências

```bash
python -m venv venv
venv\Scripts\activate        # Windows
pip install -r requirements.txt
```

### 5. Suba o servidor

```bash
uvicorn app.main:app --reload
```

A API estará disponível em: http://localhost:8000  
Documentação automática: http://localhost:8000/docs

---

## Executar o ETL (coleta global)

O ETL busca todas as instituições musicais do OpenStreetMap e salva no banco.

```bash
# Coleta global (~5-10 min, depende da conexão)
python -m scripts.run_etl

# Com mais paralelismo (cuidado para não sobrecarregar o Overpass público)
python -m scripts.run_etl --concurrency 6
```

---

## Endpoints principais

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/institutions/nearby?lat=X&lng=Y&radius_m=Z` | Busca por proximidade (sem depender de zoom) |
| `GET` | `/api/institutions/stats` | Estatísticas do banco |
| `GET` | `/docs` | Documentação interativa (Swagger) |

### Exemplo de chamada

```
GET /api/institutions/nearby?lat=-23.5505&lng=-46.6333&radius_m=50000&limit=200
```

---

## Arquitetura

```
Flutter App
    │
    ▼ HTTP
FastAPI (app/main.py)
    │
    ├── GET /nearby  ──►  PostGIS ST_DWithin  ──►  PostgreSQL
    │                      (índice GIST)
    │
    └── ETL (scripts/run_etl.py)
             │
             ▼ HTTP assíncrono
        Overpass API (OpenStreetMap)
             │
             ▼ upsert por osm_id
        PostgreSQL + PostGIS
```

**Por que não depende de zoom?**  
O Flutter passa apenas `lat/lng/raio`. O banco retorna tudo dentro daquele raio usando o índice espacial — o zoom do mapa não influencia em nada.
