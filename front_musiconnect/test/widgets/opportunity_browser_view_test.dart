import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/services/opportunities_service.dart';
import 'package:prototipo_musiconnect/presentation/screens/opportunity_detail_screen.dart';
import 'package:prototipo_musiconnect/presentation/widgets/filter_modal.dart';
import 'package:prototipo_musiconnect/presentation/widgets/opportunity_browser_view.dart';

import '../helpers/fakes.dart';
import '../helpers/screen.dart';

void main() {
  late FakeOpportunitiesService service;

  Future<void> pumpBrowser(
    WidgetTester tester, {
    double matchScaleMin = 0,
    String? lockedType,
    String? lockedTitle,
    VoidCallback? onBack,
  }) async {
    useTallScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OpportunityBrowserView(
          service: service,
          user: fakeUser(instruments: const ['Violino'], country: 'Brasil'),
          matchScaleMin: matchScaleMin,
          emptyCategoriesMessage: 'Nada por aqui.',
          emptySearchMessage: 'Nenhuma oportunidade disponível.',
          lockedType: lockedType,
          lockedTitle: lockedTitle,
          onBack: onBack,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    service = FakeOpportunitiesService()
      ..byType = {
        'audicao': [fakeOpportunity(1, title: 'Audição de violino', matchPercentage: 90)],
        'curso': [
          fakeOpportunity(2, title: 'Curso de verão', type: 'curso', matchPercentage: 40),
          fakeOpportunity(3, title: 'Masterclass', type: 'curso', matchPercentage: 70),
        ],
      }
      ..filterOptions = const FilterOptions(
        instruments: ['Piano', 'Violino'],
        countries: ['Alemanha', 'Brasil'],
        states: [FilterOption(value: 'SC', label: 'SC | Santa Catarina')],
        cities: ['Joinville'],
      );
  });

  group('carrosséis', () {
    testWidgets('um carrossel por tipo com oportunidades', (tester) async {
      await pumpBrowser(tester);

      expect(find.text('Ver todas (2)'), findsOneWidget); // Curso
      expect(find.text('Ver todas (1)'), findsOneWidget); // Audição
      expect(find.text('Emprego'), findsNothing); // tipo sem nada aberto some
    });

    testWidgets('"Ver todas" abre a categoria e voltar fecha', (tester) async {
      await pumpBrowser(tester);

      await tester.tap(find.text('Ver todas (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Busque por cursos...'), findsOneWidget);
      expect(find.text('2 oportunidades encontradas'), findsOneWidget);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Busque por oportunidades...'), findsOneWidget);
    });

    testWidgets('sem nenhuma oportunidade mostra o vazio da aba', (tester) async {
      service.byType = {};
      await pumpBrowser(tester);

      expect(find.text('Nada por aqui.'), findsOneWidget);
    });

    testWidgets('tocar num card abre o detalhe', (tester) async {
      await pumpBrowser(tester);

      await tester.tap(find.text('Audição de violino'));
      await tester.pumpAndSettle();

      expect(find.byType(OpportunityDetailScreen), findsOneWidget);
    });
  });

  group('busca', () {
    testWidgets('enviar a busca mostra a lista e a contagem', (tester) async {
      service.all = [fakeOpportunity(9, title: 'Vaga de violino')];
      await pumpBrowser(tester);

      await tester.enterText(find.byType(TextField), 'violino');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Vaga de violino'), findsOneWidget);
      expect(find.text('1 oportunidades encontradas'), findsOneWidget);
      expect(service.calls.last.q, 'violino');
    });

    testWidgets('sem resultado mostra o termo buscado', (tester) async {
      await pumpBrowser(tester);

      await tester.enterText(find.byType(TextField), 'tuba');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma oportunidade encontrada para\n"tuba"'), findsOneWidget);
    });

    testWidgets('limpar a busca volta aos carrosséis', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'x');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Ver todas (2)'), findsOneWidget);
    });

    testWidgets('erro de rede mostra aviso e tentar de novo', (tester) async {
      await pumpBrowser(tester);
      service.fail = true;
      await tester.enterText(find.byType(TextField), 'x');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível carregar as oportunidades.'), findsOneWidget);

      service.fail = false;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível carregar as oportunidades.'), findsNothing);
    });
  });

  group('modal de filtros', () {
    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Filtrar por'), findsOneWidget);
    }

    Future<void> pick(WidgetTester tester, String hint, String option) async {
      await tester.tap(find.widgetWithText(TextField, hint));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, option));
      await tester.pumpAndSettle();
    }

    testWidgets('escolher tipo, instrumento e lugar vira chips removíveis', (tester) async {
      await pumpBrowser(tester);
      await openFilters(tester);

      await tester.tap(find.text('Curso').last); // chip de tipo dentro do modal
      await pick(tester, 'Filtre instrumentos...', 'Piano');
      await pick(tester, 'Filtre países...', 'Alemanha');
      await pick(tester, 'Filtre estados...', 'SC | Santa Catarina');
      await pick(tester, 'Filtre cidades...', 'Joinville');
      expect(find.text('(1) País • (1) Estado • (1) Cidade'), findsOneWidget);

      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(find.byType(FilterModal), findsNothing);
      expect(find.textContaining('contendo os filtros:'), findsOneWidget);
      expect(find.text('SC | Santa Catarina'), findsOneWidget); // chip com o rótulo
      expect(service.calls.last.types, ['curso']);
      expect(service.calls.last.instruments, ['Piano']);

      // Remove os 5 chips um a um (são os únicos com "×" na tela agora)
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byIcon(Icons.close_rounded).first);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('contendo os filtros:'), findsNothing);
    });

    testWidgets('remover um valor escolhido dentro do modal', (tester) async {
      await pumpBrowser(tester);
      await openFilters(tester);
      await pick(tester, 'Filtre instrumentos...', 'Piano');

      await tester.tap(find.text('Piano'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('"Meu instrumento" e "Perto de Mim" usam o perfil', (tester) async {
      await pumpBrowser(tester);
      await openFilters(tester);

      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Usando seu perfil'), findsNWidgets(2));

      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(service.calls.last.instruments, ['Violino']);
      expect(service.calls.last.countries, ['Brasil']);
    });

    testWidgets('recolher seções e "Limpar tudo"', (tester) async {
      await pumpBrowser(tester);
      await openFilters(tester);
      await pick(tester, 'Filtre países...', 'Brasil');

      await tester.tap(find.text('Instrumento'));
      await tester.tap(find.text('Localização'));
      await tester.pumpAndSettle();
      expect(find.text('Filtre instrumentos...'), findsNothing);

      await tester.tap(find.text('Limpar tudo'));
      await tester.pumpAndSettle();
      expect(find.text('(1) País'), findsNothing);
    });

    testWidgets('estreitar a Escala de Match vira chip e "Limpar filtros"', (tester) async {
      service.all = [];
      await pumpBrowser(tester);
      await openFilters(tester);

      // Arrasta a alça da esquerda para a direita (aumenta o mínimo)
      final slider = tester.getRect(find.byType(RangeSlider));
      await tester.dragFrom(Offset(slider.left + 24, slider.center.dy), const Offset(200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('% match'), findsOneWidget);
      await tester.tap(find.text('Limpar filtros'));
      await tester.pumpAndSettle();
      expect(find.textContaining('% match'), findsNothing);
    });
  });

  testWidgets('página de uma categoria tem voltar próprio', (tester) async {
    var backs = 0;
    await pumpBrowser(tester, lockedType: 'curso', lockedTitle: 'Cursos', onBack: () => backs++);

    expect(find.text('Cursos'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    expect(backs, 1);
  });

  testWidgets('"Minhas oportunidades" (85-100) só mostra matches altos', (tester) async {
    await pumpBrowser(tester, matchScaleMin: 85);

    expect(find.text('Audição de violino'), findsOneWidget); // 90%
    expect(find.text('Curso de verão'), findsNothing); // 40%
  });
}
