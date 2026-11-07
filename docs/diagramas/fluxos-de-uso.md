# Diagramas de atividade dos fluxos de uso

Complemento da seção [7. Fluxos de uso](../../README.md#7-fluxos-de-uso) do README. Cada diagrama descreve, passo a passo, um fluxo completo do aplicativo, com as decisões do usuário e do sistema.

## 7.1 Fluxo 1: Cadastro e primeiro acesso

```mermaid
flowchart TD
    inicio(("Início")) --> abrir["Abrir o aplicativo"]
    abrir --> temConta{"Possui conta?"}
    temConta -- "Não" --> querConta{"Deseja criar uma conta?"}
    querConta -- "Não" --> visitante["Entrar sem cadastro, aceitando a política de privacidade"]
    visitante --> usarVisitante["Explorar o aplicativo como visitante"]
    usarVisitante --> fim(("Fim"))
    querConta -- "Sim" --> etapa1["Informar instrumentos e ramo de atuação"]
    etapa1 --> etapa2["Informar a localização"]
    etapa2 --> etapa3["Informar nome, e-mail e senha e aceitar a política de privacidade"]
    etapa3 --> envio["Sistema envia o e-mail de confirmação (Resend)"]
    envio --> link["Abrir o link de confirmação recebido por e-mail"]
    link --> confirmado{"E-mail confirmado?"}
    confirmado -- "Não" --> reenviar["Solicitar o reenvio do e-mail"]
    reenviar --> link
    confirmado -- "Sim" --> login["Entrar com e-mail e senha"]
    temConta -- "Sim" --> login
    login --> primeiro{"Primeiro acesso no dispositivo?"}
    primeiro -- "Não" --> home["Visualizar o Início com o melhor match"]
    primeiro -- "Sim" --> tutorial{"Aceita o tutorial?"}
    tutorial -- "Sim" --> percorrer["Percorrer o tutorial guiado"]
    percorrer --> notif{"Deseja receber notificações?"}
    tutorial -- "Não" --> notif
    notif -- "Sim" --> permitir["Permitir as notificações no pedido do Android"]
    permitir --> home
    notif -- "Não" --> home
    home --> fim
```

## 7.2 Fluxo 2: Encontrar e acompanhar uma oportunidade compatível

```mermaid
flowchart TD
    inicio(("Início")) --> matcher["Abrir o Matcher"]
    matcher --> minhas{"Há oportunidades em 'Minhas oportunidades'?"}
    minhas -- "Não" --> todas["Consultar 'Todas as oportunidades'"]
    todas --> filtros["Buscar e aplicar filtros, se desejado"]
    minhas -- "Sim" --> filtros
    filtros --> detalhe["Abrir o detalhe de uma oportunidade"]
    detalhe --> resumo["Ler o resumo do edital gerado pela IA"]
    resumo --> match["Consultar o detalhamento do match na aba Matcher"]
    match --> interessa{"A oportunidade é de interesse?"}
    interessa -- "Não" --> filtros
    interessa -- "Sim" --> favoritar["Favoritar a oportunidade"]
    favoritar --> autorizou{"Notificações autorizadas?"}
    autorizou -- "Sim" --> push["Receber a notificação 'O prazo está acabando'"]
    push --> abrirDetalhe["Abrir o detalhe da oportunidade"]
    autorizou -- "Não" --> ultima["Consultar 'Última chance para seus favoritos no Início'"]
    ultima --> abrirDetalhe
    abrirDetalhe --> saibaMais["Tocar em 'Saiba mais' e abrir o edital original"]
    saibaMais --> inscricao["Realizar a inscrição no site de quem oferece a oportunidade"]
    inscricao --> fim(("Fim"))
```

## 7.3 Fluxo 3: Explorar instituições no mapa

```mermaid
flowchart TD
    inicio(("Início")) --> mapa["Abrir o Mapa"]
    mapa --> como{"Como localizar?"}
    como -- "Busca" --> busca["Buscar uma cidade ou instituição"]
    como -- "Navegação" --> filtros["Aplicar filtros e consultar a legenda"]
    busca --> marcador["Tocar em um marcador"]
    filtros --> marcador
    marcador --> tipo{"Tipo de marcador?"}
    tipo -- "Instituição" --> instituicao["Consultar endereço, site, e-mail e oportunidades abertas"]
    tipo -- "Cidade" --> cidade["Consultar as oportunidades da cidade sem endereço exato"]
    instituicao --> fav{"Deseja favoritar a instituição?"}
    fav -- "Sim" --> conta{"Usuário cadastrado?"}
    conta -- "Sim" --> favoritada["Instituição adicionada aos favoritos"]
    conta -- "Não" --> convite["Receber o convite para criar uma conta"]
    favoritada --> abrir{"Deseja abrir uma oportunidade?"}
    convite --> abrir
    fav -- "Não" --> abrir
    cidade --> abrir
    abrir -- "Sim" --> detalhe["Abrir o detalhe da oportunidade"]
    detalhe --> fim(("Fim"))
    abrir -- "Não" --> fim
```
