import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/presentation/view_models/profile_view_model.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeFavoritesService favorites;
  late FakeMatchCountService matchCount;
  late ValueNotifier<bool> usageData;

  ProfileViewModel build({String name = 'Laura', bool isStudent = true,
      bool isProfessional = false, String? city = 'Jaraguá do Sul',
      String? state = 'SC', String? country = 'Brasil'}) =>
      ProfileViewModel(
        user: fakeUser(name: name, isStudent: isStudent, isProfessional: isProfessional,
            city: city, state: state, country: country),
        authService: auth,
        favorites: favorites,
        matchCount: matchCount,
        usageDataEnabled: usageData,
        setUsageDataEnabled: (value) async => usageData.value = value,
      );

  setUp(() {
    auth = FakeAuthService();
    favorites = FakeFavoritesService(saved: {1, 2, 3}, institutions: {'node_1'});
    matchCount = FakeMatchCountService(count: 12);
    usageData = ValueNotifier(true);
  });

  group('dados exibidos', () {
    test('inicial do avatar', () {
      expect(build(name: 'laura').initial, 'L');
      expect(build(name: '').initial, '?');
    });

    test('ramo de atuação', () {
      expect(build(isStudent: true, isProfessional: true).ramoLabels,
          ['Profissional', 'Estudante']);
      expect(build(isStudent: false).ramoLabels, isEmpty);
    });

    test('localização junta só o que foi informado', () {
      expect(build().location, 'Jaraguá do Sul, SC, Brasil');
      expect(build(city: null, state: '').location, 'Brasil');
      expect(build(city: null, state: null, country: null).location, 'Não informada');
    });
  });

  group('card de estatísticas', () {
    test('mostra matches, salvas e favoritas', () {
      final vm = build();
      expect(vm.matchCountLabel, '12');
      expect(vm.savedOpportunitiesCount, 3);
      expect(vm.favoriteInstitutionsCount, 1);
    });

    test('matches ainda carregando ou com erro aparece como traço', () {
      matchCount.count = null;
      expect(build().matchCountLabel, '–');
    });

    test('atualiza quando um coração muda ou o número de matches chega', () {
      final vm = build();
      var notified = 0;
      vm.addListener(() => notified++);

      favorites.unsave(1);
      matchCount.arrive(15);

      expect(notified, 2);
      expect(vm.savedOpportunitiesCount, 2);
      expect(vm.matchCountLabel, '15');
    });
  });

  test('editar o perfil troca o usuário e recalcula os matches', () {
    final vm = build();

    vm.profileEdited(fakeUser(name: 'Novo Nome', city: 'Joinville'));

    expect(vm.user.name, 'Novo Nome');
    expect(vm.location, 'Joinville, SC, Brasil');
    expect(matchCount.refreshCalls, 1);
  });

  test('chave de dados de uso lê e grava a escolha', () async {
    final vm = build();
    expect(vm.usageDataEnabled, isTrue);

    await vm.setUsageDataEnabled(false);

    expect(vm.usageDataEnabled, isFalse);
  });

  group('excluir conta', () {
    test('sucesso devolve null', () async {
      expect(await build().deleteAccount('Senha#123'), isNull);
      expect(auth.deletedWith, 'Senha#123');
    });

    test('senha errada devolve a mensagem do backend', () async {
      auth.deleteError = 'Senha incorreta.';
      expect(await build().deleteAccount('errada'), 'Senha incorreta.');
    });
  });

  test('ao ser descartado, para de escutar os serviços', () {
    final vm = build();
    vm.dispose();

    expect(favorites.isListened, isFalse);
    // Os outros dois também: mudar não deve chamar um ViewModel descartado.
    matchCount.arrive(1);
    usageData.value = false;
  });
}
