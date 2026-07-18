<div align="center">

# 🎵 MusiConnect

### Sistema Inteligente de Dados para Gestão de Oportunidades Musicais

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL+PostGIS-16-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://postgis.net)
[![Python](https://img.shields.io/badge/Python-3.12+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)

**Portfólio de TCC · Engenharia de Software · Centro Universitário Católica de Santa Catarina**

*Laura Heloísa Luchez · PAC VII – 2026/1*

</div>

---

## Sobre o Projeto | Portifólio

O **MusiConnect** é um aplicativo mobile com **Inteligência Artificial** projetado para mitigar a carga cognitiva e a evasão de estudantes de música em seus processos de profissionalização. O projeto foi desenvolvido como parte das atividades acadêmicas do PAC (Projeto de Aprendizagem Colaborativa) do curso de Engenharia de Software.

### Problema

A fragmentação de informações sobre processos seletivos e oportunidades musicais — editais, audições, vagas internacionais — constitui uma barreira significativa à profissionalização de músicos, especialmente no contexto de instituições como a **Sociedade Cultura Artística de Jaraguá do Sul (SCAR)**. O processo manual de busca consome tempo, exige domínio de idiomas e conhecimento de portais especializados dispersos na web.

### Solução

O MusiConnect propõe uma plataforma **intuitiva e preditiva** que combina três frentes tecnológicas:

| Frente | Tecnologia | Descrição |
|--------|-----------|-----------|
| **Acessibilidade Cognitiva via RAG** | LLM + Vector DB | Interpretação automática de editais complexos com extração de datas, requisitos e prazos |
| **Recomendação Personalizada** | Machine Learning (Clustering + Matching) | Alinhamento do perfil técnico do músico às exigências das oportunidades |
| **Mapa Interativo de Conexões** | Google Maps + OpenStreetMap | Hub visual global de instituições musicais em tempo real |

---

## Arquitetura

O protótipo segue **Clean Architecture** no frontend e separação clara de camadas no backend:

```
prototipo_musiconnect/
├── front_musiconnect/          # Aplicativo Flutter (Mobile)
│   └── lib/
│       ├── core/               # Utilitários e configurações globais
│       ├── data/               # Modelos e fontes de dados
│       │   └── models/
│       │       ├── place_model.dart
│       │       └── providers/  # API Service (MusiConnect API)
│       ├── domain/             # Regras de negócio (casos de uso)
│       └── presentation/       # UI (Screens + Widgets)
│           └── screens/
│               ├── map_explorer_screen.dart   # Mapa global de instituições
│               ├── future_events.dart          # Radar de oportunidades (roadmap)
│               └── portfolio_screen.dart       # Perfil do músico (roadmap)
│
└── back_musiconnect/           # API REST Python (FastAPI)
    └── app/
        ├── main.py             # Entry point da API
        ├── models.py           # Modelos SQLAlchemy + PostGIS
        ├── schemas.py          # Schemas Pydantic
        ├── database.py         # Configuração do banco
        ├── routers/
        │   └── institutions.py # Endpoints de instituições
        └── services/
            └── overpass_etl.py # Pipeline ETL global (OSM → PostgreSQL)
```

### Diagrama de Fluxo de Dados

```
OpenStreetMap (Overpass API)
         │
         ▼
   [ETL Python]          ← Coleta global em grade 30°×45°
   overpass_etl.py       ← Upsert por osm_id (sem duplicatas)
         │
         ▼
PostgreSQL + PostGIS      ← Índice GIST espacial (ST_DWithin)
         │
         ▼
   FastAPI REST API       ← /institutions/nearby?lat&lng&radius
         │
         ▼
  Flutter (Mobile)        ← Google Maps com marcadores por categoria
```

---

## Funcionalidades Implementadas

### Mapa Explorador de Instituições
- Visualização em mapa de **instituições musicais globais** com marcadores coloridos por categoria
- Busca dinâmica por raio conforme o usuário navega pelo mapa (debounce de 800ms)
- Categorias suportadas: Escola de Música, Casa de Shows, Teatro/Ópera, Nightclub, Local ao Vivo, Loja de Instrumentos
- Painel de detalhes ao clicar em cada instituição (nome, categoria, endereço)
- Legenda interativa com contadores em tempo real
- Tratamento gracioso de backend offline com banner de aviso

### Pipeline ETL Global (Backend)
- Coleta automática de dados do **OpenStreetMap** via Overpass API
- Processamento paralelo com semáforo (4 células simultâneas)
- Grade global de ~24 células (30°×45°) para cobertura total do planeta
- **Upsert idempotente** por `osm_id` — execuções repetidas nunca duplicam dados
- Backoff automático com retry em caso de rate-limiting (429) ou timeout

### API REST
- Endpoint de busca geoespacial por raio (`ST_DWithin` via PostGIS)
- Retorno tipado com Pydantic schemas
- CORS configurado para desenvolvimento mobile
- Health check integrado

---

## Funcionalidades Futuras

- [ ] **Sistema de Recomendação** — Clustering + Matching por perfil técnico do músico
- [ ] **Ingestão Autônoma de Editais** — Web Scraping + RAG (LLM + pgvector)
- [ ] **Perfil do Músico** — Cadastro de repertório, nível técnico e histórico
- [ ] **Radar de Oportunidades** — Notificações de editais e audições alinhados ao perfil
- [ ] **Integração com SCAR** — Conexão direta com os sistemas da instituição parceira
- [ ] **Publicação na Play Store** — APK instalável ou distribuição via Google Play

---

## Stack Tecnológica

### Frontend — Flutter
| Dependência | Versão | Uso |
|-------------|--------|-----|
| `flutter` | SDK ^3.x | Framework mobile multiplataforma |
| `google_maps_flutter` | ^2.5.0 | Mapa interativo |
| `http` | ^1.1.0 | Requisições à API REST |
| `cupertino_icons` | ^1.0.8 | Iconografia iOS |

### Backend — Python / FastAPI
| Dependência | Versão | Uso |
|-------------|--------|-----|
| `fastapi` | >=0.115.0 | Framework REST assíncrono |
| `uvicorn` | >=0.30.0 | Servidor ASGI |
| `sqlalchemy` | >=2.0.36 | ORM |
| `geoalchemy2` | >=0.15.2 | Tipos e funções PostGIS |
| `psycopg` | >=3.2.0 | Driver PostgreSQL (async) |
| `alembic` | >=1.14.0 | Migrações de banco |
| `httpx` | >=0.27.0 | HTTP assíncrono (ETL) |
| `pydantic-settings` | >=2.3.0 | Configuração por variáveis de ambiente |

### Infraestrutura
- **Banco de dados:** PostgreSQL 16 + extensão PostGIS
- **Dados geoespaciais:** OpenStreetMap via Overpass API
- **Versionamento:** GitHub (Clean Architecture + commits frequentes)
- **Monitoramento:** Firebase Analytics (roadmap)
- **Qualidade de código:** SonarQube / SonarCloud (roadmap)
- **Testes:** TDD — cobertura alvo 75% backend, 25% frontend (roadmap)

---

## Autora

**Laura Heloísa Luchez**
Estudante de Engenharia de Software · Centro Universitário Católica de Santa Catarina

[![Email](https://img.shields.io/badge/Email-laura.luchez@catolicasc.edu.br-D14836?style=flat&logo=gmail&logoColor=white)](mailto:laura.luchez@catolicasc.edu.br)
