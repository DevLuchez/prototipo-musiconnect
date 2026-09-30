import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/models/opportunity_model.dart';
import 'data/models/providers/auth_service.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/reset_password_screen.dart';
import 'presentation/screens/auth/welcome_screen.dart';
import 'presentation/screens/map_explorer_screen.dart';
import 'presentation/screens/matcher_screen.dart';
import 'presentation/screens/profile/profile_screen.dart';
import 'presentation/widgets/auth/auth_common.dart';

/// Chave global do Navigator — o deep link de confirmação de e-mail pode
/// chegar a qualquer momento (app em qualquer tela, ou recém-aberto por
/// causa do link), então a navegação em resposta a ele precisa de um
/// contexto que não depende de qual widget está montado no momento.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const MusicConnectApp());
}

class MusicConnectApp extends StatefulWidget {
  const MusicConnectApp({super.key});

  @override
  State<MusicConnectApp> createState() => _MusicConnectAppState();
}

class _MusicConnectAppState extends State<MusicConnectApp> {
  final _appLinks = AppLinks();
  final _authService = AuthService();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Link de confirmação de e-mail: musiconnect://confirm?token=...
    // (esquema customizado — sem domínio próprio verificado, Universal/App
    // Links não são possíveis; ver AndroidManifest.xml/Info.plist).
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleIncomingLink);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    if (uri.scheme != 'musiconnect') return;
    final token = uri.queryParameters['token'];
    if (token == null) return;

    switch (uri.host) {
      case 'confirm':
        await _handleConfirmLink(token);
      case 'reset-password':
        _handleResetPasswordLink(token);
    }
  }

  Future<void> _handleConfirmLink(String token) async {
    final confirmed = await _authService.confirm(token);
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AuthDialog.message(
        title: confirmed ? 'Cadastro concluído!' : 'Link inválido',
        message: confirmed
            ? 'Seu usuário foi cadastrado com sucesso. Faça login para continuar.'
            : 'Esse link de confirmação não é mais válido. Tente reenviar o e-mail pelo app.',
        primaryLabel: confirmed ? 'Ir para o login' : 'OK',
        onPrimary: () {
          Navigator.of(context).pop();
          if (confirmed) {
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
        },
      ),
    );
  }

  // A validade do token (existe? não expirou?) só é checada quando o
  // usuário efetivamente envia a nova senha — a tela mostra o erro do
  // backend nesse momento, sem precisar de uma checagem antecipada aqui.
  void _handleResetPasswordLink(String token) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => ResetPasswordScreen(token: token)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'MusiConnect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFDF2881),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: _AuthGate(authService: _authService),
    );
  }
}

/// Decide a tela inicial com base na sessão persistida localmente: valida
/// o token salvo (se houver) contra o backend e já abre direto em
/// [MainNavigation] se ainda for válido — sem exigir login de novo a cada
/// abertura do app.
class _AuthGate extends StatelessWidget {
  final AuthService authService;
  const _AuthGate({required this.authService});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthUser?>(
      future: authService.getCurrentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: AuthLogo(fontSize: 26)),
          );
        }
        final user = snapshot.data;
        return user != null ? MainNavigation(user: user) : const WelcomeScreen();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  final AuthUser user;
  const MainNavigation({super.key, required this.user});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 1; // começa na aba Mapa

  // Pedido para a aba Mapa focar numa oportunidade (pino da instituição ou
  // marcador da cidade) — vindo do botão "Ver no mapa". O mapa zera depois
  // de atender.
  final ValueNotifier<OpportunityModel?> _mapFocusRequest = ValueNotifier(null);

  late final AnimationController _iconPulse;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();
    _iconPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _iconScale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _iconPulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _iconPulse.dispose();
    _mapFocusRequest.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  Widget _buildPlaceholder(String tabName) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_rounded, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'Aba $tabName ainda não desenvolvida.',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[500],
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      _buildPlaceholder('Dashboard'),
      MapExplorerScreen(user: widget.user, focusRequest: _mapFocusRequest),
      MatcherScreen(
        user: widget.user,
        onSwitchToMap: (opportunity) {
          setState(() => _selectedIndex = 1);
          _mapFocusRequest.value = opportunity;
        },
      ),
      ProfileScreen(user: widget.user),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      // ── Header global ──────────────────────────────────────────
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            // Ícone hambúrguer
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.black87),
              tooltip: 'Menu',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Menu lateral em breve!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            // Logo centralizada — mesmo estilo (preto + rosa) das telas
            // iniciais, em vez do texto em gradiente que só era usado aqui.
            title: const AuthLogo(fontSize: 20),
            centerTitle: true,
            // Ícone musical animado
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: ScaleTransition(
                  scale: _iconScale,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Conteúdo das abas ──────────────────────────────────────
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),

      // ── Barra de navegação inferior ────────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFFEC4899),
          unselectedItemColor: Colors.grey[500],
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          elevation: 0,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.location_on_rounded),
              label: 'Mapa',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_rounded),
              label: 'Matcher',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}