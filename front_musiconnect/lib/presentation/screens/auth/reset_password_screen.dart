import 'package:flutter/material.dart';
import '../../../data/models/providers/auth_service.dart';
import '../../widgets/auth/auth_common.dart';
import 'login_screen.dart';

/// Tela "Definir nova senha" — aberta pelo deep link
/// `musiconnect://reset-password?token=...` do e-mail de redefinição.
/// Mesmo padrão de senha/confirmação do cadastro (checklist de força +
/// aviso de "as senhas coincidem").
class ResetPasswordScreen extends StatefulWidget {
  final String token;
  const ResetPasswordScreen({super.key, required this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _submitting = false;

  bool get _passwordValid => AuthPasswordRequirements.isValid(_passwordController.text);
  bool get _passwordsMatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _confirmPasswordController.text == _passwordController.text;
  bool get _formValid => _passwordValid && _passwordsMatch;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  void _onPasswordChanged() {
    if (_passwordController.text.isEmpty && _confirmPasswordController.text.isNotEmpty) {
      _confirmPasswordController.clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _confirmPasswordController.removeListener(_onChanged);
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await _authService.resetPassword(
        token: widget.token,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      _showSuccessDialog();
    } on AuthException catch (e) {
      if (!mounted) return;
      _showErrorDialog(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AuthDialog.message(
        title: 'Senha redefinida!',
        message: 'Sua senha foi alterada com sucesso. Faça login com a nova senha.',
        primaryLabel: 'Ir para o login',
        onPrimary: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        },
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AuthDialog.message(
        title: 'Não foi possível redefinir',
        message: message,
        primaryLabel: 'OK',
        onPrimary: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Center(child: AuthLogo(fontSize: 20)),
                const SizedBox(height: 24),
                const AuthImagePlaceholder(
                  height: 180,
                  icon: Icons.lock_reset_rounded,
                  iconSize: 56,
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Defina uma nova senha',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: kAuthTextDark,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Escolha uma nova senha pra continuar acessando sua conta.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
                  ),
                ),
                const SizedBox(height: 24),
                AuthTextField(
                  label: 'Nova senha',
                  hint: 'Digite sua nova senha',
                  controller: _passwordController,
                  isPassword: true,
                  required: true,
                  helper: AuthPasswordRequirements(password: _passwordController.text),
                ),
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Confirme a nova senha',
                  hint: _passwordController.text.isEmpty
                      ? 'Digite a nova senha primeiro'
                      : 'Digite a nova senha novamente',
                  controller: _confirmPasswordController,
                  isPassword: true,
                  required: true,
                  enabled: _passwordController.text.isNotEmpty,
                  helper: _confirmPasswordController.text.isEmpty
                      ? null
                      : Text(
                          _passwordsMatch
                              ? 'As senhas coincidem'
                              : 'As senhas não coincidem',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _passwordsMatch
                                ? const Color(0xFF16A34A)
                                : Colors.red,
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: AuthPrimaryButton(
                    label: 'Redefinir senha',
                    loading: _submitting,
                    onPressed: _formValid ? _submit : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
