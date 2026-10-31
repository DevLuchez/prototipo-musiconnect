import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/presentation/screens/auth/welcome_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/privacy_policy_screen.dart';

import '../helpers/api.dart';
import '../helpers/screen.dart';

Future<void> openPolicy(WidgetTester tester, PrivacyPolicyScreen screen) async {
  useTallScreen(tester, height: 9000);
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => TextButton(
      onPressed: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
      child: const Text('início'),
    )),
  ));
  await tester.tap(find.text('início'));
  await tester.pumpAndSettle();
  // Descarta a tela inicial do app (o carrossel tem timer) no fim do teste.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'}));

  testWidgets('aberta pela Ajuda: mostra o que mudou e volta', (tester) async {
    await openPolicy(tester, const PrivacyPolicyScreen());

    expect(find.text('O que mudou nesta versão:'), findsOneWidget);
    expect(find.text('Quem é responsável pelos seus dados'), findsOneWidget);
    expect(find.textContaining('Atualizada em '), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('início'), findsOneWidget);
  });

  testWidgets('no cadastro não destaca mudanças', (tester) async {
    await openPolicy(tester, const PrivacyPolicyScreen(highlightChanges: false));

    expect(find.text('O que mudou nesta versão:'), findsNothing);
    expect(find.text('Quem é responsável pelos seus dados'), findsOneWidget);
  });

  group('novo aceite', () {
    testWidgets('mostra o resumo, não deixa voltar e registra o aceite', (tester) async {
      var accepts = 0;
      var fail = true;
      await openPolicy(tester, PrivacyPolicyScreen(onAccept: () async {
        accepts++;
        if (fail) throw Exception('sem conexão');
      }));

      expect(find.textContaining('Atualizamos a nossa Política'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);

      await tester.tap(find.text('Aceitar e continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Exception: sem conexão'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Aceitar e continuar'));
      await tester.pumpAndSettle();
      expect(accepts, 2);
      expect(find.text('Exception: sem conexão'), findsNothing);
    });

    testWidgets('recusar pede confirmação e sai da conta', (tester) async {
      final api = FakeApi((_) => jsonResponse({}));
      await api.run(() async {
        await openPolicy(tester, PrivacyPolicyScreen(onAccept: () async {}));

        await tester.tap(find.text('Não aceito — sair da conta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(find.text('Aceitar e continuar'), findsOneWidget);

        await tester.tap(find.text('Não aceito — sair da conta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sair'));
        await tester.pumpAndSettle();

        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(api.last.url.path, endsWith('/logout'));
        expect(await const FlutterSecureStorage().read(key: 'session_token'), isNull);
      });
    });
  });
}
