// Testes instrumentados: rodam o app de verdade num celular ou emulador,
// contra a API pública, tocando na interface como uma pessoa faria.
//
//   flutter test integration_test -d <id do aparelho>
//
// Só usam o modo visitante e consultas — nada é criado, alterado ou apagado
// no servidor. O login usa um e-mail que não existe, para conferir o erro.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototipo_musiconnect/core/monitoring.dart';
import 'package:prototipo_musiconnect/core/visitor_mode.dart';
import 'package:prototipo_musiconnect/main.dart';

/// Pump até [finder] aparecer — `pumpAndSettle` não serve aqui: os
/// indicadores de carregamento animam sem parar enquanto a API responde.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Não apareceu a tempo: $finder');
}

/// Toca em [finder] se ele estiver na tela (popups que só aparecem na
/// primeira vez no aparelho, como o convite do tutorial).
Future<void> tapIfPresent(WidgetTester tester, Finder finder) async {
  await tester.pump(const Duration(seconds: 1));
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first);
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Abre o app na tela de boas-vindas.
Future<void> openApp(WidgetTester tester) async {
  VisitorMode.active = false;
  await tester.pumpWidget(const MusicConnectApp());
  await waitFor(tester, find.text('Entrar sem uma conta cadastrada'));
}

/// Entra como visitante, aceitando a política, até o Início.
Future<void> enterAsVisitor(WidgetTester tester) async {
  await tester.tap(find.text('Entrar sem uma conta cadastrada'));
  await tester.pump(const Duration(seconds: 1));
  if (find.text('Entrar sem conta').evaluate().isNotEmpty) {
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Continuar'));
  }
  await waitFor(tester, find.text('Explorar'));
  await tapIfPresent(tester, find.text('Agora não'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Monitoring.init();
  });

  testWidgets('visitante entra e navega pelas quatro abas', (tester) async {
    await openApp(tester);
    await enterAsVisitor(tester);

    expect(find.text('Explorar'), findsOneWidget);

    await tester.tap(find.text('Mapa'));
    await waitFor(tester, find.text('Legenda'));

    await tester.tap(find.text('Matcher'));
    await waitFor(tester, find.text('Todas as oportunidades'));

    await tester.tap(find.text('Perfil'));
    await waitFor(tester, find.text('Você está visitando o MusiConnect'));
  });

  testWidgets('visitante abre uma oportunidade e recebe o convite ao favoritar',
      (tester) async {
    await openApp(tester);
    await enterAsVisitor(tester);

    await tester.tap(find.text('Matcher'));
    await waitFor(tester, find.text('Todas as oportunidades'));
    await tester.tap(find.text('Todas as oportunidades'));
    await waitFor(tester, find.text('–% de match'));

    await tester.tap(find.text('–% de match').first);
    await waitFor(tester, find.text('Descrição do Edital'));
    expect(find.text('Sobre o Edital'), findsOneWidget);

    await tester.tap(find.text('Matcher').last);
    await waitFor(tester, find.textContaining('Crie sua conta para ver o quanto'));

    await tester.tap(find.byIcon(Icons.favorite_border_rounded).last);
    await waitFor(tester, find.text('Crie sua conta'));
  });

  testWidgets('login com credenciais inválidas mostra o erro', (tester) async {
    await openApp(tester);

    await tester.tap(find.text('Faça Login'));
    await waitFor(tester, find.text('Esqueci minha senha'));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'teste.instrumentado@exemplo.com');
    await tester.enterText(fields.at(1), 'SenhaErrada123');
    await tester.pump();
    await tester.tap(find.text('Entrar'));

    await waitFor(tester, find.text('E-mail ou senha inválidos.'));
  });
}
