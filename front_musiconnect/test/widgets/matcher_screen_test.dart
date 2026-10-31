import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/presentation/screens/matcher_screen.dart';

import '../helpers/api.dart';
import '../helpers/fakes.dart';
import '../helpers/screen.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'}));

  /// Servidor sem nenhuma oportunidade aberta.
  final emptyApi = FakeApi((r) => r.url.path.endsWith('filter-options')
      ? jsonResponse(<String, dynamic>{})
      : jsonResponse([]));

  Future<void> pumpMatcher(WidgetTester tester, {ValueNotifier<int?>? tabRequest}) async {
    useTallScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MatcherScreen(user: fakeUser(), tabRequest: tabRequest)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sem matches altos, leva para todas as oportunidades', (tester) async {
    await emptyApi.run(() async {
      await pumpMatcher(tester);

      expect(find.textContaining('Ainda não encontramos oportunidades'), findsOneWidget);
      await tester.tap(find.text('Ver todas as oportunidades'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nenhuma oportunidade aberta no momento.'), findsOneWidget);
    });
  });

  testWidgets('pedido de aba vindo do Perfil', (tester) async {
    final tabRequest = ValueNotifier<int?>(null);
    await emptyApi.run(() async {
      await pumpMatcher(tester, tabRequest: tabRequest);

      tabRequest.value = 1;
      await tester.pumpAndSettle();

      expect(find.textContaining('Nenhuma oportunidade aberta no momento.'), findsOneWidget);
      expect(tabRequest.value, isNull);
    });
  });

  testWidgets('"Saiba mais" explica o que é match', (tester) async {
    await emptyApi.run(() async {
      await pumpMatcher(tester);

      await tester.tap(find.text('Saiba mais'));
      await tester.pumpAndSettle();
      expect(find.text('O que é match?'), findsOneWidget);
      expect(find.textContaining('A sua localização'), findsOneWidget);

      await tester.tap(find.text('Entendi'));
      await tester.pumpAndSettle();
      expect(find.text('O que é match?'), findsNothing);
    });
  });
}
