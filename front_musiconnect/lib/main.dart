import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/models/providers/auth_service.dart';
import 'data/models/providers/favorites_service.dart';
import 'data/models/providers/match_count_service.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/reset_password_screen.dart';
import 'presentation/screens/auth/welcome_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/favorites_screens.dart';
import 'presentation/screens/help_screen.dart';
import 'presentation/screens/map_explorer_screen.dart';
import 'presentation/screens/matcher_screen.dart';
import 'presentation/screens/profile/profile_screen.dart';
import 'presentation/widgets/auth/auth_common.dart';
import 'presentation/widgets/auth/logout_flow.dart';

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
  int _selectedIndex = _homeTab; // começa na aba Início

  // Usuário logado, atualizado quando o perfil é editado — repassado às
  // abas e ao cabeçalho do menu lateral.
  late AuthUser _user = widget.user;

  // Pedido para a aba Mapa focar num pino de instituição ou marcador de
  // cidade — vindo do "Ver no mapa" ou de uma instituição favorita. O mapa
  // zera depois de atender.
  final ValueNotifier<MapFocusTarget?> _mapFocusRequest = ValueNotifier(null);

  // Pedido para o Matcher mostrar uma aba (0 = Minhas oportunidades) —
  // vindo do número de Matches do Perfil.
  final ValueNotifier<int?> _matcherTabRequest = ValueNotifier(null);

  static const int _homeTab = 0;
  static const int _mapTab = 1;
  static const int _matcherTab = 2;
  static const int _profileTab = 3;

  // Incrementado ao tocar na aba Início — a tela recarrega o resumo.
  final ValueNotifier<int> _homeRefresh = ValueNotifier(0);

  late final AnimationController _iconPulse;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();
    // Estado dos corações (salvos/favoritos) de todas as telas.
    FavoritesService.instance.load();
    // Número de Matches do Perfil.
    MatchCountService.instance.refresh(clear: true);
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
    _matcherTabRequest.dispose();
    _homeRefresh.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    // Pega oportunidades novas (scraper) desde a última consulta.
    if (index == _profileTab) MatchCountService.instance.refresh();
    if (index == _homeTab) _homeRefresh.value++;
  }

  /// Vai para o Matcher numa aba (0 = Minhas oportunidades, 1 = Todas).
  void _openMatcher(int tab) {
    setState(() => _selectedIndex = _matcherTab);
    _matcherTabRequest.value = tab;
  }

  void _onUserChanged(AuthUser user) {
    setState(() => _user = user);
    MatchCountService.instance.refresh();
  }

  /// Vai para a aba Mapa focada no alvo. Fecha antes as telas empilhadas
  /// por cima (ex: lista de favoritos aberta pelo menu lateral).
  void _focusOnMap(MapFocusTarget target) {
    final route = ModalRoute.of(context);
    if (route != null) Navigator.of(context).popUntil((r) => r == route);
    setState(() => _selectedIndex = _mapTab);
    _mapFocusRequest.value = target;
  }

  void _openSavedOpportunities() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SavedOpportunitiesScreen(
        user: _user,
        onOpenMap: (opp) => _focusOnMap(MapFocusTarget.opportunity(opp)),
      ),
    ));
  }

  void _openFavoriteInstitutions() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FavoriteInstitutionsScreen(
        onOpenMap: (place) =>
            _focusOnMap(MapFocusTarget.institution(place.osmId!)),
      ),
    ));
  }

  void _openHelp() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const HelpScreen(),
    ));
  }

  /// Item do menu lateral: fecha o menu e abre a tela.
  void _fromDrawer(VoidCallback open) {
    Navigator.of(context).pop();
    open();
  }

  /// Menu lateral (ícone hambúrguer do header): você (leva ao Perfil) e
  /// favoritos no topo; ajuda e sair embaixo. Sem contadores aqui: as
  /// quantidades aparecem nas próprias telas e no Perfil.
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        // Rolável + altura mínima da tela: o Spacer empurra ajuda/sair pro
        // rodapé, mas em tela baixa (ou fonte grande) o menu rola em vez de
        // estourar.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DrawerHeader(
                      user: _user,
                      onTap: () => _fromDrawer(() => _onItemTapped(_profileTab)),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                      child: Text(
                        'FAVORITOS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey[500],
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    _DrawerItem(
                      icon: Icons.favorite_rounded,
                      label: 'Oportunidades salvas',
                      onTap: () => _fromDrawer(_openSavedOpportunities),
                    ),
                    _DrawerItem(
                      icon: Icons.business_rounded,
                      label: 'Instituições favoritas',
                      onTap: () => _fromDrawer(_openFavoriteInstitutions),
                    ),
                    const Spacer(),
                    const SizedBox(height: 16),
                    _DrawerItem(
                      icon: Icons.help_outline_rounded,
                      label: 'Ajuda e suporte',
                      onTap: () => _fromDrawer(_openHelp),
                    ),
                    const SizedBox(height: 4),
                    // Mesmo fluxo do "Sair da conta" do Perfil. Fundo
                    // vermelho claro + ícone no vermelho escuro da "Zona de
                    // atenção" do Perfil.
                    _DrawerItem(
                      icon: Icons.logout_rounded,
                      label: 'Sair',
                      showChevron: false,
                      iconColor: Colors.red[800],
                      backgroundColor: Colors.red[50],
                      onTap: () => _fromDrawer(() => confirmAndLogout(this.context)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      DashboardScreen(
        user: _user,
        refreshRequest: _homeRefresh,
        onOpenMatcher: _openMatcher,
        onOpenMap: (opportunity) =>
            _focusOnMap(MapFocusTarget.opportunity(opportunity)),
      ),
      MapExplorerScreen(user: _user, focusRequest: _mapFocusRequest),
      MatcherScreen(
        user: _user,
        onSwitchToMap: (opportunity) =>
            _focusOnMap(MapFocusTarget.opportunity(opportunity)),
        tabRequest: _matcherTabRequest,
      ),
      ProfileScreen(
        user: _user,
        onOpenMatches: () => _openMatcher(0),
        onOpenSavedOpportunities: _openSavedOpportunities,
        onOpenFavoriteInstitutions: _openFavoriteInstitutions,
        onUserChanged: _onUserChanged,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: _buildDrawer(),
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
            // Builder: o context precisa estar abaixo do Scaffold pra
            // achar o drawer.
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.black87),
                tooltip: 'Menu',
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
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
              icon: Icon(Icons.home_rounded),
              label: 'Início',
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

/// Topo do menu lateral: inicial, nome e e-mail do usuário (mesmo círculo
/// em gradiente do Perfil, menor). Tocar leva à aba Perfil.
class _DrawerHeader extends StatelessWidget {
  final AuthUser user;
  final VoidCallback onTap;

  const _DrawerHeader({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';
    return InkWell(
      onTap: onTap,
      splashColor: kAuthPink.withOpacity(0.18),
      highlightColor: kAuthPink.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kAuthPurple, kAuthPink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kAuthTextDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  // Seta ">" — só em itens que abrem outra tela (não no "Sair").
  final bool showChevron;
  final Color? iconColor;
  // Com fundo, o item vira um bloco arredondado com margem lateral (ex: "Sair").
  final Color? backgroundColor;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showChevron = true,
    this.iconColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final background = backgroundColor;
    final tile = ListTile(
      // Com fundo, margem 16 + padding 8 = mesmos 24 dos outros itens, então
      // os ícones ficam alinhados.
      contentPadding: EdgeInsets.symmetric(horizontal: background == null ? 24 : 8),
      leading: Icon(icon, color: iconColor ?? kAuthPink, size: 22),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: kAuthTextDark,
        ),
      ),
      trailing: showChevron
          ? Icon(Icons.chevron_right_rounded, color: Colors.grey[400])
          : null,
      onTap: onTap,
    );
    if (background == null) return tile;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: tile,
      ),
    );
  }
}
