import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../widgets/auth/auth_common.dart';

/// Tutorial do primeiro acesso (pedido do coordenador da SCAR): um
/// "holofote" sobre as telas reais — a tela escurece, um elemento fica
/// iluminado e um balão explica para que ele serve.
///
/// As telas marcam os elementos com as chaves de [TutorialTargets]; o
/// [MainNavigation] mostra o [TutorialOverlay] por cima de tudo e troca de
/// aba conforme o passo.

/// Elementos que o tutorial destaca. Cada [MainNavigation] cria as suas
/// (duas navegações podem coexistir durante uma troca de tela) e as guarda
/// enquanto existir.
class TutorialKeys {
  final home = GlobalKey(debugLabel: 'tutorial:home');
  final bottomNav = GlobalKey(debugLabel: 'tutorial:bottomNav');
  final menu = GlobalKey(debugLabel: 'tutorial:menu');
  final mapSearch = GlobalKey(debugLabel: 'tutorial:mapSearch');
  final mapFilter = GlobalKey(debugLabel: 'tutorial:mapFilter');
  final mapLegend = GlobalKey(debugLabel: 'tutorial:mapLegend');
  final matcherTabs = GlobalKey(debugLabel: 'tutorial:matcherTabs');
  final matcherExplainer = GlobalKey(debugLabel: 'tutorial:matcherExplainer');
  final matcherSearch = GlobalKey(debugLabel: 'tutorial:matcherSearch');
  final profileAction = GlobalKey(debugLabel: 'tutorial:profileAction');
}

/// Disponibiliza as [TutorialKeys] da navegação para as telas das abas, que
/// marcam os seus elementos com elas.
class TutorialTargets extends InheritedWidget {
  final TutorialKeys keys;

  const TutorialTargets({super.key, required this.keys, required super.child});

  static TutorialKeys? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TutorialTargets>()?.keys;

  @override
  bool updateShouldNotify(TutorialTargets oldWidget) => keys != oldWidget.keys;
}

/// Um passo: em que aba ele acontece, o que destaca e o que diz.
class TutorialStep {
  final int tab;
  final GlobalKey Function(TutorialKeys keys) target;
  final String text;

  /// Texto para quem entrou sem conta (quando difere).
  final String? visitorText;

  const TutorialStep({
    required this.tab,
    required this.target,
    required this.text,
    this.visitorText,
  });

  String textFor({required bool visitor}) => visitor ? (visitorText ?? text) : text;
}

/// Os 10 passos — decididos com a Laura (PLANO_FINALIZACAO.md, 5.1). Só
/// elementos que sempre existem, com ou sem conta.
List<TutorialStep> tutorialSteps({
  required int homeTab,
  required int mapTab,
  required int matcherTab,
  required int profileTab,
}) =>
    [
      TutorialStep(
        tab: homeTab,
        target: (t) => t.home,
        text: 'O Início resume o que importa hoje: o seu melhor match, as '
            'oportunidades abertas por tipo e os prazos dos seus favoritos.',
        visitorText: 'O Início resume as oportunidades abertas por tipo. Com '
            'uma conta, ele mostra também o seu melhor match e os prazos dos '
            'seus favoritos.',
      ),
      TutorialStep(
        tab: homeTab,
        target: (t) => t.bottomNav,
        text: 'Navegue pelo app por aqui: Início, Mapa, Matcher e Perfil.',
      ),
      TutorialStep(
        tab: homeTab,
        target: (t) => t.menu,
        text: 'No menu ficam seus favoritos, a ajuda e a política de '
            'privacidade.',
      ),
      TutorialStep(
        tab: mapTab,
        target: (t) => t.mapSearch,
        text: 'Busque uma cidade ou uma instituição musical.',
      ),
      TutorialStep(
        tab: mapTab,
        target: (t) => t.mapFilter,
        text: 'Escolha os tipos de instituição e veja só as que têm '
            'oportunidades abertas.',
      ),
      TutorialStep(
        tab: mapTab,
        target: (t) => t.mapLegend,
        text: 'Cada cor de pino é um tipo de instituição. Pino com estrela tem '
            'oportunidades abertas.',
      ),
      TutorialStep(
        tab: matcherTab,
        target: (t) => t.matcherTabs,
        text: 'Em Minhas, as oportunidades que mais combinam com você; em '
            'Todas, todas as abertas.',
      ),
      TutorialStep(
        tab: matcherTab,
        target: (t) => t.matcherExplainer,
        text: 'Entenda o que é o match: o quanto cada oportunidade combina com '
            'o seu perfil.',
      ),
      TutorialStep(
        tab: matcherTab,
        target: (t) => t.matcherSearch,
        text: 'Busque e filtre por tipo, instrumento, local e escala de match.',
      ),
      TutorialStep(
        tab: profileTab,
        target: (t) => t.profileAction,
        text: 'Mantenha seu perfil atualizado para receber matches melhores.',
        visitorText: 'Crie sua conta para ver seus matches e guardar seus '
            'favoritos.',
      ),
    ];

const kTutorialLaterMessage =
    'Você pode ver o tutorial quando quiser em Ajuda e suporte.';
const kTutorialDoneMessage =
    'Pronto! Você pode rever o tutorial quando quiser em Ajuda e suporte.';
const kTutorialSkipMessage =
    'Você pode rever o tutorial quando quiser em Ajuda e suporte.';

/// Texto dos avisos do tutorial com "Ajuda e suporte" como link (abre a
/// tela de ajuda).
class TutorialMessage extends StatefulWidget {
  static const linkLabel = 'Ajuda e suporte';

  final String text;
  final VoidCallback onOpenHelp;

  const TutorialMessage({super.key, required this.text, required this.onOpenHelp});

  @override
  State<TutorialMessage> createState() => _TutorialMessageState();
}

class _TutorialMessageState extends State<TutorialMessage> {
  late final _link = TapGestureRecognizer()..onTap = widget.onOpenHelp;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.text.split(TutorialMessage.linkLabel);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: parts.first),
          if (parts.length > 1) ...[
            TextSpan(
              text: TutorialMessage.linkLabel,
              recognizer: _link,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
              ),
            ),
            TextSpan(text: parts.sublist(1).join(TutorialMessage.linkLabel)),
          ],
        ],
      ),
    );
  }
}

/// Pedido para rever o tutorial vindo da Ajuda (que é uma tela à parte, fora
/// da navegação principal): o [MainNavigation] escuta e começa.
final tutorialRequest = ValueNotifier<int>(0);

/// Popup da primeira entrada: "Quer aprender a usar o MusiConnect?".
Future<bool> askToStartTutorial(BuildContext context) async {
  final wants = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AuthDialog.message(
      title: 'Quer aprender a usar o MusiConnect?',
      message: 'Um passeio rápido pelas telas principais do app.',
      primaryLabel: 'Quero',
      onPrimary: () => Navigator.of(dialogContext).pop(true),
      secondaryLabel: 'Agora não',
      onSecondary: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  return wants ?? false;
}

/// O holofote: escurece a tela inteira menos o elemento do passo atual e
/// mostra o balão com o texto, o progresso e os botões (Voltar, Próximo,
/// Pular tutorial — que fecha na hora). Bloqueia os toques no app enquanto
/// aberto.
class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final TutorialKeys targets;
  final bool visitor;

  /// Troca para a aba do passo (o tutorial muda de aba sozinho).
  final ValueChanged<int> onShowTab;

  /// Acabou: [completed] = chegou ao fim (false = pulou).
  final void Function({required bool completed, required int step}) onFinish;

  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.targets,
    required this.visitor,
    required this.onShowTab,
    required this.onFinish,
  });

  @override
  State<TutorialOverlay> createState() => TutorialOverlayState();
}

class TutorialOverlayState extends State<TutorialOverlay> {
  int _index = 0;
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    // Depois da montagem: o primeiro passo troca a aba da navegação, que não
    // pode ser alterada no meio da construção da tela.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show(0);
    });
  }

  TutorialStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  /// Vai para o passo [index]: troca de aba, espera a tela se ajustar e mede
  /// onde está o elemento.
  Future<void> _show(int index) async {
    setState(() {
      _index = index;
      _hole = null;
    });
    widget.onShowTab(_step.tab);
    // A troca de aba (e a rolagem até o elemento) precisa de alguns quadros.
    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted || _index != index) return;
      final target = _step.target(widget.targets).currentContext;
      if (target == null || !target.mounted) continue;
      if (attempt == 0) {
        // Rola até o elemento, se estiver fora da tela (ex: Editar perfil).
        await Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250));
        continue;
      }
      final rect = _rectOf(target);
      if (rect != null) {
        setState(() => _hole = rect.inflate(6));
        return;
      }
    }
    // Elemento não encontrado: segue sem holofote, só com o balão.
    if (mounted && _index == index) setState(() => _hole = Rect.zero);
  }

  Rect? _rectOf(BuildContext target) {
    final box = target.findRenderObject();
    final overlay = context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox || !box.hasSize || !box.attached) {
      return null;
    }
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return topLeft & box.size;
  }

  void _next() {
    if (_isLast) {
      widget.onFinish(completed: true, step: _index + 1);
    } else {
      _show(_index + 1);
    }
  }

  void skip() => widget.onFinish(completed: false, step: _index + 1);

  /// Passo anterior — botão "Voltar" e o voltar do Android (no primeiro
  /// passo, encerra o tutorial).
  void back() {
    if (_index == 0) {
      skip();
    } else {
      _show(_index - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final hole = _hole;
    return Stack(
      children: [
        // Bloqueia toques no app e escurece em volta do elemento.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(painter: _SpotlightPainter(hole)),
          ),
        ),
        if (hole != null) _balloon(size, hole),
      ],
    );
  }

  Widget _balloon(Size size, Rect hole) {
    final balloon = _Balloon(
      text: _step.textFor(visitor: widget.visitor),
      progress: '${_index + 1} de ${widget.steps.length}',
      nextLabel: _isLast ? 'Concluir' : 'Próximo',
      onNext: _next,
      onBack: _index == 0 ? null : back,
      onSkip: skip,
    );
    const margin = 16.0;
    final padding = MediaQuery.of(context).padding;
    // Elemento que ocupa quase a tela toda (ex: o Início): balão no meio.
    if (hole == Rect.zero || hole.height > size.height * 0.5) {
      return Positioned(left: margin, right: margin, top: size.height * 0.35, child: balloon);
    }
    // Elemento na metade de baixo: balão acima dele; senão, abaixo.
    if (hole.center.dy > size.height / 2) {
      return Positioned(
        left: margin,
        right: margin,
        bottom: (size.height - hole.top + 12).clamp(padding.bottom + margin, size.height),
        child: balloon,
      );
    }
    return Positioned(
      left: margin,
      right: margin,
      top: (hole.bottom + 12).clamp(padding.top + margin, size.height),
      child: balloon,
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  const _SpotlightPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()..addRect(Offset.zero & size);
    final h = hole;
    final path = (h == null || h == Rect.zero)
        ? dim
        : Path.combine(
            PathOperation.difference,
            dim,
            Path()..addRRect(RRect.fromRectAndRadius(h, const Radius.circular(14))),
          );
    canvas.drawPath(path, Paint()..color = Colors.black.withOpacity(0.62));
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}

class _Balloon extends StatelessWidget {
  final String text;
  final String progress;
  final String nextLabel;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  const _Balloon({
    required this.text,
    required this.progress,
    required this.nextLabel,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(progress, style: TextStyle(fontSize: 12.5, color: Colors.grey[500])),
                const Spacer(),
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
                  child: const Text('Pular tutorial'),
                ),
              ],
            ),
            Text(
              text,
              style: const TextStyle(fontSize: 15, color: kAuthTextDark, height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onBack != null) ...[
                  OutlinedButton(
                    onPressed: onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kAuthPink,
                      side: const BorderSide(color: kAuthPink),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Voltar', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: kAuthPink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text(nextLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
