<img width="100%" src="../docs/img/faixa-topo.svg" alt="">

# MusiConnect — API (backend)

API REST do MusiConnect, em **Python 3.12 + FastAPI**, com banco **PostgreSQL 16 + PostGIS**. Concentra as regras de negócio (autenticação, oportunidades, cálculo do match, mapa, favoritos e notificações) e o pipeline de dados diário (coleta de editais, interpretação pelo Gemini e atualização das instituições do OpenStreetMap).

A documentação completa do projeto (arquitetura, decisões, testes e deploy) está no [README principal](../README.md). Este arquivo resume apenas o que é específico desta pasta.

## Estrutura

| Pasta / arquivo | Conteúdo |
|---|---|
| `app/main.py` | Criação da aplicação FastAPI, rotas e inicialização do agendador |
| `app/routers/` | Rotas da API: autenticação, oportunidades, instituições, favoritos, notificações, painel inicial, versão do app, links dos e-mails e tarefas administrativas |
| `app/services/` | Regras de negócio e pipeline: match (`matching.py`), coletores (`scrapers/`), interpretação pelo Gemini (`llm_enricher.py`), ETL do OpenStreetMap via QLever (`osm_etl.py`), validação no MusicBrainz e no Wikidata, e-mails (Resend) e notificações (Firebase) |
| `app/scheduler.py` | Rotinas diárias (APScheduler): ETL às 00h, coleta às 06h e notificações às 09h |
| `app/models.py`, `app/schemas.py` | Modelos do banco (SQLAlchemy) e esquemas de entrada e saída (Pydantic) |
| `app/migrations.py` | Ajustes de esquema aplicados na inicialização, além do `create_all` |
| `scripts/` | Scripts de manutenção executados manualmente (tabela abaixo) |
| `tests/` | Testes automatizados (pytest) |

## Execução local

Os passos completos (banco no Docker, variáveis do `.env` e execução da API) estão na seção [20. Execução local](../README.md#20-execução-local) do README principal. Em resumo, com o banco em execução (`docker compose up -d db`, na raiz):

```bash
python -m venv venv
venv\Scripts\activate            # Windows (no Linux/macOS: source venv/bin/activate)
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

A documentação interativa da API (Swagger) fica em `http://localhost:8000/docs`; a de produção, em https://api.musiconnect.app.br/docs.

## Scripts de manutenção

Executados a partir desta pasta (`back_musiconnect/`):

| Comando | O que faz |
|---|---|
| `python -m scripts.run_etl` | Importa as instituições musicais do OpenStreetMap (QLever); com `--validate`, valida em seguida no MusicBrainz e no Wikidata |
| `python -m scripts.run_validation` | Apenas a validação no MusicBrainz e no Wikidata, sobre as instituições já gravadas (`--skip-mb` ou `--skip-wd` para pular uma delas) |

A coleta e a interpretação das oportunidades não têm script próprio: rodam pelo agendador ou pelas rotas administrativas `POST /api/opportunities/scrape` e `POST /api/opportunities/enrich` (com a chave `X-Admin-Key`).

## Testes

```bash
pytest                 # exige o banco do Docker em execução (usa o banco musiconnect_test)
pytest --cov=app       # com relatório de cobertura
```

Os tipos de teste e a cobertura estão na seção [15.2 Testes](../README.md#152-testes) do README principal.

## Deploy

A API roda em contêiner Docker no servidor de produção e é atualizada automaticamente a cada envio para a `main`. Ver a seção [19.3 Deploy do servidor](../README.md#193-deploy-do-servidor).

<img width="100%" src="../docs/img/faixa-rodape.svg" alt="">