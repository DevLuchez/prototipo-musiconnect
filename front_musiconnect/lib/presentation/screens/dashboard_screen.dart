import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/opportunities_service.dart';
import '../view_models/dashboard_view_model.dart';
import '../widgets/app_loading_indicator.dart';
import '../widgets/auth/auth_common.dart';
import '../widgets/match_ring.dart';
import '../widgets/opportunity_browser_view.dart';
import '../widgets/opportunity_card.dart';
import '../widgets/visitor_invite.dart';
import '../widgets/opportunity_carousel_section.dart';
import 'help_screen.dart';
import 'opportunity_detail_screen.dart';

/// Aba Início (tela inicial do app): resumo do que importa hoje —
/// saudação (com atalho para as perguntas frequentes), destaque do melhor
/// match, categorias para explorar e prazos das salvas, em cards enxutos.
/// Seções vazias não aparecem.
///
/// Estado e regras ficam no [DashboardViewModel]; esta tela só desenha e
/// navega.
class DashboardScreen extends StatefulWidget {
  final AuthUser user;

  /// Recarrega quando o valor muda — o MainNavigation incrementa ao tocar
  /// na aba Início (pega oportunidades novas e salvos de outras telas).
  final Listenable? refreshRequest;

  /// Matcher numa aba: 0 = Minhas oportunidades, 1 = Todas.
  final void Function(int tab) onOpenMatcher;
  final OpenOpportunityOnMap? onOpenMap;

  /// Para testes: um ViewModel com serviços simulados. Sem ele, a tela cria
  /// o seu.
  final DashboardViewModel? viewModel;

  const DashboardScreen({
    super.key,
    required this.user,
    required this.onOpenMatcher,
    this.refreshRequest,
    this.onOpenMap,
    this.viewModel,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final _viewModel = (widget.viewModel ?? DashboardViewModel(user: widget.user))..load();

  @override
  void initState() {
    super.initState();
    widget.refreshRequest?.addListener(_viewModel.load);
  }

  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRequest != widget.refreshRequest) {
      oldWidget.refreshRequest?.removeListener(_viewModel.load);
      widget.refreshRequest?.addListener(_viewModel.load);
    }
    _viewModel.user = widget.user;
  }

  @override
  void dispose() {
    widget.refreshRequest?.removeListener(_viewModel.load);
    _viewModel.dispose();
    super.dispose();
  }

  /// Página de uma categoria — a mesma do "Ver todas" do Matcher (todas as
  /// oportunidades abertas do tipo, com busca e filtros), por cima do app.
  void _openCategory(_ExploreCategory category) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (routeContext) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: OpportunityBrowserView(
            service: OpportunitiesService(),
            user: widget.user,
            onOpenMap: widget.onOpenMap,
            lockedType: category.type,
            lockedTitle: category.label,
            onBack: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    ));
  }

  void _open(OpportunityModel opp) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OpportunityDetailScreen(
        opportunity: opp,
        user: widget.user,
        onOpenMap: widget.onOpenMap,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        if (_viewModel.isLoading) {
          return const Center(child: AppLoadingIndicator());
        }
        if (_viewModel.hasError) {
          return _ErrorState(onRetry: _viewModel.load);
        }
        return RefreshIndicator(
          onRefresh: _viewModel.load,
          color: kAuthPink,
          child: _buildContent(),
        );
      },
    );
  }

  Widget _buildContent() {
    final vm = _viewModel;
    final best = vm.bestMatch;
    final urgent = vm.urgentSaved;

    return ListView(
      // Sempre rolável — senão o "puxar pra atualizar" não funciona.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Greeting(firstName: vm.firstName),
        if (vm.isVisitor)
          const _VisitorHero()
        else if (best != null)
          _BestMatchHero(opportunity: best, onTap: () => _open(best)),
        _ExploreGrid(counts: vm.typeCounts, onOpen: _openCategory),
        if (urgent.isNotEmpty)
          // Sem "Ver todas": a lista de salvas tem também as que não são
          // urgentes, então o total não bateria com o desta seção.
          OpportunityCarouselSection(
            title: 'Última chance para seus favoritos',
            subtitle:
                'Oportunidades salvas que fecham nos próximos $kUrgentDeadlineDays dias',
            total: urgent.length,
            items: urgent,
            onCardTap: _open,
            compact: true,
          ),
        if (vm.nothingToShow)
          _EmptyState(onExplore: () => widget.onOpenMatcher(1)),
      ],
    );
  }
}

// ── Peças da tela ────────────────────────────────────────────────────────────

class _Greeting extends StatelessWidget {
  final String firstName;

  const _Greeting({required this.firstName});

  /// Bom dia (5h–11h), Boa tarde (12h–17h), Boa noite (18h–4h).
  static String _salutation(DateTime now) {
    if (now.hour >= 5 && now.hour < 12) return 'Bom dia';
    if (now.hour >= 12 && now.hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    final salutation = _salutation(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            firstName.isEmpty ? '$salutation!' : '$salutation, $firstName!',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: kAuthTextDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Veja o que separamos para você hoje.',
            style:
                TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4),
          ),
          const SizedBox(height: 12),
          const _HelpShortcut(),
        ],
      ),
    );
  }
}

/// Pílula logo abaixo da saudação — primeira coisa lida no app — que abre
/// as perguntas frequentes (a mesma tela do "Ajuda e suporte" do menu).
class _HelpShortcut extends StatelessWidget {
  const _HelpShortcut();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kAuthPink.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const HelpScreen(),
        )),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(10, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.help_outline_rounded, size: 16, color: kAuthPink),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Dúvidas? Veja as perguntas frequentes',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: kAuthPink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modo visitante: o mesmo card do "Seu melhor match", com o convite para
/// criar conta no lugar da oportunidade.
class _VisitorHero extends StatelessWidget {
  const _VisitorHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SEU MELHOR MATCH',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: kAuthPink,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Crie sua conta para descobrir a oportunidade que mais '
                      'combina com você',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: kAuthTextDark,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: kAuthPink.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: kAuthPink, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const AccountInviteButtons(),
        ],
      ),
    );
  }
}

/// Destaque do Início: a oportunidade de maior match, num card branco
/// (mesma sombra dos outros) com o anel de % e etiquetas em gradiente.
class _BestMatchHero extends StatelessWidget {
  final OpportunityModel opportunity;
  final VoidCallback onTap;

  const _BestMatchHero({required this.opportunity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final opp = opportunity;
    // Mesmos ícones usados no resto do app: o do tipo (igual ao Explorar),
    // o relógio do prazo e o pin do local.
    final pills = <_HeroPill>[
      _HeroPill(opp.typeLabel, _typeIcon(opp.type)),
      _HeroPill(deadlineShortLabel(opp.deadline), Icons.access_time_rounded),
      if ((opp.city ?? '').isNotEmpty)
        _HeroPill(opp.city!, Icons.location_on_outlined),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      // Branco + sombra padrão dos cards do app.
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: kAuthPink.withOpacity(0.12),
          highlightColor: kAuthPink.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SEU MELHOR MATCH',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: kAuthPink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        opp.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: kAuthTextDark,
                          height: 1.25,
                        ),
                      ),
                      if ((opp.institution ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          opp.institution!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: pills,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (opp.matchPercentage != null)
                  MatchRing(
                    percent: opp.matchPercentage!,
                    gradientColors: kBrandGradientColors,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ícone do tipo da oportunidade — o mesmo do bloco "Explorar".
IconData _typeIcon(String? type) =>
    _exploreCategories.where((c) => c.type == type).firstOrNull?.icon ??
    Icons.music_note_rounded;

class _HeroPill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _HeroPill(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      // Gradiente roxo→rosa do anel, mais claro (75%).
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            for (final c in kBrandGradientColors) c.withOpacity(0.75),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uma categoria do bloco "Explorar".
class _ExploreCategory {
  final String type;
  final String label;
  final IconData icon;
  const _ExploreCategory(this.type, this.label, this.icon);
}

const _exploreCategories = [
  _ExploreCategory('audicao', 'Audições', Icons.mic_rounded),
  _ExploreCategory('competicao', 'Competições', Icons.emoji_events_rounded),
  _ExploreCategory('emprego', 'Empregos', Icons.work_rounded),
  _ExploreCategory('curso', 'Cursos', Icons.school_rounded),
];

/// Bloco "Explorar": uma peça por tipo de oportunidade (2 por linha), na
/// cor do tipo, com quantas estão abertas. Tipos sem nenhuma aberta somem.
class _ExploreGrid extends StatelessWidget {
  final Map<String, int> counts;
  final void Function(_ExploreCategory category) onOpen;

  const _ExploreGrid({required this.counts, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final categories =
        _exploreCategories.where((c) => (counts[c.type] ?? 0) > 0).toList();
    if (categories.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < categories.length; i += 2) {
      final pair = categories.skip(i).take(2).toList();
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
        child: Row(
          children: [
            Expanded(
                child: _ExploreTile(
                    category: pair[0],
                    count: counts[pair[0].type]!,
                    onTap: () => onOpen(pair[0]))),
            const SizedBox(width: 10),
            Expanded(
              child: pair.length > 1
                  ? _ExploreTile(
                      category: pair[1],
                      count: counts[pair[1].type]!,
                      onTap: () => onOpen(pair[1]))
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Explorar',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _ExploreTile extends StatelessWidget {
  final _ExploreCategory category;
  final int count;
  final VoidCallback onTap;

  const _ExploreTile({
    required this.category,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = opportunityTypeColor(category.type);
    // Mesmo branco + sombra dos outros cards do app.
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: color.withOpacity(0.18),
          highlightColor: color.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Icon(category.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        count == 1 ? '1 aberta' : '$count abertas',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          // Tom mais claro da cor da categoria (ainda legível
                          // sobre o branco).
                          color: color.withOpacity(0.6),
                        ),
                      ),
                    ],
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

/// Sem prazos, matches nem novidades — convida a explorar todas.
class _EmptyState extends StatelessWidget {
  final VoidCallback onExplore;

  const _EmptyState({required this.onExplore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 48, 40, 0),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'Nenhuma novidade por aqui ainda.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.4),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onExplore,
            style: TextButton.styleFrom(foregroundColor: kAuthPink),
            child: const Text('Explorar todas as oportunidades'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'Não foi possível carregar o Início.',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: kAuthPink),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
