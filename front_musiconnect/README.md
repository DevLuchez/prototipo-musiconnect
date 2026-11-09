<img width="100%" src="../docs/img/faixa-topo.svg" alt="">

# MusiConnect — Aplicativo (Flutter)

Aplicativo Android do MusiConnect, em **Flutter 3.24.4** com a arquitetura **MVVM**. Consome a API REST do backend (`../back_musiconnect`) e usa o Firebase (notificações, métricas de uso e falhas) e o Google Maps.

A documentação completa do projeto (funcionalidades, telas, arquitetura, testes e instalação) está no [README principal](../README.md). Este arquivo resume apenas o que é específico desta pasta.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `lib/presentation/screens/` | Telas (View): Início, Mapa, Matcher, Perfil, detalhe da oportunidade, favoritos, ajuda, política de privacidade, autenticação e cadastro |
| `lib/presentation/view_models/` | ViewModels, com o estado de cada tela principal |
| `lib/presentation/widgets/` e `tutorial/` | Componentes reutilizáveis e o tutorial guiado do primeiro acesso |
| `lib/data/models/` e `lib/data/services/` | Modelos de dados e serviços de acesso à API |
| `lib/core/` | Configuração, constantes, modo visitante, notificações, links externos e monitoramento |
| `test/` | Testes de unidade e de *widget* |
| `integration_test/` | Testes instrumentados, executados em aparelho ou emulador |

A descrição de cada camada está na seção [9.2 Arquitetura do aplicativo (MVVM)](../README.md#92-arquitetura-do-aplicativo-mvvm) do README principal.

## Execução local

Os pré-requisitos (Flutter, JDK 17, Android SDK) e a configuração do Firebase estão na seção [20. Execução local](../README.md#20-execução-local) do README principal. Em resumo:

```bash
flutter pub get
flutter run                                              # usa a API de produção
flutter run --dart-define=API_URL=http://<IP>:8000       # usa uma API local
```

O arquivo `android/app/google-services.json` (Firebase) e a chave de assinatura (`android/key.properties`) não são versionados.

## Testes

```bash
flutter analyze
flutter test                                       # unidade e widget
flutter test --coverage                            # com relatório de cobertura
flutter test integration_test -d <id-do-aparelho>  # instrumentados
```

## Publicação

Cada nova versão é publicada a partir de uma *tag* no repositório, que gera o APK assinado automaticamente. Ver a seção [19.2 Publicação de uma nova versão do aplicativo](../README.md#192-publicação-de-uma-nova-versão-do-aplicativo) do README principal.

<img width="100%" src="../docs/img/faixa-rodape.svg" alt="">