# Exemplo de uso da API do MusiConnect

Complemento da seção [12. Documentação da API](../README.md#12-documentação-da-api) do README. A documentação completa e interativa está em [api.musiconnect.app.br/docs](https://api.musiconnect.app.br/docs).

Listagem de audições abertas para violino, com o percentual de match do usuário autenticado:

```http
GET /api/opportunities/?type=audicao&instrument=Violino&limit=1
Authorization: Bearer <token>
```

```json
[
  {
    "id": 1234,
    "title": "Audição para Violino Tutti na Orquestra Sinfônica",
    "type": "audicao",
    "instruments": ["Violino"],
    "deadline": "2026-12-15",
    "city": "São Paulo",
    "country": "Brasil",
    "is_remote": false,
    "description": "Resumo do edital em português, gerado pela IA.",
    "source_url": "https://...",
    "llm_confidence": 0.95,
    "match_percentage": 94,
    "match_breakdown": {
      "instrument": 45, "affinity": 20, "location": 15, "confidence": 14,
      "instrument_max": 45, "affinity_max": 20, "location_max": 20, "confidence_max": 15
    }
  }
]
```

*Exemplo ilustrativo; alguns campos foram omitidos. O total de resultados da consulta é retornado no cabeçalho `X-Total-Count`.*
