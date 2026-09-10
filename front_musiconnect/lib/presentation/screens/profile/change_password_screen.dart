import 'package:flutter/material.dart';
import '../../../data/models/providers/auth_service.dart';
import '../../widgets/auth/auth_common.dart';

/// Troca de senha estando logado — diferente do fluxo "Esqueci minha
/// senha", pede a senha atual em vez de depender de um link por e-mail.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  String? _error;

  bool get _passwordValid => AuthPasswordRequirements.isValid(_newPasswordController.text);
  bool get _passwordsMatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _confirmPasswordController.text == _newPasswordController.text;
  bool get _formValid =>
      _currentPasswordController.text.isNotEmpty && _passwordValid && _passwordsMatch;

  @override
  void initState() {
    super.initState();
    _currentPasswordController.addListener(_onChanged);
    _newPasswordController.addListener(_onChanged);
    _confirmPasswordController.addListener(_onChanged);
  }

  void _onChanged() {
    if (_error != null) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _authService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha alterada com sucesso.')),
      );
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
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
                      'Trocar senha',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: kAuthTextDark,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AuthTextField(
                      label: 'Senha atual',
                      hint: 'Insira sua senha atual',
                      controller: _currentPasswordController,
                      isPassword: true,
                      required: true,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: 'Nova senha',
                      hint: 'Digite a nova senha',
                      controller: _newPasswordController,
                      isPassword: true,
                      required: true,
                      helper: AuthPasswordRequirements(password: _newPasswordController.text),
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: 'Confirme a nova senha',
                      hint: _newPasswordController.text.isEmpty
                          ? 'Digite a senha primeiro'
                          : 'Digite a senha novamente',
                      controller: _confirmPasswordController,
                      isPassword: true,
                      required: true,
                      enabled: _newPasswordController.text.isNotEmpty,
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
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: AuthPrimaryButton(
                        label: 'Salvar',
                        loading: _loading,
                        onPressed: _formValid ? _submit : null,
                      ),
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
