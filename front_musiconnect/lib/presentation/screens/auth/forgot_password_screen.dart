import 'dart:async';

import 'package:flutter/material.dart';
import '../../../data/models/providers/auth_service.dart';
import '../../widgets/auth/auth_common.dart';

/// Tela "Esqueci minha senha": pede o e-mail, envia o link de
/// redefinição (via backend real) e mostra um estado de "e-mail
/// enviado" com opção de reenviar — mesmo padrão da confirmação de
/// cadastro.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _sending = false;
  bool _sent = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  bool get _emailValid => _emailRegex.hasMatch(_emailController.text.trim());

  static const _cooldownSeconds = 30;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _emailController.removeListener(_onChanged);
    _emailController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _secondsLeft = _cooldownSeconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      await _authService.forgotPassword(_emailController.text.trim());
      if (!mounted) return;
      setState(() => _sent = true);
      _startCooldown();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft == 0;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    AuthBackButton(onTap: () => Navigator.of(context).pop()),
                    const Expanded(child: Center(child: AuthLogo(fontSize: 17))),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Esqueci minha senha',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: kAuthTextDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Informe seu e-mail cadastrado e enviaremos um link '
                      'para redefinir sua senha.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: Image.asset(
                        'assets/images/forgot_password.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AuthTextField(
                      label: 'E-mail',
                      hint: 'Insira seu e-mail cadastrado',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      required: true,
                    ),
                    const SizedBox(height: 20),
                    if (!_sent)
                      SizedBox(
                        width: double.infinity,
                        child: AuthPrimaryButton(
                          label: 'Enviar link',
                          loading: _sending,
                          onPressed: _emailValid ? _submit : null,
                        ),
                      )
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(
                                  text: 'Se esse e-mail estiver cadastrado, enviamos um '
                                      'link de redefinição para '),
                              TextSpan(
                                text: _emailController.text.trim(),
                                style: const TextStyle(color: kAuthPink),
                              ),
                              const TextSpan(
                                  text: '. Acesse sua caixa de e-mails e clique no link.'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: AuthOutlineButton(
                          label: 'Reenviar link',
                          onPressed: canResend && !_sending ? _submit : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          canResend
                              ? 'Você já pode reenviar o e-mail'
                              : 'Nova tentativa em: $_secondsLeft segundos',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    AuthFooterLink(
                      question: 'Lembrou a senha?',
                      action: 'Faça login',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
