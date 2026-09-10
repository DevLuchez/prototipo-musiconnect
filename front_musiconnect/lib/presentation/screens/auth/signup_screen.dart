import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../data/models/providers/auth_service.dart';
import '../../../data/models/providers/geo_service.dart';
import '../../widgets/app_loading_indicator.dart';
import '../../widgets/auth/auth_common.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';

const _kStepIcons = [
  Icons.music_note_rounded,
  Icons.location_on_rounded,
  Icons.vpn_key_rounded,
  Icons.mail_outline_rounded,
];

/// Fluxo de Cadastro: 3 passos (interesses, localização, credenciais)
/// seguidos de confirmação de e-mail e tela de sucesso.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _pageController = PageController();
  int _page = 0;

  // ── Passo 1: interesses ──────────────────────────────────────
  List<String> _selectedInstruments = [];
  bool _isProfessional = false;
  bool _isStudent = false;

  // ── Passo 2: localização ─────────────────────────────────────
  final _geoService = GeoService();
  List<GeoOption> _countries = [];
  bool _countriesLoading = true;
  GeoOption? _selectedCountry;
  List<GeoOption> _states = [];
  bool _statesLoading = false;
  GeoOption? _selectedState;
  List<GeoOption> _cities = [];
  bool _citiesLoading = false;
  GeoOption? _selectedCity;

  // ── Passo 3: credenciais ─────────────────────────────────────
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _signingUp = false;

  // Passo do ícone ativo no indicador — acompanha a página atual
  // (interesses, localização, credenciais, confirmação de e-mail).
  int get _stepIndicatorIndex => _page.clamp(0, 3);

  // Validação do passo 1 (interesses) — pelo menos 1 instrumento e 1 ramo
  // de atuação são obrigatórios.
  bool get _instrumentsValid => _selectedInstruments.isNotEmpty;
  bool get _ramoValid => _isProfessional || _isStudent;
  bool get _interestsValid => _instrumentsValid && _ramoValid;

  // Validação do passo 2 (localização) — só o País é obrigatório.
  bool get _locationValid => _selectedCountry != null;

  // Validação do passo 3 (credenciais) ─────────────────────────
  bool get _nameValid => _nameController.text.trim().isNotEmpty;

  // E-mail: só valida formato aqui — a existência real é confirmada
  // depois, no passo "Confirme seu e-mail" (não dá pra provar isso só no
  // campo, sem enviar um e-mail de verdade).
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  bool get _emailValid => _emailRegex.hasMatch(_emailController.text.trim());
  bool get _emailTouchedInvalid =>
      _emailController.text.isNotEmpty && !_emailValid;

  bool get _passwordValid => AuthPasswordRequirements.isValid(_passwordController.text);

  bool get _passwordsMatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _confirmPasswordController.text == _passwordController.text;

  bool get _credentialsValid =>
      _nameValid && _emailValid && _passwordValid && _passwordsMatch;

  @override
  void initState() {
    super.initState();
    _loadCountries();
    // Reconstrói a tela a cada mudança nesses campos — precisamos disso
    // pro medidor de força da senha, o aviso de confirmação e a
    // habilitação do botão "Cadastrar" reagirem em tempo real.
    _nameController.addListener(_onCredentialsChanged);
    _emailController.addListener(_onCredentialsChanged);
    _passwordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onCredentialsChanged);
  }

  void _onCredentialsChanged() => setState(() {});

  void _onPasswordChanged() {
    // Sem senha, o campo de confirmação não faz sentido — limpa e
    // desliga (a UI também desabilita o campo nesse caso).
    if (_passwordController.text.isEmpty &&
        _confirmPasswordController.text.isNotEmpty) {
      _confirmPasswordController.clear();
    }
    setState(() {});
  }

  Future<void> _loadCountries() async {
    setState(() => _countriesLoading = true);
    final countries = await _geoService.fetchCountries();
    if (!mounted) return;
    setState(() {
      _countries = countries;
      _countriesLoading = false;
    });
  }

  Future<void> _onCountrySelected(GeoOption? country) async {
    setState(() {
      _selectedCountry = country;
      // Troca de país invalida estado/cidade já escolhidos.
      _selectedState = null;
      _selectedCity = null;
      _states = [];
      _cities = [];
    });
    if (country?.countryCode == null) return;
    setState(() => _statesLoading = true);
    final states = await _geoService.fetchStates(country!.countryCode!);
    if (!mounted || country != _selectedCountry) return;
    setState(() {
      _states = states;
      _statesLoading = false;
    });
  }

  Future<void> _onStateSelected(GeoOption? state) async {
    setState(() {
      _selectedState = state;
      // Troca de estado invalida a cidade já escolhida.
      _selectedCity = null;
      _cities = [];
    });
    if (state?.adminCode1 == null || _selectedCountry?.countryCode == null) return;
    setState(() => _citiesLoading = true);
    final cities = await _geoService.fetchCities(
      _selectedCountry!.countryCode!,
      state!.adminCode1!,
    );
    if (!mounted || state != _selectedState) return;
    setState(() {
      _cities = cities;
      _citiesLoading = false;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.removeListener(_onCredentialsChanged);
    _emailController.removeListener(_onCredentialsChanged);
    _passwordController.removeListener(_onPasswordChanged);
    _confirmPasswordController.removeListener(_onCredentialsChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  void _back() {
    if (_page == 0) {
      Navigator.of(context).pop();
    } else {
      _goToPage(_page - 1);
    }
  }

  // Botão de voltar do HEADER (ícone circular) — em qualquer passo do
  // cadastro, sempre volta pra tela de Entrada, diferente do "Voltar" do
  // rodapé, que navega um passo por vez dentro do próprio wizard.
  void _backToWelcome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  // Cria o usuário (pendente de confirmação) no backend e dispara o
  // e-mail de confirmação — só então avança pro passo de confirmação.
  Future<void> _submitSignup() async {
    setState(() => _signingUp = true);
    try {
      await _authService.signup(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        instruments: _selectedInstruments,
        isProfessional: _isProfessional,
        isStudent: _isStudent,
        country: _selectedCountry?.name,
        state: _selectedState?.name,
        city: _selectedCity?.name,
      );
      if (!mounted) return;
      _goToPage(3);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _signingUp = false);
    }
  }

  Future<void> _resendConfirmationEmail() async {
    try {
      await _authService.resend(_emailController.text.trim());
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // Chamado pelo botão "Já confirmei" — consulta o status real no
  // backend (o usuário pode ter confirmado em outro dispositivo, ou o
  // deep link pode não ter sido capturado nesta sessão).
  Future<void> _checkConfirmationAndProceed() async {
    final confirmed = await _authService.isConfirmed(_emailController.text.trim());
    if (!mounted) return;
    if (confirmed) {
      _showSignupSuccessDialog();
    } else {
      showDialog(
        context: context,
        builder: (_) => AuthDialog.message(
          title: 'E-mail ainda não confirmado',
          message:
              'Acesse sua caixa de e-mails e clique no link de confirmação antes de continuar.',
          primaryLabel: 'OK',
          onPrimary: () => Navigator.of(context).pop(),
        ),
      );
    }
  }

  // Chamado quando o deep link `musiconnect://confirm` confirma o
  // e-mail com o app aberto nesta mesma tela.
  void _showSignupSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AuthDialog.message(
        title: 'Cadastro concluído!',
        message: 'Seu usuário foi cadastrado com sucesso. Faça login para continuar.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      AuthBackButton(onTap: _backToWelcome),
                      const Expanded(child: Center(child: AuthLogo(fontSize: 17))),
                      const SizedBox(width: 36),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Cadastre-se',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: kAuthTextDark,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SignupStepper(currentStep: _stepIndicatorIndex),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildInterestsStep(),
                  _buildLocationStep(),
                  _buildCredentialsStep(),
                  _buildEmailConfirmStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Passo 1: Seus interesses na música ───────────────────────
  Widget _buildInterestsStep() {
    return _StepScaffold(
      title: 'Seus interesses na música',
      footer: _stepFooter(
        onNext: () => _goToPage(1),
        enabled: _interestsValid,
      ),
      children: [
        const SectionLabel(
          title: 'Instrumentos',
          subtitle:
              'Selecione o(s) instrumento(s) que você tem experiência ou interesse em aprender.',
          required: true,
        ),
        const SizedBox(height: 8),
        AuthMultiSelectField(
          hint: 'Selecione instrumento(s)...',
          options: kInstrumentOptions,
          selected: _selectedInstruments,
          onChanged: (v) => setState(() => _selectedInstruments = v),
        ),
        const SizedBox(height: 20),
        const SectionLabel(
          title: 'Ramo de atuação',
          subtitle:
              'Selecione o(s) ramo(s) onde você deseja encontrar oportunidades como musicista.',
          required: true,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            CheckRow(
              label: 'Profissional',
              value: _isProfessional,
              onChanged: (v) => setState(() => _isProfessional = v),
            ),
            const SizedBox(width: 24),
            CheckRow(
              label: 'Estudante',
              value: _isStudent,
              onChanged: (v) => setState(() => _isStudent = v),
            ),
          ],
        ),
      ],
    );
  }

  // ── Passo 2: Sua localização ─────────────────────────────────
  Widget _buildLocationStep() {
    return _StepScaffold(
      title: 'Sua localização',
      subtitle:
          'Informe sua localização para que possamos encontrar as oportunidades ao seu redor.',
      footer: _stepFooter(
        onNext: () => _goToPage(2),
        enabled: _locationValid,
      ),
      children: [
        AuthSingleSelectField<GeoOption>(
          label: 'País',
          hint: 'Selecione o país onde você mora',
          required: true,
          options: _countries,
          selected: _selectedCountry,
          displayString: (o) => o.name,
          loading: _countriesLoading,
          onChanged: _onCountrySelected,
        ),
        const SizedBox(height: 16),
        AuthSingleSelectField<GeoOption>(
          label: 'Estado',
          hint: _selectedCountry == null
              ? 'Selecione o país primeiro'
              : 'Selecione o estado onde você mora',
          options: _states,
          selected: _selectedState,
          displayString: (o) => o.name,
          enabled: _selectedCountry != null,
          loading: _statesLoading,
          onChanged: _onStateSelected,
        ),
        const SizedBox(height: 16),
        AuthSingleSelectField<GeoOption>(
          label: 'Cidade',
          hint: _selectedState == null
              ? 'Selecione o estado primeiro'
              : 'Selecione a cidade onde você mora',
          options: _cities,
          selected: _selectedCity,
          displayString: (o) => o.name,
          enabled: _selectedState != null,
          loading: _citiesLoading,
          onChanged: (v) => setState(() => _selectedCity = v),
        ),
      ],
    );
  }

  // ── Passo 3: Suas credenciais de acesso ──────────────────────
  Widget _buildCredentialsStep() {
    return _StepScaffold(
      title: 'Suas credenciais de acesso',
      subtitle: 'Informe e-mail e senha para se autenticar no MusiConnect.',
      footer: _stepFooter(
        nextLabel: 'Cadastrar',
        onNext: _submitSignup,
        enabled: _credentialsValid,
        loading: _signingUp,
      ),
      children: [
        AuthTextField(
          label: 'Nome de usuário',
          hint: 'Digite seu nome',
          controller: _nameController,
          required: true,
        ),
        const SizedBox(height: 16),
        AuthTextField(
          label: 'E-mail',
          hint: 'Digite seu e-mail',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          required: true,
          helper: _emailTouchedInvalid
              ? const Text(
                  'Formato de e-mail inválido',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 16),
        AuthTextField(
          label: 'Senha',
          hint: 'Digite sua senha',
          controller: _passwordController,
          isPassword: true,
          required: true,
          helper: AuthPasswordRequirements(password: _passwordController.text),
        ),
        const SizedBox(height: 16),
        AuthTextField(
          label: 'Confirme a Senha',
          hint: _passwordController.text.isEmpty
              ? 'Digite a senha primeiro'
              : 'Digite sua senha novamente',
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
                    color: _passwordsMatch ? const Color(0xFF16A34A) : Colors.red,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _stepFooter({
    required VoidCallback onNext,
    String nextLabel = 'Avançar',
    bool enabled = true,
    bool loading = false,
  }) {
    // No primeiro passo, "Voltar" sai do cadastro — fica desabilitado e
    // cinza. Nos demais, volta um passo dentro do wizard — habilitado e
    // rosa.
    final isFirstStep = _page == 0;
    return Row(
      children: [
        TextButton(
          onPressed: isFirstStep ? null : _back,
          style: TextButton.styleFrom(
            foregroundColor: isFirstStep ? Colors.grey[400] : kAuthPink,
            disabledForegroundColor: Colors.grey[400],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left_rounded, size: 18),
              Text('Voltar', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const Spacer(),
        // "Avançar" segue o estilo do botão "Cadastre-se" da tela de
        // Entrada (contorno); "Cadastrar" (último passo) continua
        // preenchido, como confirmação final.
        if (nextLabel == 'Avançar')
          AuthOutlineButton(
            label: nextLabel,
            onPressed: enabled ? onNext : null,
            trailingIcon: Icons.chevron_right_rounded,
          )
        else
          AuthPrimaryButton(
            label: nextLabel,
            onPressed: enabled ? onNext : null,
            loading: loading,
          ),
      ],
    );
  }

  // ── Passo 4: Confirme seu e-mail ─────────────────────────────
  Widget _buildEmailConfirmStep() {
    return _EmailConfirmStep(
      email: _emailController.text.isEmpty
          ? 'seuemail@gmail.com'
          : _emailController.text,
      onResend: _resendConfirmationEmail,
      onCheckConfirmed: _checkConfirmationAndProceed,
      onBack: () => _goToPage(2),
    );
  }
}

/// Layout comum aos passos com cabeçalho (título+subtítulo), conteúdo
/// rolável e rodapé fixo com os botões de navegação.
class _StepScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget footer;

  const _StepScaffold({
    required this.title,
    this.subtitle,
    required this.children,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kAuthTextDark,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: footer,
        ),
        AuthFooterLink(
          question: 'Já tem uma conta?',
          action: 'Faça login',
          onTap: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Indicador de progresso com 3 ícones conectados (música, localização,
/// chave), no estilo do protótipo: concluído = preenchido com check;
/// atual = anel rosa; futuro = cinza.
class _SignupStepper extends StatelessWidget {
  final int currentStep;
  const _SignupStepper({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _kStepIcons.length; i++) ...[
          _buildCircle(i),
          if (i < _kStepIcons.length - 1) _buildLine(i),
        ],
      ],
    );
  }

  Widget _buildCircle(int index) {
    if (index < currentStep) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(color: kAuthPink, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
      );
    }
    if (index == currentStep) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: kAuthPink, width: 2.5),
        ),
        child: Icon(_kStepIcons[index], size: 17, color: kAuthPink),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey[300]!, width: 1.5),
      ),
      child: Icon(_kStepIcons[index], size: 16, color: Colors.grey[400]),
    );
  }

  Widget _buildLine(int index) {
    return Container(
      width: 28,
      height: 2,
      color: index < currentStep ? kAuthPink : Colors.grey[300],
    );
  }
}

/// Passo 4: confirmação de e-mail, com reenvio e contagem regressiva.
class _EmailConfirmStep extends StatefulWidget {
  final String email;
  final Future<void> Function() onResend;
  final Future<void> Function() onCheckConfirmed;
  final VoidCallback onBack;

  const _EmailConfirmStep({
    required this.email,
    required this.onResend,
    required this.onCheckConfirmed,
    required this.onBack,
  });

  @override
  State<_EmailConfirmStep> createState() => _EmailConfirmStepState();
}

class _EmailConfirmStepState extends State<_EmailConfirmStep> {
  static const _cooldownSeconds = 30;
  int _secondsLeft = _cooldownSeconds;
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _secondsLeft = _cooldownSeconds;
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

  void _handleResend() {
    _startCooldown();
    widget.onResend();
  }

  Future<void> _handleCheckConfirmed() async {
    setState(() => _checking = true);
    await widget.onCheckConfirmed();
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft == 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const AuthImagePlaceholder(
            height: 220,
            icon: Icons.mark_email_read_outlined,
            iconSize: 64,
          ),
          const SizedBox(height: 24),
          const Text(
            'Confirme seu e-mail',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kAuthTextDark,
            ),
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
              children: [
                const TextSpan(text: 'Nós enviamos uma confirmação no e-mail '),
                TextSpan(
                  text: widget.email,
                  style: const TextStyle(color: kAuthPink),
                ),
                const TextSpan(
                  text: '. Acesse sua caixa de e-mails e clique no link de '
                      'confirmação para continuar.',
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          AuthPrimaryButton(
            label: 'Reenviar email',
            onPressed: canResend ? _handleResend : null,
          ),
          const SizedBox(height: 10),
          Text(
            canResend
                ? 'Você já pode reenviar o e-mail'
                : 'Nova tentativa em: $_secondsLeft segundos',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: _checking ? null : _handleCheckConfirmed,
            child: _checking
                ? const AppLoadingIndicator(size: 14)
                : const Text(
                    'Já confirmei — continuar',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: kAuthPink,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onBack,
              style: TextButton.styleFrom(foregroundColor: kAuthPink),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, size: 18),
                  Text('Voltar', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

