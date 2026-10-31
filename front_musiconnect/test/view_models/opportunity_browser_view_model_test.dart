import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/presentation/view_models/opportunity_browser_view_model.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeOpportunitiesService service;
  late List<String> events;

  OpportunityBrowserViewModel build({
    double min = 0,
    double max = 100,
    String? lockedType,
    String? lockedTitle,
  }) =>
      OpportunityBrowserViewModel(
        service: service,
        matchScaleMin: min,
        matchScaleMax: max,
        lockedType: lockedType,
        lockedTitle: lockedTitle,
        logEvent: events.add,
      );

  setUp(() {
    service = FakeOpportunitiesService();
    events = [];
  });

  group('carrosséis por categoria', () {
    test('um carrossel por tipo com oportunidades; tipos vazios somem', () async {
      service.byType = {
        'audicao': [fakeOpportunity(1), fakeOpportunity(2)],
        'curso': [fakeOpportunity(3, type: 'curso')],
      };
      final vm = build();

      await vm.start();

      expect(vm.categoriesLoading, isFalse);
      // Na ordem definida em kOpportunityTypeLabels (emprego, curso, ...).
      expect(vm.categories.map((c) => c.typeKey), ['curso', 'audicao']);
      expect(vm.categories.last.total, 2);
      expect(vm.searchMode, isFalse);
    });

    test('cada prévia pede só 10 por tipo', () async {
      await build().start();
      expect(service.calls.every((c) => c.limit == 10), isTrue);
    });
  });

  group('Escala de Match', () {
    test('"Minhas oportunidades" (85-100) filtra mesmo sem mexer no slider', () async {
      service.byType = {
        'audicao': [
          fakeOpportunity(1, matchPercentage: 90),
          fakeOpportunity(2, matchPercentage: 50),
          fakeOpportunity(3, matchPercentage: 99),
        ],
      };
      final vm = build(min: 85);

      await vm.start();

      final audicoes = vm.categories.single;
      expect(audicoes.items.map((o) => o.id), [3, 1]); // maior match primeiro
      expect(audicoes.total, 2);
      expect(service.calls.first.limit, 500); // lote maior antes de cortar
      expect(vm.matchScaleActive, isFalse); // é o repouso da aba, não um filtro
    });

    test('estreitar a escala conta como filtro e vira chip removível', () async {
      service.all = [fakeOpportunity(1, matchPercentage: 40), fakeOpportunity(2, matchPercentage: 80)];
      final vm = build();
      _apply(vm, matchStart: 70);
      await _settle();

      expect(vm.matchScaleActive, isTrue);
      expect(vm.activeFiltersCount, 1);
      expect(vm.opportunities.map((o) => o.id), [2]);

      vm.resetMatchScale();
      await _settle();
      expect(vm.matchScaleActive, isFalse);
      expect(vm.opportunities.length, 2);
    });
  });

  group('busca e filtros', () {
    test('buscar entra no modo lista e manda o texto', () async {
      service.all = [fakeOpportunity(1)];
      final vm = build();

      vm.search('violino');
      await _settle();

      expect(vm.searchMode, isTrue);
      expect(service.calls.last.q, 'violino');
      expect(vm.opportunities.length, 1);
    });

    test('digitar sem enviar não busca nem troca de modo', () {
      final vm = build();
      vm.query = 'vio';
      // A troca de modo só acontece quando a tela redesenha (ao enviar).
      expect(service.calls, isEmpty);
    });

    test('aplicar filtros registra o evento e conta cada valor', () async {
      final vm = build();

      _apply(vm, types: ['audicao', 'curso'], instruments: ['Piano']);
      await _settle();

      expect(vm.activeFiltersCount, 3);
      expect(service.calls.last.types, ['audicao', 'curso']);
      expect(service.calls.last.instruments, ['Piano']);
      expect(events, ['apply_filter']);
    });

    test('remover um chip tira só aquele valor', () async {
      final vm = build();
      _apply(vm, types: ['audicao', 'curso'], instruments: ['Piano'],
          countries: ['Brasil'], states: ['SC'], cities: ['Joinville']);
      await _settle();

      vm.removeType('curso');
      vm.removeInstrument('Piano');
      vm.removeCountry('Brasil');
      vm.removeState('SC');
      vm.removeCity('Joinville');
      await _settle();

      expect(vm.activeTypes, ['audicao']);
      expect(vm.activeFiltersCount, 1);
    });

    test('limpar filtros zera tudo', () async {
      final vm = build();
      _apply(vm, types: ['audicao'], matchStart: 50);
      await _settle();

      vm.clearFilters();
      await _settle();

      expect(vm.activeFiltersCount, 0);
      expect(vm.matchScaleStart, 0);
    });

    test('texto da contagem de resultados', () async {
      service.all = [for (var i = 0; i < 3; i++) fakeOpportunity(i)];
      final vm = build();

      vm.search('x');
      await _settle();
      expect(vm.resultCountLabel, '3 oportunidades encontradas');

      _apply(vm, instruments: ['Piano']);
      await _settle();
      expect(vm.resultCountLabel, '3 oportunidades encontradas contendo os filtros:');
    });

    test('erro de rede vira mensagem e tentar de novo funciona', () async {
      service.fail = true;
      final vm = build();

      vm.search('x');
      await _settle();
      expect(vm.error, isNotNull);

      service.fail = false;
      await vm.load();
      expect(vm.error, isNull);
    });
  });

  group('página de uma categoria', () {
    test('começa direto na lista, travada no tipo', () async {
      service.byType = {'curso': [fakeOpportunity(1, type: 'curso')]};
      final vm = build(lockedType: 'curso', lockedTitle: 'Cursos');

      await vm.start();

      expect(vm.searchMode, isTrue);
      expect(service.calls.single.types, ['curso']);
      expect(vm.searchHint, 'Busque por cursos...');
    });

    test('fora de uma categoria, a dica de busca é genérica', () {
      expect(build().searchHint, 'Busque por oportunidades...');
    });

    test('"Ver todas" abre e fecha a subpágina', () {
      final vm = build();

      vm.openDrill('audicao', 'Audições');
      expect((vm.drillType, vm.drillLabel), ('audicao', 'Audições'));

      vm.closeDrill();
      expect(vm.drillType, isNull);
    });
  });

  test('carga que termina depois de sair da tela não quebra', () async {
    final vm = build();
    final loading = vm.load();
    vm.dispose();
    await loading; // sem "used after being disposed"
  });
}

void _apply(
  OpportunityBrowserViewModel vm, {
  List<String> types = const [],
  List<String> instruments = const [],
  List<String> countries = const [],
  List<String> states = const [],
  List<String> cities = const [],
  double? matchStart,
}) =>
    vm.applyFilters(
      types: types,
      instruments: instruments,
      countries: countries,
      states: states,
      cities: cities,
      stateLabels: const {},
      matchStart: matchStart ?? vm.matchScaleMin,
      matchEnd: vm.matchScaleMax,
      instrumentToggle: false,
      locationToggle: false,
    );

/// Deixa terminar as buscas disparadas (o falso responde na hora).
Future<void> _settle() => Future<void>.delayed(Duration.zero);
