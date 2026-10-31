import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prototipo_musiconnect/core/constants.dart';
import 'package:prototipo_musiconnect/core/monitoring.dart';
import 'package:prototipo_musiconnect/core/visitor_mode.dart';
import 'package:prototipo_musiconnect/data/models/opportunity_model.dart';
import 'package:prototipo_musiconnect/data/services/auth_service.dart';
import 'package:prototipo_musiconnect/data/services/dashboard_service.dart';
import 'package:prototipo_musiconnect/data/services/favorites_service.dart';
import 'package:prototipo_musiconnect/main.dart';
import 'package:prototipo_musiconnect/presentation/screens/auth/signup_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/auth/welcome_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/favorites_screens.dart';
import 'package:prototipo_musiconnect/presentation/screens/matcher_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/opportunity_detail_screen.dart';
import 'package:prototipo_musiconnect/presentation/widgets/favorite_button.dart';
import 'package:prototipo_musiconnect/presentation/widgets/filter_modal.dart';
import 'package:prototipo_musiconnect/presentation/widgets/opportunity_card.dart';
import 'package:prototipo_musiconnect/presentation/view_models/dashboard_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/api.dart';
import '../helpers/fakes.dart';
import '../helpers/screen.dart';

const _visitor = AuthUser.visitor();

/// Servidor sem login: Início só com o "Explorar", listas vazias.
http.Response _publicApi(http.Request r) {
      if (r.url.path.endsWith('/api/dashboard')) {
        return jsonResponse({
          'match_count': 0,
          'urgent_saved': [],
          'top_matches': [],
          'new_matches': [],
          'type_counts': {'audicao': 3},
        });
      }
      if (r.url.path.endsWith('filter-options')) return jsonResponse(<String, dynamic>{});
      return jsonResponse([]);
}

/// A navegação principal tem um ícone que pulsa sem parar (pumpAndSettle
/// nunca termina): avança o tempo em passos.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpVisitorApp(WidgetTester tester) async {
  useTallScreen(tester);
  await tester.pumpWidget(const MaterialApp(home: MainNavigation(user: _visitor)));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => VisitorMode.active = false);

  test('o usuário visitante não tem perfil nem pede novo aceite da política', () {
    expect(_visitor.isVisitor, isTrue);
    expect(_visitor.instruments, isEmpty);
    expect(_visitor.needsPrivacyAcceptance, isFalse);
    expect(fakeUser().isVisitor, isFalse);
  });

  group('entrada pela tela de boas-vindas', () {
    Future<void> tapVisit(WidgetTester tester) async {
      await tester.tap(find.text('Entrar sem uma conta cadastrada'));
      await tester.pumpAndSettle();
    }

    testWidgets('pede o aceite da política com a caixa e lembra a versão aceita',
        (tester) async {
      await FakeApi(_publicApi).run(() async {
        useTallScreen(tester);
        await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
        await tester.pump();
        await tapVisit(tester);

        expect(find.text('Entrar sem conta'), findsOneWidget);
        await tester.tap(find.text('Continuar'));
        await tester.pump();
        expect(find.text('Entrar sem conta'), findsOneWidget); // sem a caixa, não entra

        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        await tester.tap(find.text('Continuar'));
        await settle(tester);

        expect(find.byType(MainNavigation), findsOneWidget);
        expect(VisitorMode.active, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(kVisitorPrivacyVersionKey), kPrivacyPolicyVersion);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('com a política já aceita, entra direto; cancelar não entra',
        (tester) async {
      await FakeApi(_publicApi).run(() async {
        useTallScreen(tester);
        await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
        await tester.pump();
        await tapVisit(tester);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(find.byType(MainNavigation), findsNothing);
        await tester.pumpWidget(const SizedBox());

        SharedPreferences.setMockInitialValues({kVisitorPrivacyVersionKey: kPrivacyPolicyVersion});
        await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
        await tester.pump();
        await tester.tap(find.text('Entrar sem uma conta cadastrada'));
        await settle(tester);
        expect(find.text('Entrar sem conta'), findsNothing);
        expect(find.byType(MainNavigation), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    });
  });

  group('app no modo visitante', () {
    testWidgets('Início espelha o do cadastrado, com o convite no melhor match', (tester) async {
      await FakeApi(_publicApi).run(() async {
        await pumpVisitorApp(tester);

        expect(find.textContaining(RegExp(r'^(Bom dia|Boa tarde|Boa noite)!$')), findsOneWidget);
        expect(find.textContaining('Crie sua conta para descobrir'), findsOneWidget);
        expect(find.text('Explorar'), findsOneWidget);
        expect(find.text('3 abertas'), findsOneWidget);
        expect(find.text('Última chance para seus favoritos'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('menu lateral: visitante e "Voltar ao menu inicial" volta às boas-vindas',
        (tester) async {
      await FakeApi(_publicApi).run(() async {
        await pumpVisitorApp(tester);

        await tester.tap(find.byTooltip('Menu'));
        await settle(tester);
        expect(find.text('Visitante'), findsOneWidget);
        expect(find.text('Sair'), findsNothing);

        await tester.tap(find.text('Voltar ao menu inicial'));
        await settle(tester);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(VisitorMode.active, isFalse);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('Perfil convida a criar conta e mantém a chave de dados de uso',
        (tester) async {
      await FakeApi(_publicApi).run(() async {
        await pumpVisitorApp(tester);

        await tester.tap(find.text('Perfil'));
        await settle(tester);
        expect(find.text('Você está visitando o MusiConnect'), findsOneWidget);
        expect(find.text('Enviar dados de uso e erros'), findsOneWidget);

        await tester.tap(find.byType(Switch));
        await settle(tester);
        expect(Monitoring.usageDataEnabled.value, isFalse);
        await Monitoring.setUsageDataEnabled(true);

        await tester.tap(find.text('Criar conta'));
        await settle(tester);
        expect(find.byType(SignupScreen), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('favoritos do menu ficam vazios, com o convite, sem consultar o servidor',
        (tester) async {
      VisitorMode.active = true;
      final api = FakeApi(_publicApi);
      await api.run(() async {
        useTallScreen(tester);
        await tester.pumpWidget(MaterialApp(
          home: SavedOpportunitiesScreen(user: _visitor, onOpenMap: (_) {}),
        ));
        await settle(tester);
        expect(find.textContaining('Crie sua conta para salvar oportunidades'), findsOneWidget);

        await tester.pumpWidget(MaterialApp(home: FavoriteInstitutionsScreen(onOpenMap: (_) {})));
        await settle(tester);
        expect(find.textContaining('Crie sua conta para favoritar instituições'), findsOneWidget);
        expect(api.requests, isEmpty);
      });
    });
  });

  group('peças que dependem de conta', () {
    testWidgets('coração abre o popup de convite em vez de salvar', (tester) async {
      VisitorMode.active = true;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: FavoriteButton.opportunity(1))),
      ));

      await tester.tap(find.byType(FavoriteButton));
      await tester.pumpAndSettle();
      expect(find.text('Crie sua conta'), findsOneWidget);
      expect(FavoritesService.instance.isOpportunitySaved(1), isFalse);

      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('Crie sua conta'), findsNothing);
    });

    testWidgets('card mostra "–% de match"', (tester) async {
      VisitorMode.active = true;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OpportunityCard(
            opportunity: const OpportunityModel(id: 1, title: 'Audição'),
            showFavorite: false,
            onTap: () {},
          ),
        ),
      ));
      expect(find.text('–% de match'), findsOneWidget);
    });

    testWidgets('filtros pelo perfil e a Escala de Match aparecem bloqueados', (tester) async {
      useTallScreen(tester);
      await FakeApi(_publicApi).run(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: FilterModal(
              service: FakeOpportunitiesService(),
              profileFiltersLocked: true,
              onApply: ({
                required types,
                required instruments,
                required countries,
                required states,
                required cities,
                required stateLabels,
                required matchScale,
                required instrumentToggle,
                required locationToggle,
              }) {},
            ),
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Disponível com uma conta cadastrada'), findsNWidgets(3));
        expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(3));
        expect(tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged, isNull);
        await tester.tap(find.text('Meu instrumento'));
        await tester.pump();
        expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(3));
      });
    });

    testWidgets('Matcher: "Minhas" mostra só o convite', (tester) async {
      await FakeApi(_publicApi).run(() async {
        useTallScreen(tester);
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MatcherScreen(user: _visitor))));
        await tester.pumpAndSettle();
        expect(find.textContaining('Crie sua conta para acompanhar de perto'), findsOneWidget);
        expect(find.text('Criar conta'), findsOneWidget);
      });
    });

    testWidgets('detalhe: aba Matcher convida a criar conta', (tester) async {
      await FakeApi(_publicApi).run(() async {
        useTallScreen(tester);
        await tester.pumpWidget(const MaterialApp(
          home: OpportunityDetailScreen(
            opportunity: OpportunityModel(id: 1, title: 'Audição'),
            user: _visitor,
          ),
        ));
        await tester.tap(find.text('Matcher'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Crie sua conta para ver o quanto'), findsOneWidget);
      });
    });

    test('ViewModel do Início: visitante nunca cai no "nada para mostrar"', () async {
      final vm = DashboardViewModel(
        user: _visitor,
        service: FakeDashboardService(data: const DashboardData(
          matchCount: 0, topMatches: [], urgentSaved: [], newMatches: [],
        )),
        favorites: FakeFavoritesService(),
      );
      await vm.load();
      expect(vm.isVisitor, isTrue);
      expect(vm.nothingToShow, isFalse);
      vm.dispose();
    });
  });
}
