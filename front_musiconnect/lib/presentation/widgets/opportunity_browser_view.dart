import 'package:flutter/material.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/opportunities_service.dart';
import '../screens/opportunity_detail_screen.dart';
import '../view_models/opportunity_browser_view_model.dart';
import 'app_loading_indicator.dart';
import 'filter_modal.dart';
import 'opportunity_card.dart';
import 'opportunity_carousel_section.dart';

const _pink = Color(0xFFEC4899);

/// Busca + filtro + carrosséis por categoria + lista plana de resultados —
/// o layout completo usado tanto pela aba "Todas as oportunidades" quanto
/// por "Minhas oportunidades" (mesmo widget, só muda a faixa da Escala de
/// Match). A subpágina "Ver todas" de uma categoria é o próprio widget se
/// renderizando de novo, travado num tipo ([lockedType]) — ver [build].
///
/// Estado e regras ficam no [OpportunityBrowserViewModel]; esta tela só
/// desenha e navega.
class OpportunityBrowserView extends StatefulWidget {
  final OpportunitiesService service;

  /// Chamado quando o usuário quer ver uma instituição no mapa.
  final OpenOpportunityOnMap? onOpenMap;

  // Limites do slider "Escala de Match" no FilterModal — "Todas as
  // oportunidades" usa 0-100 (livre, sem filtrar por padrão); "Minhas
  // oportunidades" trava em 85-100 (nunca mostra abaixo do que promete).
  final double matchScaleMin;
  final double matchScaleMax;

  final String emptyCategoriesMessage;
  final String emptySearchMessage;

  // Ícone e ação (opcional) do estado vazio dos carrosséis — mesmo visual
  // do vazio das telas de favoritos.
  final IconData emptyCategoriesIcon;
  final Widget? emptyCategoriesAction;

  // Perfil do usuário logado — usado pelos filtros opcionais "Meu
  // instrumento"/"Perto de Mim" no FilterModal (iguais nas duas abas:
  // começam desligados, o usuário decide se liga) e passado adiante pra
  // tela de detalhes (aba Matcher: "seu perfil vs. edital").
  final AuthUser user;

  // Só usados no modo "subpágina de categoria" (drill-down interno — ver
  // [build]): quando [lockedType] não é nulo, trava a busca nesse tipo,
  // esconde os carrosséis e mostra o cabeçalho local de voltar.
  final String? lockedType;
  final String? lockedTitle;
  final VoidCallback? onBack;

  const OpportunityBrowserView({
    super.key,
    required this.service,
    required this.user,
    this.onOpenMap,
    this.matchScaleMin = 0,
    this.matchScaleMax = 100,
    this.emptyCategoriesMessage = 'Nenhuma oportunidade disponível.',
    this.emptySearchMessage = 'Nenhuma oportunidade disponível.',
    this.emptyCategoriesIcon = Icons.library_music_outlined,
    this.emptyCategoriesAction,
    this.lockedType,
    this.lockedTitle,
    this.onBack,
  }) : assert(lockedType == null || lockedTitle != null);

  @override
  State<OpportunityBrowserView> createState() =>
      _OpportunityBrowserViewState();
}

class _OpportunityBrowserViewState extends State<OpportunityBrowserView> {
  late final _viewModel = OpportunityBrowserViewModel(
    service: widget.service,
    matchScaleMin: widget.matchScaleMin,
    matchScaleMax: widget.matchScaleMax,
    lockedType: widget.lockedType,
    lockedTitle: widget.lockedTitle,
  )..start();

  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _openFilters() {
    final vm = _viewModel;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterModal(
        // O filtro de tipo fica escondido dentro de uma subpágina de
        // categoria — o tipo já está travado pela navegação ali.
        showTypeFilter: widget.lockedType == null,
        initialTypes: vm.activeTypes,
        initialInstruments: vm.activeInstruments,
        initialCountries: vm.activeCountries,
        initialStates: vm.activeStates,
        initialCities: vm.activeCities,
        initialStateLabels: vm.stateLabels,
        service: widget.service,
        searchQuery: _searchController.text,
        matchScaleMin: widget.matchScaleMin,
        matchScaleMax: widget.matchScaleMax,
        initialMatchScale: RangeValues(vm.matchScaleStart, vm.matchScaleEnd),
        myInstruments: widget.user.instruments,
        myCountry: widget.user.country,
        myState: widget.user.state,
        myCity: widget.user.city,
        initialInstrumentToggle: vm.myInstrumentToggle,
        initialLocationToggle: vm.myLocationToggle,
        profileFiltersLocked: widget.user.isVisitor,
        onApply: ({
          required types,
          required instruments,
          required countries,
          required states,
          required cities,
          required stateLabels,
          required matchScale,
          required instrumentToggle,
          required locationToggle,
        }) {
          vm.applyFilters(
            types: types,
            instruments: instruments,
            countries: countries,
            states: states,
            cities: cities,
            stateLabels: stateLabels,
            matchStart: matchScale.start,
            matchEnd: matchScale.end,
            instrumentToggle: instrumentToggle,
            locationToggle: locationToggle,
          );
        },
      ),
    );
  }

  void _openDetail(OpportunityModel opp) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OpportunityDetailScreen(
          opportunity: opp,
          user: widget.user,
          onOpenMap: widget.onOpenMap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => _buildView(),
    );
  }

  Widget _buildView() {
    final vm = _viewModel;
    // Subpágina "Ver todas" de uma categoria — mesmo widget, travado no
    // tipo escolhido, com o header local de voltar e sem carrosséis.
    if (widget.lockedType == null && vm.drillType != null) {
      return OpportunityBrowserView(
        key: ValueKey(vm.drillType),
        service: widget.service,
        user: widget.user,
        onOpenMap: widget.onOpenMap,
        matchScaleMin: widget.matchScaleMin,
        matchScaleMax: widget.matchScaleMax,
        emptyCategoriesMessage: widget.emptyCategoriesMessage,
        emptySearchMessage: widget.emptySearchMessage,
        lockedType: vm.drillType,
        lockedTitle: vm.drillLabel,
        onBack: vm.closeDrill,
      );
    }

    return Column(
      children: [
        if (widget.lockedType != null)
          // Cabeçalho local (voltar + título da categoria) — não é um
          // AppBar de verdade, pra não competir com o header global do app.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Color(0xFF111827)),
                  tooltip: 'Voltar',
                  onPressed: widget.onBack,
                ),
                Expanded(
                  child: Text(
                    widget.lockedTitle!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),

        // Barra de busca + filtros
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              // Campo de busca
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (text) => vm.query = text,
                    onSubmitted: vm.search,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: vm.searchHint,
                      hintStyle: TextStyle(
                          fontSize: 13.5, color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 18, color: Colors.grey[400]),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 40, minHeight: 0),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                vm.search('');
                              },
                              child: Icon(Icons.close_rounded,
                                  size: 16, color: Colors.grey[400]),
                            )
                          : null,
                      suffixIconConstraints:
                          const BoxConstraints(minWidth: 40, minHeight: 0),
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Botão de filtros
              GestureDetector(
                onTap: _openFilters,
                child: Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 20,
                        color: Color(0xFFDF2881),
                      ),
                      if (vm.activeFiltersCount > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: _pink,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${vm.activeFiltersCount}',
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        if (vm.searchMode) ...[
          // Contagem de resultados
          if (!vm.isLoading && vm.error == null)
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, vm.activeFiltersCount > 0 ? 4 : 10),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  vm.resultCountLabel,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // Chips de filtros ativos
          if (vm.activeFiltersCount > 0)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (vm.matchScaleActive)
                      _ActiveFilterChip(
                        label:
                            '${vm.matchScaleStart.round()}-${vm.matchScaleEnd.round()}% match',
                        onRemove: vm.resetMatchScale,
                      ),
                    for (final v in vm.activeTypes)
                      _ActiveFilterChip(
                        label: kOpportunityTypeLabels[v] ?? v,
                        onRemove: () => vm.removeType(v),
                      ),
                    for (final v in vm.activeInstruments)
                      _ActiveFilterChip(
                        label: v,
                        onRemove: () => vm.removeInstrument(v),
                      ),
                    for (final v in vm.activeCountries)
                      _ActiveFilterChip(
                        label: v,
                        onRemove: () => vm.removeCountry(v),
                      ),
                    for (final v in vm.activeStates)
                      _ActiveFilterChip(
                        label: vm.stateLabels[v] ?? v,
                        onRemove: () => vm.removeState(v),
                      ),
                    for (final v in vm.activeCities)
                      _ActiveFilterChip(
                        label: v,
                        onRemove: () => vm.removeCity(v),
                      ),
                  ],
                ),
              ),
            ),

          // Lista / Loading / Erro / Vazio
          Expanded(child: _buildContent()),
        ] else
          // Modo padrão: navegar por categoria (carrosséis por tipo)
          Expanded(child: _buildCategoriesBrowser()),
      ],
    );
  }

  Widget _buildCategoriesBrowser() {
    final vm = _viewModel;
    if (vm.categoriesLoading) {
      return const Center(
        child: AppLoadingIndicator(size: 28, color: _pink),
      );
    }

    if (vm.categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.emptyCategoriesIcon,
                  size: 48, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                widget.emptyCategoriesMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: Colors.grey[500], height: 1.4),
              ),
              if (widget.emptyCategoriesAction != null) ...[
                const SizedBox(height: 8),
                widget.emptyCategoriesAction!,
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _pink,
      onRefresh: vm.loadCategories,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final category in vm.categories)
            OpportunityCarouselSection(
              title: category.label,
              total: category.total,
              items: category.items,
              onSeeAll: () => vm.openDrill(category.typeKey, category.label),
              onCardTap: _openDetail,
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final vm = _viewModel;
    if (vm.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLoadingIndicator(size: 28, color: _pink),
            SizedBox(height: 16),
            Text(
              'Carregando oportunidades...',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (vm.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              vm.error!,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: vm.load,
              style: OutlinedButton.styleFrom(
                foregroundColor: _pink,
                side: const BorderSide(color: _pink),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (vm.opportunities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                vm.query.isNotEmpty
                    ? 'Nenhuma oportunidade encontrada para\n"${vm.query}"'
                    : widget.emptySearchMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
            if (vm.activeFiltersCount > 0) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: vm.clearFilters,
                child: const Text(
                  'Limpar filtros',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _pink,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _pink,
      onRefresh: vm.load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: vm.opportunities.length,
        itemBuilder: (context, index) {
          final opp = vm.opportunities[index];
          return OpportunityCard(
            opportunity: opp,
            matchPercentage: opp.matchPercentage,
            onTap: () => _openDetail(opp),
          );
        },
      ),
    );
  }
}

/// Chip de filtro ativo com botão de remoção.
class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _pink.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pink.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _pink,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 14, color: _pink),
          ),
        ],
      ),
    );
  }
}
