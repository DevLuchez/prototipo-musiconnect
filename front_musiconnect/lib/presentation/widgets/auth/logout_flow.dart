import 'package:flutter/material.dart';
import '../../../data/models/providers/auth_service.dart';
import '../../screens/auth/welcome_screen.dart';
import 'auth_common.dart';

/// "Sair da conta" — mesmo fluxo no Perfil e no menu lateral: pede
/// confirmação, invalida a sessão no backend e volta para a tela inicial
/// (limpando toda a pilha de telas).
Future<void> confirmAndLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AuthDialog.message(
      title: 'Sair da conta',
      message: 'Tem certeza que deseja sair?',
      primaryLabel: 'Sair',
      onPrimary: () => Navigator.of(dialogContext).pop(true),
      secondaryLabel: 'Cancelar',
      onSecondary: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  if (confirmed != true) return;

  await AuthService().logout();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    (route) => false,
  );
}
