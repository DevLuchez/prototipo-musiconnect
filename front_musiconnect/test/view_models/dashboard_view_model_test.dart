import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/services/dashboard_service.dart';
import 'package:prototipo_musiconnect/presentation/view_models/dashboard_view_model.dart';

import '../helpers/fakes.dart';

/// Responde [data] (ou lança [error]) e conta quantas vezes foi chamado.
class _FakeDashboardService implements DashboardService {
  _FakeDashboardService({this.data});

  DashboardData? data;
  Object? error;
  int calls = 0;

  @override
  Future<DashboardData> fetch() async {
    calls++;
    if (error != null) throw error!;
    return data!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DashboardData _data({
  List<int> top = const [],
  List<int> urgent = const [],
  Map<String, int> counts = const {},
}) =>
    DashboardData(
      matchCount: top.length,
      topMatches: [for (final id in top) fakeOpportunity(id, matchPercentage: 90)],
      urgentSaved: [for (final id in urgent) fakeOpportunity(id)],
      newMatches: const [],
      typeCounts: counts,
    );

void main() {
  late _FakeDashboardService service;
  late FakeFavoritesService favorites;

  DashboardViewModel build({String name = 'Laura Heloísa'}) => DashboardViewModel(
        user: fakeUser(name: name),
        service: service,
        favorites: favorites,
      );

  setUp(() {
    service = _FakeDashboardService(data: _data());
    favorites = FakeFavoritesService();
  });

  test('começa carregando e termina com os dados', () async {
    final vm = build();
    expect(vm.isLoading, isTrue);

    await vm.load();

    expect(vm.isLoading, isFalse);
    expect(vm.hasError, isFalse);
  });

  test('erro do backend vira estado de erro, e tentar de novo funciona', () async {
    service.error = Exception('HTTP 500');
    final vm = build();

    await vm.load();
    expect(vm.hasError, isTrue);

    service.error = null;
    await vm.load();
    expect(vm.hasError, isFalse);
  });

  test('o destaque é o primeiro dos melhores matches', () async {
    service.data = _data(top: [7, 3]);
    final vm = build();

    await vm.load();

    expect(vm.bestMatch?.id, 7);
    expect(vm.nothingToShow, isFalse);
  });

  test('prazos se aproximando só mostram as que continuam salvas', () async {
    service.data = _data(urgent: [1, 2]);
    favorites.saved.addAll({1, 2});
    final vm = build();
    await vm.load();
    var notified = 0;
    vm.addListener(() => notified++);

    favorites.unsave(1); // desmarcou o coração em outra tela

    expect(vm.urgentSaved.map((o) => o.id), [2]);
    expect(notified, 1); // a tela é avisada na hora, sem recarregar
  });

  test('sem matches nem salvas urgentes, convida a explorar', () async {
    service.data = _data(urgent: [1]); // existe, mas não está mais salva
    final vm = build();

    await vm.load();

    expect(vm.nothingToShow, isTrue);
  });

  test('contagem por tipo para o bloco Explorar', () async {
    service.data = _data(counts: {'audicao': 3, 'curso': 1});
    final vm = build();

    await vm.load();

    expect(vm.typeCounts, {'audicao': 3, 'curso': 1});
  });

  test('saudação usa só o primeiro nome', () {
    expect(build(name: '  Laura   Heloísa Luchez ').firstName, 'Laura');
    expect(build(name: '').firstName, '');
  });

  test('trocar o usuário (perfil editado) recarrega; o mesmo usuário não', () async {
    final user = fakeUser();
    final vm = DashboardViewModel(user: user, service: service, favorites: favorites);
    await vm.load();
    final calls = service.calls;

    vm.user = user;
    expect(service.calls, calls);

    vm.user = fakeUser(name: 'Outro');
    await Future<void>.delayed(Duration.zero);
    expect(service.calls, calls + 1);
  });

  test('ao ser descartado, para de escutar os favoritos', () async {
    final vm = build();
    expect(favorites.isListened, isTrue);

    vm.dispose();

    expect(favorites.isListened, isFalse);
  });
}
