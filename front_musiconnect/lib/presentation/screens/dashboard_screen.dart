import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/models/providers/auth_service.dart';
import '../../data/models/providers/dashboard_service.dart';
import '../../data/models/providers/favorites_service.dart';
import '../widgets/app_loading_indicator.dart';
import '../widgets/auth/auth_common.dart';
import '../widgets/opportunity_carousel_section.dart';
import 'opportunity_detail_screen.dart';

/// Aba Início (tela inicial do app): resumo do que importa hoje —
/// saudação, novidades, prazos das salvas e melhores matches. Seções
/// vazias não aparecem.
class DashboardScreen extends StatefulWidget {
  final AuthUser user;

  /// Recarrega quando o valor muda — o MainNavigation incrementa ao tocar
  /// na aba Início (pega oportunidades novas e salvos de outras telas).
  final Listenable? refreshRequest;

  /// Matcher numa aba: 0 = Minhas oportunidades, 1 = Todas.
  final void Function(int tab) onOpenMatcher;
  final OpenOpportunityOnMap? onOpenMap;

  const DashboardScreen({
    super.key,
    required this.user,
    required this.onOpenMatcher,
    this.refreshRequest,
    this.onOpenMap,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _service = DashboardService();
  late Future<DashboardData> _future = _service.fetch();

  @override
  void initState() {
    super.initState();
    widget.refreshRequest?.addListener(_reload);
  }

  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRequest != widget.refreshRequest) {
      oldWidget.refreshRequest?.removeListener(_reload);
      widget.refreshRequest?.addListener(_reload);
    }
    // Perfil editado (aba Perfil) muda os matches.
    if (oldWidget.user != widget.user) _reload();
  }

  @override
  void dispose() {
    widget.refreshRequest?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final future = _service.fetch();
    setState(() => _future = future);
    await future.catchError((_) => const DashboardData(
          matchCount: 0,
          urgentSaved: [],
          topMatches: [],
          newMatches: [],
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

  String get _firstName {
    final name = widget.user.name.trim();
    return name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: AppLoadingIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorState(onRetry: _reload);
        }
        return RefreshIndicator(
          onRefresh: _reload,
          color: kAuthPink,
          // Escuta os corações: remover uma salva tira ela de "Prazos se
          // aproximando" na hora, sem esperar recarregar.
          child: ListenableBuilder(
            listenable: FavoritesService.instance,
            builder: (context, _) => _buildContent(snapshot.data!),
          ),
        );
      },
    );
  }

  Widget _buildContent(DashboardData data) {
    final favorites = FavoritesService.instance;
    final urgent =
        data.urgentSaved.where((o) => favorites.isOpportunitySaved(o.id)).toList();
    final nothingToShow =
        urgent.isEmpty && data.topMatches.isEmpty && data.newMatches.isEmpty;

    return ListView(
      // Sempre rolável — senão o "puxar pra atualizar" não funciona.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Greeting(firstName: _firstName),
        if (data.newMatches.isNotEmpty)
          OpportunityCarouselSection(
            title: 'Novas para você',
            total: data.newMatches.length,
            items: data.newMatches,
            onCardTap: _open,
          ),
        if (urgent.isNotEmpty)
          // Sem "Ver todas": a lista de salvas tem também as que não são
          // urgentes, então o total não bateria com o desta seção.
          OpportunityCarouselSection(
            title: 'Prazos se aproximando',
            subtitle:
                'Oportunidades salvas que fecham nos próximos $kUrgentDeadlineDays dias',
            total: urgent.length,
            items: urgent,
            onCardTap: _open,
          ),
        if (data.topMatches.isNotEmpty)
          OpportunityCarouselSection(
            title: 'Seus melhores matches',
            total: data.matchCount,
            items: data.topMatches,
            onSeeAll: () => widget.onOpenMatcher(0),
            onCardTap: _open,
          ),
        if (nothingToShow)
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
            style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4),
          ),
        ],
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
            style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.4),
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
