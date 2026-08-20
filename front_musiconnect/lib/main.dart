import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'presentation/screens/map_explorer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const MusicConnectApp());
}

class MusicConnectApp extends StatelessWidget {
  const MusicConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MusiConnect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 1; // começa na aba Mapa

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
      const MapExplorerScreen(),
      _buildPlaceholder('Matcher'),
      _buildPlaceholder('Perfil'),
    ];

    return Scaffold(
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
            // Logo centralizada
            title: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'MusiConnect',
                style: TextStyle(
                  color: Colors.white, // masked by shader
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  letterSpacing: 0.3,
                ),
              ),
            ),
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