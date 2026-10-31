import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/presentation/screens/auth/forgot_password_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/auth/login_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/auth/reset_password_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/auth/signup_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/auth/welcome_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/privacy_policy_screen.dart';

import '../helpers/api.dart';
import '../helpers/screen.dart';

const _senha = 'Senha#123';

/// Abre [screen] num app com servidor simulado. No fim do teste, a tela é
/// descartada (cancela timers de carrossel/contagem regressiva).
Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  useTallScreen(tester);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String hint, String text) async {
  await tester.enterText(find.widgetWithText(TextField, hint), text);
  await tester.pumpAndSettle();
}

/// Escolhe [option] num campo com autocomplete (abre a lista ao tocar).
Future<void> pick(WidgetTester tester, String hint, String option) async {
  await tester.tap(find.widgetWithText(TextField, hint));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, option));
  await tester.pumpAndSettle();
}

/// Botão de voltar próprio do app (seta no canto superior esquerdo).
Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
  await tester.pumpAndSettle();
}

bool enabled(WidgetTester tester, String label) {
  final button = find.ancestor(of: find.text(label).last, matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton));
  return tester.widget<ButtonStyleButton>(button.first).onPressed != null;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Boas-vindas', () {
    testWidgets('leva ao login e ao cadastro', (tester) async {
      await FakeApi((_) => jsonResponse({})).run(() async {
        await pumpScreen(tester, const WelcomeScreen());
        final slideTitle = find.textContaining(
            RegExp('^(Seu perfil, seu ritmo|Oportunidades mundiais|Matching musical)\$'));
        expect(slideTitle, findsWidgets);

        // O carrossel avança sozinho
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();

        await tapText(tester, 'Faça Login');
        expect(find.byType(LoginScreen), findsOneWidget);
        await goBack(tester);

        await tapText(tester, 'Cadastre-se');
        expect(find.byType(SignupScreen), findsOneWidget);
      });
    });
  });

  group('Login', () {
    testWidgets('botão só habilita com e-mail e senha', (tester) async {
      await pumpScreen(tester, const LoginScreen());
      expect(enabled(tester, 'Entrar'), isFalse);

      await fill(tester, 'Insira seu e-mail', 'aluna@example.com');
      await fill(tester, 'Insira sua senha', _senha);

      expect(enabled(tester, 'Entrar'), isTrue);
    });

    testWidgets('erro do backend aparece e some ao editar', (tester) async {
      await FakeApi((_) => detailError('E-mail ou senha inválidos.', status: 401)).run(() async {
        await pumpScreen(tester, const LoginScreen());
        await fill(tester, 'Insira seu e-mail', 'aluna@example.com');
        await fill(tester, 'Insira sua senha', 'errada');

        await tapText(tester, 'Entrar');
        expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);

        await fill(tester, 'Insira sua senha', 'errada2');
        expect(find.text('E-mail ou senha inválidos.'), findsNothing);
      });
    });

    testWidgets('links para esqueci a senha e cadastro', (tester) async {
      await pumpScreen(tester, const LoginScreen());

      await tapText(tester, 'Esqueci minha senha');
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      await goBack(tester);

      await tapLink(tester, 'Cadastre-se');
      expect(find.byType(SignupScreen), findsOneWidget);
    });

    testWidgets('voltar sem tela anterior vai para as boas-vindas', (tester) async {
      await pumpScreen(tester, const LoginScreen());

      await goBack(tester);

      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });

  group('Esqueci a senha', () {
    testWidgets('envia o link e libera o reenvio depois de 30 s', (tester) async {
      final api = FakeApi((_) => jsonResponse({'status': 'reset'}));
      await api.run(() async {
        await pumpScreen(tester, const ForgotPasswordScreen());
        await fill(tester, 'Insira seu e-mail cadastrado', 'aluna@example.com');

        await tapText(tester, 'Enviar link');
        expect(find.textContaining('enviamos um link de redefinição', findRichText: true), findsOneWidget);
        expect(find.text('Nova tentativa em: 30 segundos'), findsOneWidget);
        expect(enabled(tester, 'Reenviar link'), isFalse);

        await tester.pump(const Duration(seconds: 31));
        expect(find.text('Você já pode reenviar o e-mail'), findsOneWidget);

        await tapText(tester, 'Reenviar link');
        expect(api.requests.length, 2);
        await tester.pump(const Duration(seconds: 31));
      });
    });

    testWidgets('erro mostra a mensagem', (tester) async {
      await FakeApi((_) => detailError('Muitas tentativas.', status: 429)).run(() async {
        await pumpScreen(tester, const ForgotPasswordScreen());
        await fill(tester, 'Insira seu e-mail cadastrado', 'a@b.com');

        await tapText(tester, 'Enviar link');

        expect(find.text('Muitas tentativas.'), findsOneWidget);
      });
    });
  });

  group('Redefinir senha (link do e-mail)', () {
    Future<void> fillPasswords(WidgetTester tester, String a, String b) async {
      await fill(tester, 'Digite sua nova senha', a);
      await fill(tester, 'Digite a nova senha novamente', b);
    }

    testWidgets('senhas diferentes não habilitam', (tester) async {
      await pumpScreen(tester, const ResetPasswordScreen(token: 'tok'));
      await fillPasswords(tester, _senha, 'Outra#123');

      expect(enabled(tester, 'Redefinir senha'), isFalse);

      // Apagar a senha limpa a confirmação
      await fill(tester, 'Digite sua nova senha', '');
      expect(find.text('Outra#123'), findsNothing);
    });

    testWidgets('sucesso leva ao login', (tester) async {
      final api = FakeApi((_) => jsonResponse({'status': 'reset'}));
      await api.run(() async {
        await pumpScreen(tester, const ResetPasswordScreen(token: 'tok-do-link'));
        await fillPasswords(tester, _senha, _senha);

        await tapText(tester, 'Redefinir senha');
        expect(find.text('Senha redefinida!'), findsOneWidget);
        expect(api.last.body, contains('tok-do-link'));

        await tapText(tester, 'Ir para o login');
        expect(find.byType(LoginScreen), findsOneWidget);
      });
    });

    testWidgets('link expirado mostra o erro', (tester) async {
      await FakeApi((_) => detailError('Esse link de redefinição expirou. Solicite um novo.'))
          .run(() async {
        await pumpScreen(tester, const ResetPasswordScreen(token: 'velho'));
        await fillPasswords(tester, _senha, _senha);

        await tapText(tester, 'Redefinir senha');
        expect(find.text('Não foi possível redefinir'), findsOneWidget);

        await tapText(tester, 'OK');
        expect(find.text('Não foi possível redefinir'), findsNothing);
      });
    });
  });

  group('Cadastro', () {
    Future<void> fillUntilCredentials(WidgetTester tester) async {
      await pumpScreen(tester, const SignupScreen());

      // Passo 1: interesses
      expect(enabled(tester, 'Avançar'), isFalse);
      await pick(tester, 'Selecione instrumento(s)...', 'Clarinete');
      await tapText(tester, 'Estudante');
      await tapText(tester, 'Avançar');

      // Passo 2: localização em cascata
      await pick(tester, 'Selecione o país onde você mora', 'Brasil');
      await pick(tester, 'Selecione o estado onde você mora', 'Santa Catarina');
      await pick(tester, 'Selecione a cidade onde você mora', 'Jaraguá do Sul');
      await tapText(tester, 'Avançar');
    }

    Future<void> fillCredentials(WidgetTester tester) async {
      await fill(tester, 'Digite seu nome', 'Aluna');
      await fill(tester, 'Digite seu e-mail', 'aluna@example.com');
      await fill(tester, 'Digite sua senha', _senha);
      await fill(tester, 'Digite sua senha novamente', _senha);
    }

    testWidgets('fluxo completo até a confirmação do e-mail', (tester) async {
      final api = FakeApi((r) {
        if (r.url.host.contains('geonames')) return geoNames(r);
        if (r.url.path.endsWith('/status')) return jsonResponse({'confirmed': true});
        return jsonResponse({'status': 'ok'}, status: 201);
      });

      await api.run(() async {
        await fillUntilCredentials(tester);
        await fillCredentials(tester);
        expect(find.text('As senhas coincidem'), findsOneWidget);
        expect(enabled(tester, 'Cadastrar'), isFalse); // falta aceitar a política

        await tester.tap(find.byType(Checkbox).last);
        await tester.pumpAndSettle();
        await tapText(tester, 'Cadastrar');

        expect(find.text('Confirme seu e-mail'), findsOneWidget);
        final signup = api.requests.firstWhere((r) => r.url.path.endsWith('/signup'));
        expect(signup.body, contains('"city":"Jaraguá do Sul"'));
        expect(signup.body, contains('"privacy_accepted":true'));

        // Reenvio libera depois da contagem
        await tester.pump(const Duration(seconds: 31));
        await tapText(tester, 'Reenviar email');
        expect(api.requests.any((r) => r.url.path.endsWith('/resend')), isTrue);

        await tapText(tester, 'Já confirmei — continuar');
        expect(find.text('Cadastro concluído!'), findsOneWidget);
        await tapText(tester, 'Ir para o login');
        expect(find.byType(LoginScreen), findsOneWidget);
      });
    });

    testWidgets('e-mail ainda não confirmado avisa', (tester) async {
      final api = FakeApi((r) {
        if (r.url.host.contains('geonames')) return geoNames(r);
        if (r.url.path.endsWith('/status')) return jsonResponse({'confirmed': false});
        return jsonResponse({'status': 'ok'}, status: 201);
      });

      await api.run(() async {
        await fillUntilCredentials(tester);
        await fillCredentials(tester);
        await tester.tap(find.byType(Checkbox).last);
        await tester.pumpAndSettle();
        await tapText(tester, 'Cadastrar');

        await tapText(tester, 'Já confirmei — continuar');
        expect(find.text('E-mail ainda não confirmado'), findsOneWidget);
        await tapText(tester, 'OK');

        // "Voltar" do último passo volta às credenciais
        await tapText(tester, 'Voltar');
        expect(find.text('Suas credenciais de acesso'), findsOneWidget);
        await tester.pump(const Duration(seconds: 31));
      });
    });

    testWidgets('validações das credenciais e erro do backend', (tester) async {
      final api = FakeApi((r) => r.url.host.contains('geonames')
          ? geoNames(r)
          : detailError('Esse e-mail já está cadastrado.', status: 409));

      await api.run(() async {
        await fillUntilCredentials(tester);

        await fill(tester, 'Digite seu e-mail', 'sem-arroba');
        expect(find.text('Formato de e-mail inválido'), findsOneWidget);

        await fillCredentials(tester);
        await fill(tester, 'Digite sua senha novamente', 'Diferente#1');
        expect(find.text('As senhas não coincidem'), findsOneWidget);

        await fill(tester, 'Digite sua senha novamente', _senha);
        await tester.tap(find.byType(Checkbox).last);
        await tester.pumpAndSettle();
        await tapText(tester, 'Cadastrar');

        expect(find.text('Esse e-mail já está cadastrado.'), findsOneWidget);
        expect(find.text('Suas credenciais de acesso'), findsOneWidget);
      });
    });

    testWidgets('link da política abre a política sem destaques', (tester) async {
      await FakeApi(geoNames).run(() async {
        await fillUntilCredentials(tester);

        await tester.tap(find.textContaining('Política de privacidade', findRichText: true).last);
        await tester.pumpAndSettle();

        final screen = tester.widget<PrivacyPolicyScreen>(find.byType(PrivacyPolicyScreen));
        expect(screen.highlightChanges, isFalse);
      });
    });

    testWidgets('voltar entre passos e sair do cadastro', (tester) async {
      await FakeApi(geoNames).run(() async {
        await fillUntilCredentials(tester);

        await tapText(tester, 'Voltar');
        expect(find.text('Sua localização'), findsOneWidget);
        await tapText(tester, 'Voltar');
        expect(find.text('Seus interesses na música'), findsOneWidget);

        await goBack(tester);
        expect(find.byType(WelcomeScreen), findsOneWidget);
      });
    });
  });
}
