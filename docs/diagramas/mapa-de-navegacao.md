# Mapa de navegação do MusiConnect

Complemento da seção [8.2 Mapa de navegação](../../README.md#8-estrutura-de-navegação) do README. O diagrama mostra todas as telas do aplicativo e como se chega a cada uma; os rótulos das setas indicam o elemento tocado.

```mermaid
flowchart LR
    subgraph acesso["Acesso"]
        boas["Boas-vindas"]
        cadastro["Cadastro<br/>(4 etapas)"]
        login["Login"]
        esqueci["Esqueci minha senha"]
        redefinir["Redefinir senha"]
    end

    subgraph abas["Barra de navegação inferior"]
        inicio["Início"]
        mapa["Mapa"]
        matcher["Matcher<br/>(Minhas / Todas)"]
        perfil["Perfil"]
    end

    subgraph menu["Menu lateral"]
        favOp["Oportunidades<br/>favoritas"]
        favInst["Instituições<br/>favoritas"]
        politica["Política de<br/>privacidade"]
        ajuda["Ajuda e suporte"]
    end

    subgraph detalhes["Telas de detalhe"]
        lista["Lista por tipo"]
        detalhe["Detalhe da oportunidade<br/>(Sobre o Edital / Matcher)"]
        instituicao["Painel da instituição"]
        cidade["Painel da cidade"]
        editar["Editar perfil"]
        trocar["Trocar senha"]
        tutorial["Tutorial guiado"]
    end

    subgraph externos["Fora do aplicativo"]
        email["E-mail"]
        navegador["Navegador<br/>(edital original, site)"]
        notificacao["Notificação"]
    end

    boas --> cadastro
    boas --> login
    boas -- "Entrar sem conta" --> abas
    cadastro -- "Confirmação" --> email
    email -- "Link de confirmação" --> login
    login --> esqueci
    esqueci -- "Link de redefinição" --> email
    email -- "Link de redefinição" --> redefinir
    redefinir --> login
    login --> abas

    inicio -- "Melhor match" --> detalhe
    inicio -- "Explorar" --> lista
    inicio -- "Dúvidas?" --> ajuda
    matcher -- "Ver todas" --> lista
    matcher --> detalhe
    lista --> detalhe
    mapa --> instituicao
    mapa --> cidade
    instituicao --> detalhe
    cidade --> detalhe
    detalhe -- "Ver no mapa" --> mapa
    detalhe -- "Saiba mais" --> navegador
    instituicao -- "Saiba mais" --> navegador
    perfil --> editar
    perfil --> trocar
    trocar -- "Esqueci minha senha" --> esqueci
    perfil -- "Sair / Excluir conta" --> boas

    abas -- "☰" --> menu
    favOp --> detalhe
    favInst --> instituicao
    ajuda --> tutorial
    ajuda -- "Fale conosco" --> email

    notificacao -- "Prazo acabando" --> detalhe
    notificacao -- "Novas oportunidades" --> matcher
    notificacao -- "Nova versão<br/>(janela de atualização)" --> navegador
```

No modo visitante, a navegação é a mesma, com três diferenças: a aba Perfil exibe um convite para criar conta ou entrar; as listas de favoritos e a aba "Minhas oportunidades" exibem o mesmo convite; e as ações que dependem de conta, como favoritar, abrem uma janela que encaminha ao cadastro ou ao login.
