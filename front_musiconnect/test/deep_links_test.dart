import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/core/deep_links.dart';

void main() {
  group('DeepLink.parse', () {
    test('link https de confirmação do e-mail', () {
      final link = DeepLink.parse(
          Uri.parse('https://musiconnect.app.br/confirmar?token=abc'));
      expect(link?.action, DeepLinkAction.confirmEmail);
      expect(link?.token, 'abc');
    });

    test('link https de redefinição de senha', () {
      final link = DeepLink.parse(
          Uri.parse('https://musiconnect.app.br/redefinir-senha?token=abc'));
      expect(link?.action, DeepLinkAction.resetPassword);
      expect(link?.token, 'abc');
    });

    test('links antigos musiconnect:// continuam funcionando', () {
      expect(DeepLink.parse(Uri.parse('musiconnect://confirm?token=abc'))?.action,
          DeepLinkAction.confirmEmail);
      expect(
          DeepLink.parse(Uri.parse('musiconnect://reset-password?token=abc'))?.action,
          DeepLinkAction.resetPassword);
    });

    test('ignora links sem token, de outro domínio ou outro caminho', () {
      expect(DeepLink.parse(Uri.parse('https://musiconnect.app.br/confirmar')), isNull);
      expect(DeepLink.parse(Uri.parse('https://outro.com/confirmar?token=abc')), isNull);
      expect(DeepLink.parse(Uri.parse('https://musiconnect.app.br/outra?token=abc')),
          isNull);
    });
  });
}
