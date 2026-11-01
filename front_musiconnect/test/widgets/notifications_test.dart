import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prototipo_musiconnect/core/constants.dart';
import 'package:prototipo_musiconnect/core/push_notifications.dart';
import 'package:prototipo_musiconnect/core/visitor_mode.dart';
import 'package:prototipo_musiconnect/data/services/auth_service.dart';
import 'package:prototipo_musiconnect/main.dart';
import 'package:prototipo_musiconnect/presentation/screens/favorites_screens.dart';
import 'package:prototipo_musiconnect/presentation/screens/opportunity_detail_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/profile/profile_screen.dart';
import 'package:prototipo_musiconnect/presentation/view_models/profile_view_model.dart';
import 'package:prototipo_musiconnect/presentation/widgets/auth/logout_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/api.dart';
import '../helpers/fakes.dart';
import '../helpers/screen.dart';

const _question = 'Quer ser avisado de oportunidades que combinam com você e de '
    'prazos dos seus favoritos?';

late FakePushBackend backend;
late Map<String, dynamic> prefsSent;

http.Response _api(http.Request r) {
  final path = r.url.path;
  if (path.endsWith('/api/notifications/device')) return http.Response('', 204);
  if (path.endsWith('/api/notifications/preferences')) {
    prefsSent = json.decode(r.body) as Map<String, dynamic>;
    return jsonResponse(userJson()..addAll(prefsSent));
  }
  if (path.endsWith('/api/opportunities/12')) return jsonResponse(opportunityJson(12, title: 'Bolsa de Harpa'));
  if (path.endsWith('/api/opportunities/99')) return detailError('não encontrada', status: 404);
  if (path.endsWith('/api/dashboard')) {
    return jsonResponse({
      'match_count': 0,
      'urgent_saved': [],
      'top_matches': [],
      'new_matches': [],
      'type_counts': {'audicao': 3},
    });
  }
  if (path.endsWith('/api/auth/me')) return jsonResponse(userJson());
  if (path.endsWith('/ids')) return jsonResponse({'opportunities': [], 'institutions': []});
  if (path.endsWith('filter-options')) return jsonResponse(<String, dynamic>{});
  if (path.contains('match-count')) return jsonResponse({'count': 0});
  return jsonResponse([]);
}

Future<void> settle(WidgetTester tester, {int steps = 15}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AuthUser _user() => fakeUser(privacyPolicyVersion: kPrivacyPolicyVersion);

/// Tutorial já oferecido: o convite das notificações aparece logo.
Future<void> pumpApp(WidgetTester tester, {AuthUser? user, bool notificationsOffered = false}) async {
  SharedPreferences.setMockInitialValues({
    MainNavigationState.tutorialOfferedKey: true,
    if (notificationsOffered) PushNotifications.offeredKey: true,
  });
  useTallScreen(tester);
  await tester.pumpWidget(MaterialApp(home: MainNavigation(user: user ?? _user())));
  await settle(tester);
}

void main() {
  late FakeApi api;
  final original = PushNotifications.instance;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'});
    backend = FakePushBackend();
    prefsSent = {};
    PushNotifications.instance = PushNotifications(backend: backend);
    api = FakeApi(_api);
  });
  tearDown(() {
    PushNotifications.instance = original;
    VisitorMode.active = false;
  });

  bool deviceRegistered() =>
      api.requests.any((r) => r.url.path.endsWith('/api/notifications/device'));

  group('convite', () {
    testWidgets('"Quero" pede a permissão do Android e registra o aparelho', (tester) async {
      await api.run(() async {
        await pumpApp(tester);
        expect(find.text(_question), findsOneWidget);

        await tester.tap(find.text('Quero'));
        await settle(tester);

        expect(backend.permissionRequests, 1);
        expect(deviceRegistered(), isTrue);
        expect(find.text(kNotificationsLaterMessage), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(PushNotifications.offeredKey), isTrue);
      });
    });

    testWidgets('"Quero" com a permissão negada avisa onde ligar depois', (tester) async {
      backend.allowOnRequest = false;
      await api.run(() async {
        await pumpApp(tester);
        await tester.tap(find.text('Quero'));
        await settle(tester);

        expect(deviceRegistered(), isFalse);
        expect(find.text(kNotificationsLaterMessage), findsOneWidget);
      });
    });

    testWidgets('"Agora não" desliga as chaves, não pede a permissão e não pergunta de novo',
        (tester) async {
      await api.run(() async {
        await pumpApp(tester);
        await tester.tap(find.text('Agora não'));
        await settle(tester);

        expect(backend.permissionRequests, 0);
        expect(prefsSent, {'notify_new_matches': false, 'notify_deadlines': false});
        expect(find.text(kNotificationsLaterMessage), findsOneWidget);
        await tester.pumpWidget(const SizedBox());

        await tester.pumpWidget(MaterialApp(home: MainNavigation(user: _user())));
        await settle(tester);
        expect(find.text(_question), findsNothing);
      });
    });

    testWidgets('vem depois do convite do tutorial', (tester) async {
      await api.run(() async {
        SharedPreferences.setMockInitialValues({});
        useTallScreen(tester);
        await tester.pumpWidget(MaterialApp(home: MainNavigation(user: _user())));
        await settle(tester);
        expect(find.text('Quer aprender a usar o MusiConnect?'), findsOneWidget);
        expect(find.text(_question), findsNothing);

        await tester.tap(find.text('Agora não'));
        await settle(tester);
        expect(find.text(_question), findsOneWidget);
      });
    });

    testWidgets('visitante não é convidado nem registra aparelho', (tester) async {
      await api.run(() async {
        await pumpApp(tester, user: const AuthUser.visitor());

        expect(find.text(_question), findsNothing);
        expect(deviceRegistered(), isFalse);
      });
    });

    testWidgets('com a permissão já dada, registra o aparelho ao abrir', (tester) async {
      backend.permitted = true;
      await api.run(() async {
        await pumpApp(tester, notificationsOffered: true);

        expect(deviceRegistered(), isTrue);
      });
    });
  });

  group('toque na notificação', () {
    testWidgets('de uma oportunidade abre o detalhe', (tester) async {
      await api.run(() async {
        await pumpApp(tester, notificationsOffered: true);

        backend.tapController.add(const PushMessage(
            data: {'open': 'opportunity', 'opportunity_id': '12'}));
        await settle(tester);

        expect(find.byType(OpportunityDetailScreen), findsOneWidget);
        expect(find.text('Bolsa de Harpa'), findsWidgets);
      });
    });

    testWidgets('de oportunidade que sumiu avisa', (tester) async {
      await api.run(() async {
        await pumpApp(tester, notificationsOffered: true);

        backend.tapController.add(const PushMessage(
            data: {'open': 'opportunity', 'opportunity_id': '99'}));
        await settle(tester);

        expect(find.text('Essa oportunidade não está mais disponível.'), findsOneWidget);
      });
    });

    testWidgets('de várias novas abre "Minhas oportunidades"', (tester) async {
      await api.run(() async {
        await pumpApp(tester, notificationsOffered: true);

        backend.tapController.add(const PushMessage(data: {'open': 'matches'}));
        await settle(tester);

        expect(find.text('Minhas oportunidades'), findsOneWidget);
      });
    });

    testWidgets('de prazos abre os favoritos', (tester) async {
      await api.run(() async {
        await pumpApp(tester, notificationsOffered: true);

        backend.tapController.add(const PushMessage(data: {'open': 'favorites'}));
        await settle(tester);

        expect(find.byType(SavedOpportunitiesScreen), findsOneWidget);
      });
    });

    testWidgets('que abriu o app vai direto ao que ela avisa', (tester) async {
      backend.initial = const PushMessage(data: {'open': 'favorites'});
      await api.run(() async {
        await pumpApp(tester);

        expect(find.byType(SavedOpportunitiesScreen), findsOneWidget);
        expect(find.text(_question), findsNothing);
      });
    });

    testWidgets('com o app aberto aparece um aviso com "Ver"', (tester) async {
      await api.run(() async {
        await pumpApp(tester, notificationsOffered: true);

        backend.foregroundController.add(const PushMessage(
            title: '2 favoritas com prazo acabando',
            body: 'Toque para ver.',
            data: {'open': 'favorites'}));
        await settle(tester);
        expect(find.text('2 favoritas com prazo acabando\nToque para ver.'), findsOneWidget);

        await tester.tap(find.text('Ver'));
        await settle(tester);
        expect(find.byType(SavedOpportunitiesScreen), findsOneWidget);
      });
    });
  });

  group('Perfil', () {
    Future<ProfileViewModel> pumpProfile(WidgetTester tester, {AuthUser? user}) async {
      useTallScreen(tester);
      final u = user ?? _user();
      final vm = ProfileViewModel(
        user: u,
        authService: FakeAuthService(),
        favorites: FakeFavoritesService(),
        matchCount: FakeMatchCountService(count: 0),
        usageDataEnabled: ValueNotifier(true),
        setUsageDataEnabled: (_) async {},
        push: PushNotifications.instance,
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProfileScreen(user: u, viewModel: vm))));
      await tester.pumpAndSettle();
      return vm;
    }

    Finder switchOf(String title) => find.descendant(
          of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
          matching: find.byType(Switch),
        );

    testWidgets('sem a permissão do Android as chaves aparecem desligadas', (tester) async {
      await api.run(() async {
        await pumpProfile(tester);

        expect(tester.widget<Switch>(switchOf('Novas oportunidades para você')).value, isFalse);
        expect(tester.widget<Switch>(switchOf('Prazos dos favoritos')).value, isFalse);
      });
    });

    testWidgets('permissão dada em outro lugar (convite) liga as chaves na hora', (tester) async {
      await api.run(() async {
        await pumpProfile(tester);
        expect(tester.widget<Switch>(switchOf('Prazos dos favoritos')).value, isFalse);

        await PushNotifications.instance.enable();
        await tester.pumpAndSettle();

        expect(tester.widget<Switch>(switchOf('Novas oportunidades para você')).value, isTrue);
        expect(tester.widget<Switch>(switchOf('Prazos dos favoritos')).value, isTrue);
      });
    });

    testWidgets('ligar pede a permissão e salva só a chave tocada', (tester) async {
      await api.run(() async {
        await pumpProfile(tester);

        await tester.tap(switchOf('Prazos dos favoritos'));
        await tester.pumpAndSettle();

        expect(backend.permissionRequests, 1);
        expect(prefsSent, {'notify_new_matches': false, 'notify_deadlines': true});
        expect(tester.widget<Switch>(switchOf('Prazos dos favoritos')).value, isTrue);
        expect(tester.widget<Switch>(switchOf('Novas oportunidades para você')).value, isFalse);
      });
    });

    testWidgets('ligar com a permissão negada explica onde permitir', (tester) async {
      backend.allowOnRequest = false;
      await api.run(() async {
        await pumpProfile(tester);

        await tester.tap(switchOf('Novas oportunidades para você'));
        await tester.pumpAndSettle();

        expect(prefsSent, isEmpty);
        expect(find.text('Permita as notificações do MusiConnect nas configurações do Android.'),
            findsOneWidget);
      });
    });

    testWidgets('desligar com a permissão dada só salva a chave', (tester) async {
      backend.permitted = true;
      await api.run(() async {
        await pumpProfile(tester);
        expect(tester.widget<Switch>(switchOf('Novas oportunidades para você')).value, isTrue);

        await tester.tap(switchOf('Novas oportunidades para você'));
        await tester.pumpAndSettle();

        expect(backend.permissionRequests, 0);
        expect(prefsSent, {'notify_new_matches': false, 'notify_deadlines': true});
      });
    });

    testWidgets('sem conexão mostra o erro', (tester) async {
      backend.permitted = true;
      await FakeApi(offline).run(() async {
        await pumpProfile(tester);
        await tester.tap(switchOf('Prazos dos favoritos'));
        await tester.pumpAndSettle();

        expect(find.text('Não foi possível conectar ao servidor. Verifique sua conexão.'),
            findsOneWidget);
      });
    });
  });

  testWidgets('"Sair" descarta o identificador do aparelho', (tester) async {
    await api.run(() async {
      useTallScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => confirmAndLogout(context),
            child: const Text('sair'),
          ),
        ),
      ));
      await tester.tap(find.text('sair'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();

      expect(backend.tokensDeleted, 1);
    });
  });

  test('sem Firebase tudo vira nada (sem erro)', () async {
    final push = PushNotifications();
    expect(push.available, isFalse);
    expect(await push.enable(), isFalse);
    expect(await push.isPermitted(), isFalse);
    expect(await push.initialTap(), isNull);
    await push.register();
    await push.unregister();
  });
}
