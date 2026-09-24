import 'package:flutter/material.dart';
import '../../data/models/providers/auth_service.dart';
import '../../data/models/providers/opportunities_service.dart';
import '../widgets/opportunity_browser_view.dart';

const _pink = Color(0xFFEC4899);

/// Tela Matcher com duas abas:
///   1. Minhas oportunidades (match >= 85%)
///   2. Todas as oportunidades
///
/// As duas abas compartilham o mesmo layout (busca, filtro, carrosséis por
/// categoria) via [OpportunityBrowserView] — só muda a faixa da Escala de
/// Match permitida no filtro de cada uma, e se "Meu instrumento"/"Perto de
/// Mim" ficam travados ligados (Minhas) ou livres (Todas).
class MatcherScreen extends StatefulWidget {
  final AuthUser user;

  /// Chamado quando o usuário quer ver uma instituição no mapa.
  final VoidCallback? onSwitchToMap;

  const MatcherScreen({super.key, required this.user, this.onSwitchToMap});

  @override
  State<MatcherScreen> createState() => _MatcherScreenState();
}

class _MatcherScreenState extends State<MatcherScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _service = OpportunitiesService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── TabBar ───────────────────────────────────────────────
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: _pink,
            unselectedLabelColor: Colors.grey[500],
            indicatorColor: _pink,
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13.5,
            ),
            tabs: const [
              Tab(text: 'Minhas oportunidades'),
              Tab(text: 'Todas as oportunidades'),
            ],
          ),
        ),

        // ── Conteúdo das abas ────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              OpportunityBrowserView(
                service: _service,
                user: widget.user,
                matchScaleMin: 85,
                matchScaleMax: 100,
                onOpenMap: widget.onSwitchToMap,
                emptyCategoriesMessage:
                    'Nenhuma oportunidade com alta compatibilidade encontrada ainda. Ajuste a escala de match no filtro ou volte mais tarde.',
                emptySearchMessage:
                    'Nenhuma oportunidade com alta compatibilidade encontrada.',
              ),
              OpportunityBrowserView(
                service: _service,
                user: widget.user,
                onOpenMap: widget.onSwitchToMap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
