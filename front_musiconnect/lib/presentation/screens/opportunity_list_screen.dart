import 'package:flutter/material.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/models/providers/opportunities_service.dart';
import '../widgets/app_loading_indicator.dart';
import '../widgets/opportunity_card.dart';
import '../widgets/filter_modal.dart';
import 'opportunity_detail_screen.dart';

const _pink = Color(0xFFEC4899);

/// Conteúdo da subpágina de categoria — mostrada ao tocar em "Ver todas"
/// num carrossel (dentro da aba "Todas as oportunidades"), com [type]
/// travado nessa categoria.
///
/// Embutido dentro da própria aba (não é uma rota separada via
/// Navigator.push): a `MatcherScreen` troca seu conteúdo por este widget
/// mantendo o header e a navbar globais visíveis — só [onBack] volta pro
/// carrossel. Evita o problema de um Navigator.push cobrir a tela toda,
/// escondendo o header/navbar que pertencem ao Scaffold de MainNavigation.
class OpportunityListScreen extends StatefulWidget {
  /// Tipo travado desta subpágina (ex: 'audicao').
  final String? type;
  final String title;
  final VoidCallback onBack;
  final VoidCallback? onOpenMap;

  const OpportunityListScreen({
    super.key,
    this.type,
    required this.title,
    required this.onBack,
    this.onOpenMap,
  });

  @override
  State<OpportunityListScreen> createState() => _OpportunityListScreenState();
}

class _OpportunityListScreenState extends State<OpportunityListScreen> {
  final _service = OpportunitiesService();
  final _searchController = TextEditingController();

  List<OpportunityModel> _opportunities = [];
  int _totalCount = 0;
  bool _loading = true;
  String? _error;

  List<String> _activeInstruments = [];
  List<String> _activeCountries = [];
  List<String> _activeStates = [];
  List<String> _activeCities = [];
  Map<String, String> _stateLabels = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _service.fetchOpportunities(
        q: _searchController.text.isEmpty ? null : _searchController.text,
        type: widget.type,
        instruments: _activeInstruments,
        countries: _activeCountries,
        states: _activeStates,
        cities: _activeCities,
        onlyActive: false, // mostra todas, inclusive sem prazo
        limit: 500,
      );
      setState(() {
        _opportunities = result.items;
        _totalCount = result.total;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Não foi possível carregar as oportunidades.';
        _loading = false;
      });
    }
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterModal(
        initialInstruments: _activeInstruments,
        initialCountries: _activeCountries,
        initialStates: _activeStates,
        initialCities: _activeCities,
        initialStateLabels: _stateLabels,
        service: _service,
        onApply: ({
          required instruments,
          required countries,
          required states,
          required cities,
          required stateLabels,
        }) {
          setState(() {
            _activeInstruments = instruments;
            _activeCountries = countries;
            _activeStates = states;
            _activeCities = cities;
            _stateLabels = stateLabels;
          });
          _load();
        },
      ),
    );
  }

  int get _activeFiltersCount =>
      _activeInstruments.length +
      _activeCountries.length +
      _activeStates.length +
      _activeCities.length;

  String get _searchHint {
    final type = widget.type;
    if (type == null) return 'Busque por oportunidades...';
    final plural = kOpportunityTypePluralLabels[type] ?? widget.title.toLowerCase();
    return 'Busque por $plural...';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
                  widget.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: Column(
            children: [
              // Barra de busca + filtros
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
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
                          onSubmitted: (_) => _load(),
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: _searchHint,
                            hintStyle: TextStyle(
                                fontSize: 13.5, color: Colors.grey[400]),
                            prefixIcon: Icon(Icons.search_rounded,
                                size: 18, color: Colors.grey[400]),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      _searchController.clear();
                                      _load();
                                    },
                                    child: Icon(Icons.close_rounded,
                                        size: 16, color: Colors.grey[400]),
                                  )
                                : null,
                            border: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                            if (_activeFiltersCount > 0)
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
                                      '$_activeFiltersCount',
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

              // Contagem de resultados
              if (!_loading && _error == null)
                Container(
                  color: Colors.white,
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16, _activeFiltersCount > 0 ? 4 : 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      (_opportunities.length < _totalCount
                              ? '${_opportunities.length} de $_totalCount oportunidades encontradas'
                              : '$_totalCount oportunidades encontradas') +
                          (_activeFiltersCount > 0
                              ? ' contendo os filtros:'
                              : ''),
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
              if (_activeFiltersCount > 0)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final v in _activeInstruments)
                          _ActiveFilterChip(
                            label: v,
                            onRemove: () {
                              setState(() => _activeInstruments =
                                  _activeInstruments
                                      .where((x) => x != v)
                                      .toList());
                              _load();
                            },
                          ),
                        for (final v in _activeCountries)
                          _ActiveFilterChip(
                            label: v,
                            onRemove: () {
                              setState(() => _activeCountries = _activeCountries
                                  .where((x) => x != v)
                                  .toList());
                              _load();
                            },
                          ),
                        for (final v in _activeStates)
                          _ActiveFilterChip(
                            label: _stateLabels[v] ?? v,
                            onRemove: () {
                              setState(() => _activeStates =
                                  _activeStates.where((x) => x != v).toList());
                              _load();
                            },
                          ),
                        for (final v in _activeCities)
                          _ActiveFilterChip(
                            label: v,
                            onRemove: () {
                              setState(() => _activeCities =
                                  _activeCities.where((x) => x != v).toList());
                              _load();
                            },
                          ),
                      ],
                    ),
                  ),
                ),

              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
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

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _load,
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

    if (_opportunities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Nenhuma oportunidade encontrada para\n"${_searchController.text}"'
                  : 'Nenhuma oportunidade disponível.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            if (_activeFiltersCount > 0) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _activeInstruments = [];
                    _activeCountries = [];
                    _activeStates = [];
                    _activeCities = [];
                  });
                  _load();
                },
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
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _opportunities.length,
        itemBuilder: (context, index) {
          final opp = _opportunities[index];
          return OpportunityCard(
            opportunity: opp,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => OpportunityDetailScreen(
                  opportunity: opp,
                  onOpenMap: widget.onOpenMap,
                ),
              ),
            ),
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
