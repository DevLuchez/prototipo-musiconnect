import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/app_update_service.dart';
import 'auth/auth_common.dart';

bool _promptOpen = false;

/// Confere se há versão nova e, se houver, mostra o aviso — um por vez
/// (abrir o app, voltar a ele e tocar na notificação podem coincidir).
Future<void> checkForAppUpdate(
  GlobalKey<NavigatorState> navigatorKey, {
  AppUpdateService? service,
}) async {
  if (_promptOpen) return;
  final update = await (service ?? AppUpdateService()).check();
  final context = navigatorKey.currentContext;
  if (update == null || _promptOpen || context == null || !context.mounted) return;
  _promptOpen = true;
  // O aviso não fecha sozinho, mas uma troca de tela que limpa a pilha
  // (ex: link do e-mail) o remove — aí a próxima verificação mostra de novo.
  await showAppUpdatePrompt(context, update);
  _promptOpen = false;
}

/// Aviso de versão nova: o app só segue depois de atualizar — o aviso não
/// fecha, nem pelo voltar. "Atualizar" abre o download no navegador; a
/// pessoa instala por cima e continua conectada.
Future<void> showAppUpdatePrompt(BuildContext context, AppUpdate update) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AuthDialog.message(
        title: 'Atualize o MusiConnect',
        message: 'A versão ${update.version} já está disponível, com melhorias e '
            'correções. Baixe e instale por cima para continuar usando — '
            'você continua conectado e não perde nada.',
        primaryLabel: 'Atualizar',
        onPrimary: () => launchUrl(
          Uri.parse(update.downloadUrl),
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false),
      ),
    ),
  );
}
