import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/services/auth_service.dart';
import 'package:prototipo_musiconnect/presentation/screens/profile/change_password_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/profile/edit_profile_screen.dart';

import '../helpers/api.dart';
import '../helpers/fakes.dart';
import '../helpers/screen.dart';

const _senha = 'Senha#123';

/// Abre [screen] por cima de uma tela inicial, para que o "voltar" e o
/// resultado devolvido no pop possam ser verificados.
Future<List<Object?>> openFrom(WidgetTester tester, Widget screen) async {
  final results = <Object?>[];
  useTallScreen(tester);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () async => results.add(await Navigator.of(context).push<Object?>(
            MaterialPageRoute(builder: (_) => screen))),
        child: const Text('início'),
      )),
    ),
  ));
  await tester.tap(find.text('início'));
  await tester.pumpAndSettle();
  return results;
}

Future<void> fill(WidgetTester tester, String hint, String text) async {
  await tester.enterText(find.widgetWithText(TextField, hint), text);
  await tester.pumpAndSettle();
}

Future<void> pick(WidgetTester tester, String hint, String option) async {
  await tester.tap(find.widgetWithText(TextField, hint));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, option));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

bool enabled(WidgetTester tester, String label) {
  final button = find.ancestor(
      of: find.text(label).last, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
  return tester.widget<ButtonStyleButton>(button.first).onPressed != null;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'}));

  group('Editar perfil', () {
    final user = fakeUser(state: 'Santa Catarina');

    testWidgets('vem preenchido com o perfil e salva as mudanças', (tester) async {
      final api = FakeApi((r) {
        if (r.url.host.contains('geonames')) return geoNames(r);
        return jsonResponse({...userJson(), 'name': 'Laura'});
      });
      await api.run(() async {
        final results = await openFrom(tester, EditProfileScreen(user: user));

        expect(find.text('Laura Heloísa'), findsOneWidget);
        expect(find.text('Brasil'), findsOneWidget);
        expect(find.text('Santa Catarina'), findsOneWidget);
        expect(find.text('Jaraguá do Sul'), findsOneWidget);

        await tester.enterText(find.widgetWithText(TextField, 'Laura Heloísa'), 'Laura');
        await tapText(tester, 'Profissional');
        await tapText(tester, 'Salvar');

        final sent = jsonDecode(api.last.body) as Map<String, dynamic>;
        expect(api.last.method, 'PATCH');
        expect(sent['name'], 'Laura');
        expect(sent['is_professional'], isTrue);
        expect(sent['state'], 'Santa Catarina');
        expect(sent['city'], 'Jaraguá do Sul');
        expect((results.single as AuthUser).name, 'Laura');
      });
    });

    testWidgets('trocar país e estado limpa o que vem depois', (tester) async {
      await FakeApi(geoNames).run(() async {
        await openFrom(tester, EditProfileScreen(user: user));

        await pick(tester, 'Brasil', 'Brasil');
        expect(find.text('Santa Catarina'), findsNothing);
        expect(find.text('Selecione o estado primeiro'), findsOneWidget);

        await pick(tester, 'Selecione o estado onde você mora', 'Santa Catarina');
        expect(find.text('Jaraguá do Sul'), findsNothing);
        await pick(tester, 'Selecione a cidade onde você mora', 'Jaraguá do Sul');
        expect(find.text('Jaraguá do Sul'), findsOneWidget);
        expect(enabled(tester, 'Salvar'), isTrue);
      });
    });

    testWidgets('sem nome ou sem ramo não deixa salvar', (tester) async {
      await FakeApi(geoNames).run(() async {
        await openFrom(tester, EditProfileScreen(user: user));

        await tapText(tester, 'Estudante');
        expect(enabled(tester, 'Salvar'), isFalse);
        await tapText(tester, 'Estudante');
        expect(enabled(tester, 'Salvar'), isTrue);

        await tester.enterText(find.widgetWithText(TextField, 'Laura Heloísa'), ' ');
        await tester.pumpAndSettle();
        expect(enabled(tester, 'Salvar'), isFalse);
      });
    });

    testWidgets('perfil sem local conhecido começa em branco', (tester) async {
      await FakeApi(geoNames).run(() async {
        await openFrom(tester, EditProfileScreen(user: fakeUser(country: 'Atlântida')));

        expect(find.text('Selecione o país primeiro'), findsOneWidget);
        expect(find.text('Selecione o estado primeiro'), findsOneWidget);
        expect(enabled(tester, 'Salvar'), isFalse);
      });
    });

    testWidgets('erro do servidor aparece na tela; voltar não salva', (tester) async {
      final api = FakeApi((r) => r.url.host.contains('geonames')
          ? geoNames(r)
          : detailError('Nome inválido.', status: 422));
      await api.run(() async {
        final results = await openFrom(tester, EditProfileScreen(user: user));

        await tapText(tester, 'Salvar');
        expect(find.text('Nome inválido.'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pumpAndSettle();
        expect(results, [null]);
      });
    });
  });

  group('Trocar senha', () {
    Future<void> fillForm(WidgetTester tester, {String confirm = _senha}) async {
      await fill(tester, 'Insira sua senha atual', 'antiga');
      await fill(tester, 'Digite a nova senha', _senha);
      await fill(tester, 'Digite a senha novamente', confirm);
    }

    testWidgets('troca a senha, guarda o novo token e volta', (tester) async {
      final api = FakeApi((_) => jsonResponse({'token': 'novo'}));
      await api.run(() async {
        await openFrom(tester, const ChangePasswordScreen());

        expect(enabled(tester, 'Salvar'), isFalse);
        expect(find.text('Digite a senha primeiro'), findsOneWidget);
        await fillForm(tester, confirm: 'outra');
        expect(find.text('As senhas não coincidem'), findsOneWidget);
        expect(enabled(tester, 'Salvar'), isFalse);

        await fill(tester, 'Digite a senha novamente', _senha);
        expect(find.text('As senhas coincidem'), findsOneWidget);
        await tapText(tester, 'Salvar');

        expect(jsonDecode(api.last.body),
            {'current_password': 'antiga', 'new_password': _senha});
        expect(find.text('Senha alterada com sucesso.'), findsOneWidget);
        expect(find.text('início'), findsOneWidget);
        expect(await const FlutterSecureStorage().read(key: 'session_token'), 'novo');
      });
    });

    testWidgets('senha atual errada mostra o erro, que some ao digitar', (tester) async {
      await FakeApi((_) => detailError('Senha atual incorreta.')).run(() async {
        await openFrom(tester, const ChangePasswordScreen());

        await fillForm(tester);
        await tapText(tester, 'Salvar');
        expect(find.text('Senha atual incorreta.'), findsOneWidget);

        await fill(tester, 'Insira sua senha atual', 'outra');
        expect(find.text('Senha atual incorreta.'), findsNothing);
      });
    });

    testWidgets('sem conexão', (tester) async {
      await FakeApi(offline).run(() async {
        await openFrom(tester, const ChangePasswordScreen());

        await fillForm(tester);
        await tapText(tester, 'Salvar');
        expect(find.textContaining('Não foi possível conectar'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pumpAndSettle();
        expect(find.text('início'), findsOneWidget);
      });
    });
  });
}
