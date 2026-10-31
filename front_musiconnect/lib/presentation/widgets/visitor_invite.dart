import 'package:flutter/material.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import 'auth/auth_common.dart';

/// Convites para criar conta, mostrados no modo visitante (ver
/// core/visitor_mode.dart) no lugar do que depende do perfil: match,
/// favoritos e prazos.

void openSignup(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );

void openLogin(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );

/// Popup no meio da tela (como o "Sair da conta"): convite + Criar conta /
/// Entrar. Usado quando o visitante toca em algo que precisa de conta, como
/// o coração de salvar.
Future<void> showAccountInvite(BuildContext context, {required String message}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AuthDialog.message(
      title: 'Crie sua conta',
      message: message,
      primaryLabel: 'Criar conta',
      onPrimary: () {
        Navigator.of(dialogContext).pop();
        openSignup(context);
      },
      secondaryLabel: 'Entrar',
      onSecondary: () {
        Navigator.of(dialogContext).pop();
        openLogin(context);
      },
    ),
  );
}

/// Convite no layout das listas vazias do app (ícone acima do texto), com
/// os botões Criar conta / Entrar.
class AccountInvite extends StatelessWidget {
  final IconData icon;
  final String message;

  const AccountInvite({
    super.key,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.4),
            ),
            const SizedBox(height: 16),
            const AccountInviteButtons(),
          ],
        ),
      ),
    );
  }
}

/// Botões do convite: Criar conta (principal) e Entrar.
class AccountInviteButtons extends StatelessWidget {
  const AccountInviteButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: AuthPrimaryButton(
            label: 'Criar conta',
            onPressed: () => openSignup(context),
          ),
        ),
        TextButton(
          onPressed: () => openLogin(context),
          style: TextButton.styleFrom(foregroundColor: kAuthPink),
          child: const Text(
            'Já tenho conta — Entrar',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
