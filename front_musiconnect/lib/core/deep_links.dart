/// Links que abrem o app vindos dos e-mails.
///
/// Atuais: https://musiconnect.app.br/confirmar?token=... e
/// /redefinir-senha?token=... (App Links — o Android abre o app direto,
/// verificado pelo /.well-known/assetlinks.json do backend; sem o app,
/// abrem as páginas do backend). Os antigos musiconnect://confirm e
/// musiconnect://reset-password continuam aceitos para e-mails enviados
/// antes da troca — o Gmail removia esses links, por isso a mudança.
enum DeepLinkAction { confirmEmail, resetPassword }

class DeepLink {
  static const String webHost = 'musiconnect.app.br';

  final DeepLinkAction action;
  final String token;

  const DeepLink(this.action, this.token);

  /// O que o link pede, ou `null` se não for um link do MusiConnect.
  static DeepLink? parse(Uri uri) {
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return null;

    DeepLinkAction? action;
    if (uri.scheme == 'https' && uri.host == webHost) {
      action = switch (uri.path) {
        '/confirmar' => DeepLinkAction.confirmEmail,
        '/redefinir-senha' => DeepLinkAction.resetPassword,
        _ => null,
      };
    } else if (uri.scheme == 'musiconnect') {
      action = switch (uri.host) {
        'confirm' => DeepLinkAction.confirmEmail,
        'reset-password' => DeepLinkAction.resetPassword,
        _ => null,
      };
    }
    return action == null ? null : DeepLink(action, token);
  }
}
