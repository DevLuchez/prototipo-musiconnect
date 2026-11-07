# Pipeline de dados do MusiConnect

Complemento da seção [9.4 Pipeline de dados e fontes](../../README.md#94-pipeline-de-dados-e-fontes) do README. O diagrama detalha as três rotinas diárias executadas pelo agendador da API e o caminho dos dados até o aplicativo.

```mermaid
flowchart TB
    subgraph etl["00h — Atualização do mapa"]
        qlever["Consulta as instituições musicais<br/>do OpenStreetMap (QLever)"]
        upsert["Insere ou atualiza cada instituição<br/>pelo identificador do OSM"]
        validar["Valida e complementa os dados<br/>(MusicBrainz e Wikidata)"]
        qlever --> upsert --> validar
    end

    subgraph coleta["06h — Coleta de oportunidades"]
        scrapers["Coleta os editais das fontes<br/>(Musical Chairs, WFIMC, CONCERTO,<br/>SCAR e FEMUSC)"]
        retirados["Desativa os editais retirados da fonte"]
        gemini["Interpreta os editais novos ou alterados<br/>com o Gemini: tipo, instrumentos, local,<br/>prazo, resumo em português e confiança"]
        resolver["Vincula cada oportunidade à instituição no mapa;<br/>se ela ainda não existir, localiza-a no OSM<br/>(Nominatim) e cria o marcador; se não for<br/>encontrada, associa ao centro da cidade"]
        limpeza["Remove dos favoritos as oportunidades<br/>que deixaram de estar disponíveis"]
        scrapers --> retirados --> gemini --> resolver --> limpeza
    end

    subgraph notif["09h — Notificações"]
        selecionar["Seleciona, para cada usuário, as novas<br/>oportunidades com match ≥ 85%, as<br/>favoritas com prazo próximo e a<br/>disponibilidade de nova versão"]
        enviar["Envia pelo Firebase Cloud Messaging<br/>e registra o envio"]
        selecionar --> enviar
    end

    db[("PostgreSQL + PostGIS")]
    app["Aplicativo"]

    validar --> db
    limpeza --> db
    db --> selecionar
    db -- "API REST: apenas oportunidades abertas<br/>com confiança ≥ 80%" --> app
    enviar -. "Notificação" .-> app
```
