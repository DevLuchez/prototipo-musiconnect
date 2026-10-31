import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/opportunities_service.dart';
import '../widgets/match_explainer.dart';
import '../widgets/opportunity_browser_view.dart';
import '../widgets/visitor_invite.dart';
import 'opportunity_detail_screen.dart';

const _pink = Color(0xFFEC4899);

const _visitorInvite = 'Crie sua conta para acompanhar de perto as '
    'oportunidades que combinam com você.';

/// Tela Matcher — faixa "o que é match" no topo e duas abas:
///   1. Minhas oportunidades (match >= [kHighMatchThreshold])
///   2. Todas as oportunidades
///
/// As duas abas compartilham o mesmo layout (busca, filtro, carrosséis por
/// categoria) via [OpportunityBrowserView] — só muda a faixa da Escala de
/// Match permitida no filtro de cada uma. "Meu instrumento"/"Perto de Mim"
/// começam desligados nas duas.
class MatcherScreen extends StatefulWidget {
  final AuthUser user;

  /// Chamado quando o usuário quer ver uma instituição no mapa.
  final OpenOpportunityOnMap? onSwitchToMap;

  /// Pedido para mostrar uma aba (0 = Minhas, 1 = Todas) — vindo do número
  /// de Matches do Perfil. A tela zera o valor depois de atender.
  final ValueNotifier<int?>? tabRequest;

  const MatcherScreen({
    super.key,
    required this.user,
    this.onSwitchToMap,
    this.tabRequest,
  });

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
    widget.tabRequest?.addListener(_onTabRequest);
  }

  void _onTabRequest() {
    final index = widget.tabRequest?.value;
    if (index == null) return;
    widget.tabRequest!.value = null;
    _tabController.animateTo(index);
  }

  @override
  void dispose() {
    widget.tabRequest?.removeListener(_onTabRequest);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── O que é match (sempre visível, acima das abas) ───────
        const MatchExplainerBanner(),

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
              if (widget.user.isVisitor)
                // Sem perfil, não há match: a aba mostra só o convite.
                OpportunityBrowserView(
                  service: _service,
                  user: widget.user,
                  matchScaleMin: kHighMatchThreshold.toDouble(),
                  matchScaleMax: 100,
                  onOpenMap: widget.onSwitchToMap,
                  emptyCategoriesIcon: Icons.auto_awesome_rounded,
                  emptyCategoriesMessage: _visitorInvite,
                  emptyCategoriesAction: const AccountInviteButtons(),
                  emptySearchMessage: _visitorInvite,
                )
              else
                OpportunityBrowserView(
                  service: _service,
                  user: widget.user,
                  matchScaleMin: kHighMatchThreshold.toDouble(),
                  matchScaleMax: 100,
                  onOpenMap: widget.onSwitchToMap,
                  emptyCategoriesIcon: Icons.auto_awesome_rounded,
                  emptyCategoriesMessage:
                      'Ainda não encontramos oportunidades com alta '
                      'compatibilidade com o seu perfil.',
                  emptyCategoriesAction: TextButton(
                    onPressed: () => _tabController.animateTo(1),
                    style: TextButton.styleFrom(foregroundColor: _pink),
                    child: const Text('Ver todas as oportunidades'),
                  ),
                  emptySearchMessage:
                      'Nenhuma oportunidade com alta compatibilidade encontrada.',
                ),
              OpportunityBrowserView(
                service: _service,
                user: widget.user,
                onOpenMap: widget.onSwitchToMap,
                emptyCategoriesMessage:
                    'Nenhuma oportunidade aberta no momento.\n'
                    'Novos editais, audições e concursos aparecem aqui '
                    'assim que forem publicados.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
