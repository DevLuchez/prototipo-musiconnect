import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/auth/auth_common.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class _OnboardingPage {
  final String title;
  final String subtitle;
  final String image;

  const _OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.image,
  });
}

const _pages = [
  _OnboardingPage(
    title: 'Seu perfil, seu ritmo',
    subtitle:
        'Monte seu perfil e receba recomendações que têm tudo a ver com você.',
    image: 'assets/images/onboarding_profile.png',
  ),
  _OnboardingPage(
    title: 'Oportunidades mundiais',
    subtitle:
        'Explore o mapa interativo e descubra instituições ao redor do globo.',
    image: 'assets/images/onboarding_global.png',
  ),
  _OnboardingPage(
    title: 'Matching musical',
    subtitle:
        'Encontre oportunidades de carreira e estudo selecionadas sob medida para você.',
    image: 'assets/images/onboarding_matching.png',
  ),
];

/// Tela de Entrada: carrossel de boas-vindas (3 páginas com bolinhas) que
/// leva a Login ou Cadastro.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

// Índice inicial bem alto (múltiplo de _pages.length) pra simular um
// PageView infinito: sempre andamos pra frente (nunca voltamos ao índice
// 0), e o slide exibido é `index % _pages.length`. Assim, do último slide
// pro primeiro o carrossel continua deslizando na mesma direção, em vez
// de "voltar".
const _kInfiniteStart = 10000;

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final _controller = PageController(initialPage: _kInfiniteStart);
  int _page = _kInfiniteStart;
  Timer? _autoplayTimer;

  int get _activeDot => _page % _pages.length;

  @override
  void initState() {
    super.initState();
    _startAutoplay();
  }

  void _startAutoplay() {
    _autoplayTimer?.cancel();
    _autoplayTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _controller.animateToPage(
        _page + 1,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _goLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _goSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pages.length, (i) {
        final active = i == _activeDot;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? kAuthTextDark : Colors.grey[300],
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Center(child: AuthLogo()),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  _startAutoplay();
                },
                itemBuilder: (context, index) {
                  final page = _pages[index % _pages.length];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    // Bloco de texto+imagem centralizado como um todo na
                    // área do carrossel — a folga (quando a imagem não
                    // preenche toda a altura disponível) fica dividida
                    // igualmente acima e abaixo, em vez de empilhada só de
                    // um lado (texto-imagem ou imagem-bolinhas).
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: kAuthTextDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          page.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.grey[600],
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: Image.asset(page.image, fit: BoxFit.contain),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            _buildDots(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: AuthPrimaryButton(label: 'Faça Login', onPressed: _goLogin),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AuthOutlineButton(label: 'Cadastre-se', onPressed: _goSignup),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Entre na sua conta para continuar',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
