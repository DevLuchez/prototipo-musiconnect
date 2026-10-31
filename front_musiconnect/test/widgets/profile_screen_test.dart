import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/services/auth_service.dart';
import 'package:prototipo_musiconnect/presentation/screens/auth/welcome_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/profile/change_password_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/profile/profile_screen.dart';
import 'package:prototipo_musiconnect/presentation/view_models/profile_view_model.dart';

import '../helpers/api.dart';
import '../helpers/fakes.dart';
import '../helpers/screen.dart';

void main() {
  late FakeAuthService auth;
  late FakeFavoritesService favorites;
  late FakeMatchCountService matchCount;
  late ValueNotifier<bool> usageData;
  late List<String> opened;

  Future<void> pumpProfile(WidgetTester tester,
      {AuthUser? profile, ProfileViewModel? viewModel, ValueChanged<AuthUser>? onUserChanged}) async {
    useTallScreen(tester);
    final user = profile ??
        fakeUser(
          name: 'Laura',
          instruments: const ['Piano', 'Violino'],
          isStudent: true,
          isProfessional: true,
        );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileScreen(
          user: user,
          onUserChanged: onUserChanged,
          onOpenMatches: () => opened.add('matches'),
          onOpenSavedOpportunities: () => opened.add('salvas'),
          onOpenFavoriteInstitutions: () => opened.add('favoritas'),
          viewModel: viewModel ?? ProfileViewModel(
            user: user,
            authService: auth,
            favorites: favorites,
            matchCount: matchCount,
            usageDataEnabled: usageData,
            setUsageDataEnabled: (v) async => usageData.value = v,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    auth = FakeAuthService();
    favorites = FakeFavoritesService(saved: {1, 2, 3}, institutions: {'node_1'});
    matchCount = FakeMatchCountService(count: 7);
    usageData = ValueNotifier(true);
    opened = [];
  });

  testWidgets('mostra os dados do perfil e os números', (tester) async {
    await pumpProfile(tester);

    expect(find.text('L'), findsOneWidget); // avatar
    expect(find.text('Laura'), findsOneWidget);
    expect(find.text('aluna@example.com'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Piano'), findsOneWidget);
    expect(find.text('Profissional'), findsOneWidget);
    expect(find.text('Estudante'), findsOneWidget);
    expect(find.text('Jaraguá do Sul, SC, Brasil'), findsOneWidget);
  });

  testWidgets('números do card levam às listas', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('Matches'));
    await tester.tap(find.text('Oport. salvas'));
    await tester.tap(find.text('Inst. favoritas'));

    expect(opened, ['matches', 'salvas', 'favoritas']);
  });

  testWidgets('números atualizam ao vivo', (tester) async {
    await pumpProfile(tester);

    matchCount.arrive(null);
    await tester.pump();

    expect(find.text('–'), findsOneWidget); // consulta falhou: traço, não número
  });

  testWidgets('chave de dados de uso liga e desliga', (tester) async {
    await pumpProfile(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(usageData.value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('alterar senha abre a tela de troca de senha', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('Alterar senha'));
    await tester.pumpAndSettle();

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });

  testWidgets('sair da conta pede confirmação', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    expect(find.text('Tem certeza que deseja sair?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Tem certeza que deseja sair?'), findsNothing);
  });

  group('excluir conta', () {
    Future<void> confirmWith(WidgetTester tester, String password) async {
      await tester.tap(find.text('Excluir conta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
    }

    testWidgets('senha errada mostra a mensagem e fica no perfil', (tester) async {
      auth.deleteError = 'Senha incorreta.';
      await pumpProfile(tester);

      await confirmWith(tester, 'errada');

      expect(find.text('Senha incorreta.'), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('senha certa exclui e volta para a tela inicial', (tester) async {
      await pumpProfile(tester);

      await confirmWith(tester, 'Senha#123');

      expect(auth.deletedWith, 'Senha#123');
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('cancelar não exclui', (tester) async {
      await pumpProfile(tester);

      await tester.tap(find.text('Excluir conta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(auth.deletedWith, isNull);
    });
  });

  testWidgets('editar perfil atualiza a tela e avisa o app', (tester) async {
    final changed = <AuthUser>[];
    final api = FakeApi((r) => r.url.host.contains('geonames')
        ? geoNames(r)
        : jsonResponse({...userJson(), 'name': 'Laura Luchez', 'instruments': ['Flauta']}));
    await api.run(() async {
      await pumpProfile(tester, onUserChanged: changed.add);

      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(changed.single.name, 'Laura Luchez');
      expect(find.text('Laura Luchez'), findsOneWidget);
      expect(find.text('Flauta'), findsOneWidget);
    });
  });

  testWidgets('voltar da edição sem salvar não muda nada', (tester) async {
    final changed = <AuthUser>[];
    await FakeApi(geoNames).run(() async {
      await pumpProfile(tester, onUserChanged: changed.add);

      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(changed, isEmpty);
      expect(find.text('Laura'), findsOneWidget);
    });
  });

  testWidgets('perfil sem instrumentos nem ramo; atualizado de fora', (tester) async {
    final empty = fakeUser(name: 'Ana', instruments: const [], isStudent: false);
    final viewModel = ProfileViewModel(
      user: empty,
      authService: auth,
      favorites: favorites,
      matchCount: matchCount,
      usageDataEnabled: usageData,
      setUsageDataEnabled: (v) async => usageData.value = v,
    );
    await pumpProfile(tester, profile: empty, viewModel: viewModel);
    expect(find.text('Não informado'), findsNWidgets(2));

    await pumpProfile(tester, profile: fakeUser(name: 'Bia'), viewModel: viewModel);
    expect(find.text('Bia'), findsOneWidget);
  });
}
