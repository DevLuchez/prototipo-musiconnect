import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prototipo_musiconnect/core/constants.dart';
import 'package:prototipo_musiconnect/core/visitor_mode.dart';
import 'package:prototipo_musiconnect/data/services/auth_service.dart';
import 'package:prototipo_musiconnect/main.dart';
import 'package:prototipo_musiconnect/presentation/screens/help_screen.dart';
import 'package:prototipo_musiconnect/presentation/tutorial/tutorial.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/api.dart';
import '../helpers/fakes.dart';
import '../helpers/screen.dart';

/// Servidor com respostas vazias (o tutorial só depende das telas).
http.Response _api(http.Request r) {
  final path = r.url.path;
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

/// A navegação tem um ícone que pulsa sem parar (pumpAndSettle não termina).
Future<void> settle(WidgetTester tester, {int steps = 15}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Política já aceita na versão atual (senão o app pede o novo aceite antes).
AuthUser _user() => fakeUser(privacyPolicyVersion: kPrivacyPolicyVersion);

Future<void> pumpApp(WidgetTester tester, {AuthUser? user, bool offered = false}) async {
  SharedPreferences.setMockInitialValues({if (offered) MainNavigationState.tutorialOfferedKey: true});
  useTallScreen(tester);
  await tester.pumpWidget(MaterialApp(home: MainNavigation(user: user ?? _user())));
  await settle(tester);
}

Future<void> next(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Próximo'));
  await settle(tester);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'});
  });
  tearDown(() => VisitorMode.active = false);

  testWidgets('primeira entrada: "Agora não" avisa onde rever e não pergunta de novo',
      (tester) async {
    await FakeApi(_api).run(() async {
      await pumpApp(tester);
      expect(find.text('Quer aprender a usar o MusiConnect?'), findsOneWidget);

      await tester.tap(find.text('Agora não'));
      await settle(tester);
      expect(find.text(kTutorialLaterMessage, findRichText: true), findsOneWidget);
      expect(find.byType(TutorialOverlay), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(MainNavigationState.tutorialOfferedKey), isTrue);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(MaterialApp(home: MainNavigation(user: _user())));
      await settle(tester);
      expect(find.text('Quer aprender a usar o MusiConnect?'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('"Quero" percorre os 10 passos, trocando de aba, até o fim', (tester) async {
    await FakeApi(_api).run(() async {
      await pumpApp(tester);
      await tester.tap(find.text('Quero'));
      await settle(tester);

      expect(find.text('1 de 10'), findsOneWidget);
      expect(find.textContaining('O Início resume o que importa hoje'), findsOneWidget);
      for (var step = 2; step <= 10; step++) {
        await next(tester);
        expect(find.text('$step de 10'), findsOneWidget);
      }
      expect(find.text('Mantenha seu perfil atualizado para receber matches melhores.'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Concluir'));
      await settle(tester);
      expect(find.byType(TutorialOverlay), findsNothing);
      expect(find.text(kTutorialDoneMessage, findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('"Voltar" volta um passo (e não aparece no primeiro)', (tester) async {
    await FakeApi(_api).run(() async {
      await pumpApp(tester);
      await tester.tap(find.text('Quero'));
      await settle(tester);
      expect(find.widgetWithText(OutlinedButton, 'Voltar'), findsNothing);

      await next(tester);
      await next(tester);
      expect(find.text('3 de 10'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Voltar'));
      await settle(tester);
      expect(find.text('2 de 10'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('"Pular tutorial" fecha na hora e avisa onde rever', (tester) async {
    await FakeApi(_api).run(() async {
      await pumpApp(tester);
      await tester.tap(find.text('Quero'));
      await settle(tester);
      await next(tester);

      await tester.tap(find.text('Pular tutorial'));
      await settle(tester);
      expect(find.byType(TutorialOverlay), findsNothing);
      expect(find.text(kTutorialSkipMessage, findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('voltar do Android volta um passo; no primeiro, encerra', (tester) async {
    await FakeApi(_api).run(() async {
      await pumpApp(tester);
      await tester.tap(find.text('Quero'));
      await settle(tester);
      await next(tester);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('1 de 10'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(TutorialOverlay), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('visitante vê os textos do modo sem conta', (tester) async {
    await FakeApi(_api).run(() async {
      await pumpApp(tester, user: const AuthUser.visitor());
      await tester.tap(find.text('Quero'));
      await settle(tester);
      expect(find.textContaining('Com uma conta, ele mostra também'), findsOneWidget);

      for (var step = 2; step <= 10; step++) {
        await next(tester);
      }
      expect(find.textContaining('Crie sua conta para ver seus matches'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('Ajuda: "Ver o tutorial" volta ao app e começa o passeio', (tester) async {
    await FakeApi(_api).run(() async {
      await pumpApp(tester, offered: true);
      expect(find.text('Quer aprender a usar o MusiConnect?'), findsNothing);

      await tester.tap(find.byTooltip('Menu'));
      await settle(tester);
      await tester.tap(find.text('Ajuda e suporte'));
      await settle(tester);
      await tester.tap(find.text('Ver o tutorial'));
      await settle(tester);

      expect(find.byType(TutorialOverlay), findsOneWidget);
      expect(find.text('1 de 10'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('"Ajuda e suporte" no aviso abre a tela de ajuda', (tester) async {
    await FakeApi(_api).run(() async {
      await pumpApp(tester);
      await tester.tap(find.text('Agora não'));
      await settle(tester);

      await tapLink(tester, 'Ajuda e suporte');
      await settle(tester);
      expect(find.byType(HelpScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
