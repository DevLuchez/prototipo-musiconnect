import 'package:flutter/material.dart';
import '../../../data/models/providers/auth_service.dart';
import '../../../main.dart';
import '../../widgets/auth/auth_common.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';
import 'welcome_screen.dart';

/// Tela de Login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  String? _loginError;

  bool get _loginValid =>
      _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onFieldsChanged);
    _passwordController.addListener(_onFieldsChanged);
  }

  void _onFieldsChanged() {
    // Limpa o erro assim que o usuário mexe nos campos de novo — evita
    // deixar uma mensagem de erro desatualizada na tela.
    if (_loginError != null) {
      setState(() => _loginError = null);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _emailController.removeListener(_onFieldsChanged);
    _passwordController.removeListener(_onFieldsChanged);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _loginError = null;
    });
    try {
      final user = await _authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainNavigation(user: user)),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _loginError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goSignup() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }

  // Chegar aqui pelo popup de "Cadastro concluído" (após confirmar o
  // e-mail) limpa toda a pilha de navegação, deixando só o Login — sem
  // isso, o botão de voltar tentaria dar pop numa pilha vazia (tela preta).
  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    AuthBackButton(onTap: _back),
                    const Expanded(child: Center(child: AuthLogo(fontSize: 17))),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Faça Login',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: kAuthTextDark,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: Image.asset('assets/images/login.png', fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 24),
                    AuthTextField(
                      label: 'E-mail',
                      hint: 'Insira seu e-mail',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      required: true,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: 'Senha',
                      hint: 'Insira sua senha',
                      controller: _passwordController,
                      isPassword: true,
                      required: true,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Esqueci minha senha',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: kAuthPink,
                          ),
                        ),
                      ),
                    ),
                    if (_loginError != null) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          _loginError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: AuthPrimaryButton(
                        label: 'Entrar',
                        loading: _loading,
                        onPressed: _loginValid ? _login : null,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AuthFooterLink(
                      question: 'Não tem uma conta?',
                      action: 'Cadastre-se',
                      onTap: _goSignup,
                    ),
                    const SizedBox(height: 24),
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
