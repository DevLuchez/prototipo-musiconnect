import 'package:flutter/material.dart';
import '../../core/text_utils.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/models/providers/opportunities_service.dart';

const _pink = Color(0xFFEC4899);

/// Modal de filtros da aba "Todas as oportunidades" (e da subpágina de
/// categoria). Segue o protótipo: tipo, instrumento e localização (país/
/// estado/cidade), com "Meu instrumento"/"Perto de Mim"/"Escala de Match"
/// dependendo do perfil do usuário logado.
///
/// Instrumento e localização são cruzados entre si (busca facetada):
/// escolher um instrumento estreita as opções de localização mostradas, e
/// vice-versa — o modal busca as opções de novo a cada mudança, usando
/// [service]. Tipo não entra nesse cruzamento (são só 4 valores fixos,
/// não precisa buscar do backend).
///
/// Fonte saiu do modal: só tinha "Musical Chairs" (pouco útil como filtro
/// hoje).
class FilterModal extends StatefulWidget {
  // Escondido dentro da subpágina de uma categoria — o tipo já está
  // travado pela navegação ali, filtrar de novo seria redundante.
  final bool showTypeFilter;
  final List<String> initialTypes;
  final List<String> initialInstruments;
  final List<String> initialCountries;
  final List<String> initialStates;
  final List<String> initialCities;
  // Rótulo por extenso ("MT" -> "MT | Montana") de estados já selecionados
  // antes de abrir o modal — deixa os chips certos desde o primeiro frame,
  // sem esperar a primeira busca de opções responder.
  final Map<String, String> initialStateLabels;
  final OpportunitiesService service;
  // Texto da barra de busca do Matcher — as opções mostradas respeitam a
  // busca (null/vazio = sem busca).
  final String? searchQuery;
  // Limites do slider "Escala de Match" — "Todas as oportunidades" usa
  // 0-100 (livre, sem filtrar por padrão); "Minhas oportunidades" trava em
  // 85-100 (nunca mostra abaixo do que a aba promete).
  final double matchScaleMin;
  final double matchScaleMax;
  // Valor atual do range, pra manter a seleção ao reabrir o modal — default
  // igual aos limites (ou seja, sem filtro ativo).
  final RangeValues? initialMatchScale;

  // "Meu instrumento" / "Perto de Mim": instrumentos e localização do
  // perfil do usuário logado, usados quando o toggle correspondente está
  // ligado. Opcionais e iguais nas duas abas — começam desligados
  // (initialInstrumentToggle/initialLocationToggle), o usuário decide se
  // liga.
  final List<String> myInstruments;
  final String? myCountry;
  final String? myState;
  final String? myCity;
  final bool initialInstrumentToggle;
  final bool initialLocationToggle;

  final void Function({
    required List<String> types,
    required List<String> instruments,
    required List<String> countries,
    required List<String> states,
    required List<String> cities,
    required Map<String, String> stateLabels,
    required RangeValues matchScale,
    required bool instrumentToggle,
    required bool locationToggle,
  }) onApply;

  const FilterModal({
    super.key,
    this.showTypeFilter = true,
    this.initialTypes = const [],
    this.initialInstruments = const [],
    this.initialCountries = const [],
    this.initialStates = const [],
    this.initialCities = const [],
    this.initialStateLabels = const {},
    required this.service,
    this.searchQuery,
    this.matchScaleMin = 0,
    this.matchScaleMax = 100,
    this.initialMatchScale,
    this.myInstruments = const [],
    this.myCountry,
    this.myState,
    this.myCity,
    this.initialInstrumentToggle = false,
    this.initialLocationToggle = false,
    required this.onApply,
  });

  @override
  State<FilterModal> createState() => _FilterModalState();
}

class _FilterModalState extends State<FilterModal> {
  late List<String> _types = List.of(widget.initialTypes);
  late List<String> _instruments = List.of(widget.initialInstruments);
  late List<String> _countries = List.of(widget.initialCountries);
  late List<String> _states = List.of(widget.initialStates);
  late List<String> _cities = List.of(widget.initialCities);

  // Rótulo de exibição por sigla de estado (ex: "MT" -> "MT | Montana"),
  // acumulado conforme as opções chegam — assim um estado selecionado
  // continua mostrando o rótulo certo mesmo se sair da lista de opções
  // depois de cruzar com outro filtro.
  late final Map<String, String> _stateLabels =
      Map.of(widget.initialStateLabels);

  FilterOptions _options = const FilterOptions();
  bool _optionsLoading = true;

  bool _instrumentExpanded = true;
  bool _locationExpanded = true;

  late RangeValues _matchScale = widget.initialMatchScale ??
      RangeValues(widget.matchScaleMin, widget.matchScaleMax);

  late bool _instrumentToggle = widget.initialInstrumentToggle;
  late bool _locationToggle = widget.initialLocationToggle;

  @override
  void initState() {
    super.initState();
    _refreshOptions();
  }

  void _setInstrumentToggle(bool value) {
    setState(() {
      _instrumentToggle = value;
      _instruments = value ? List.of(widget.myInstruments) : [];
    });
    _refreshOptions();
  }

  void _setLocationToggle(bool value) {
    setState(() {
      _locationToggle = value;
      _countries = value && widget.myCountry != null ? [widget.myCountry!] : [];
      _states = value && widget.myState != null ? [widget.myState!] : [];
      _cities = value && widget.myCity != null ? [widget.myCity!] : [];
    });
    _refreshOptions();
  }

  Future<void> _refreshOptions() async {
    setState(() => _optionsLoading = true);
    final options = await widget.service.fetchFilterOptions(
      q: widget.searchQuery,
      instruments: _instruments,
      countries: _countries,
      states: _states,
      cities: _cities,
    );
    for (final s in options.states) {
      _stateLabels[s.value] = s.label;
    }
    if (!mounted) return;
    setState(() {
      _options = options;
      _optionsLoading = false;
    });
  }

  String _stateLabel(String code) => _stateLabels[code] ?? code;

  void _toggleType(String key) {
    setState(() {
      _types = _types.contains(key)
          ? _types.where((t) => t != key).toList()
          : [..._types, key];
    });
  }

  void _toggle(List<String> current, String value, void Function(List<String>) apply) {
    final next = List<String>.of(current);
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    apply(next);
    _refreshOptions();
  }

  String? get _locationSummary {
    final parts = <String>[
      if (_countries.isNotEmpty) '(${_countries.length}) País',
      if (_states.isNotEmpty) '(${_states.length}) Estado',
      if (_cities.isNotEmpty) '(${_cities.length}) Cidade',
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Altura FIXA (não só um teto): com "maxHeight" solto, o Column com
      // Expanded lá dentro encolhia pro tamanho do conteúdo sempre que
      // cabia, e aí o rodapé/cabeçalho acabavam rolando junto por não
      // haver de fato uma área rolável isolada. Com altura fixa, o
      // Expanded sempre recebe um espaço delimitado de verdade, e só o
      // SingleChildScrollView de dentro rola quando o conteúdo excede.
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho fixo ──────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'Filtrar por',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
          ),
          const Divider(height: 1),

          // ── Filtros — só esta parte rola ──────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  _ToggleRow(
                    title: 'Meu instrumento',
                    subtitle: 'Filtra pelo(s) instrumento(s) do seu perfil',
                    value: _instrumentToggle,
                    onChanged: _setInstrumentToggle,
                  ),
                  const Divider(height: 1),
                  _ToggleRow(
                    title: 'Perto de Mim',
                    subtitle: 'Filtra pela localização do seu perfil',
                    value: _locationToggle,
                    onChanged: _setLocationToggle,
                  ),

                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Escala de Match',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        RangeSlider(
                          values: _matchScale,
                          min: widget.matchScaleMin,
                          max: widget.matchScaleMax,
                          activeColor: _pink,
                          inactiveColor: const Color(0xFFE5E7EB),
                          labels: RangeLabels(
                            '${_matchScale.start.round()}%',
                            '${_matchScale.end.round()}%',
                          ),
                          onChanged: (v) => setState(() => _matchScale = v),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${widget.matchScaleMin.round()}%',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[400])),
                            Text(
                              '${_matchScale.start.round()}% - ${_matchScale.end.round()}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                            ),
                            Text('${widget.matchScaleMax.round()}%',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[400])),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (widget.showTypeFilter) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tipo de oportunidade',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: kOpportunityTypeLabels.entries.map((e) {
                              final selected = _types.contains(e.key);
                              return GestureDetector(
                                onTap: () => _toggleType(e.key),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? _pink.withOpacity(0.1)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selected
                                          ? _pink
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Text(
                                    e.value,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? _pink
                                          : const Color(0xFF374151),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Divider(height: 1),
                  _CollapsibleHeader(
                    title: 'Instrumento',
                    subtitle: _instrumentToggle ? 'Usando seu perfil' : null,
                    expanded: _instrumentExpanded,
                    onTap: () => setState(
                        () => _instrumentExpanded = !_instrumentExpanded),
                  ),
                  if (_instrumentExpanded)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: IgnorePointer(
                        ignoring: _instrumentToggle,
                        child: Opacity(
                          opacity: _instrumentToggle ? 0.5 : 1,
                          child: _PickerField(
                            options: _options.instruments
                                .map((i) => FilterOption(value: i, label: i))
                                .toList(),
                            selectedValues: _instruments,
                            selectedLabel: (v) => v,
                            hint: 'Filtre instrumentos...',
                            loading: _optionsLoading,
                            onToggle: (v) => _toggle(_instruments, v,
                                (n) => setState(() => _instruments = n)),
                          ),
                        ),
                      ),
                    ),

                  const Divider(height: 1),
                  _CollapsibleHeader(
                    title: 'Localização',
                    subtitle:
                        _locationToggle ? 'Usando seu perfil' : _locationSummary,
                    expanded: _locationExpanded,
                    onTap: () => setState(
                        () => _locationExpanded = !_locationExpanded),
                  ),
                  if (_locationExpanded) ...[
                    IgnorePointer(
                      ignoring: _locationToggle,
                      child: Opacity(
                        opacity: _locationToggle ? 0.5 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 6),
                      child: Text('País',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151))),
                    ),
                    _PickerField(
                      options: _options.countries
                          .map((c) => FilterOption(value: c, label: c))
                          .toList(),
                      selectedValues: _countries,
                      selectedLabel: (v) => v,
                      hint: 'Filtre países...',
                      loading: _optionsLoading,
                      onToggle: (v) => _toggle(
                          _countries, v, (n) => setState(() => _countries = n)),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 14, bottom: 6),
                      child: Text('Estado',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151))),
                    ),
                    _PickerField(
                      options: _options.states,
                      selectedValues: _states,
                      selectedLabel: _stateLabel,
                      hint: 'Filtre estados...',
                      loading: _optionsLoading,
                      onToggle: (v) => _toggle(
                          _states, v, (n) => setState(() => _states = n)),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 14, bottom: 6),
                      child: Text('Cidade',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151))),
                    ),
                    _PickerField(
                      options: _options.cities
                          .map((c) => FilterOption(value: c, label: c))
                          .toList(),
                      selectedValues: _cities,
                      selectedLabel: (v) => v,
                      hint: 'Filtre cidades...',
                      loading: _optionsLoading,
                      onToggle: (v) =>
                          _toggle(_cities, v, (n) => setState(() => _cities = n)),
                    ),
                    const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ],
                  ],
                ),
              ),
            ),
          ),

          // ── Rodapé fixo ───────────────────────────────────────────
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _matchScale =
                            RangeValues(widget.matchScaleMin, widget.matchScaleMax);
                        _types = [];
                        _instrumentToggle = false;
                        _locationToggle = false;
                        _instruments = [];
                        _countries = [];
                        _states = [];
                        _cities = [];
                      });
                      _refreshOptions();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Limpar tudo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onApply(
                        types: _types,
                        instruments: _instruments,
                        countries: _countries,
                        states: _states,
                        cities: _cities,
                        stateLabels: Map.of(_stateLabels),
                        matchScale: _matchScale,
                        instrumentToggle: _instrumentToggle,
                        locationToggle: _locationToggle,
                      );
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _pink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Aplicar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha "Meu instrumento" / "Perto de Mim" — checkbox que liga/desliga o
/// filtro pelo perfil do usuário logado.
class _ToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: _pink,
          ),
        ],
      ),
    );
  }
}

/// Cabeçalho de seção recolhível (Instrumento / Localização), com resumo
/// opcional (ex: "(1) País • (1) Estado") e seta que indica expandido/não.
class _CollapsibleHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool expanded;
  final VoidCallback onTap;

  const _CollapsibleHeader({
    required this.title,
    this.subtitle,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.grey[500],
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ],
        ),
      ),
    );
  }
}

/// Campo de busca com autocomplete pra escolher (multi-seleção) valores de
/// uma lista (instrumento, país, estado, cidade) — cada valor escolhido
/// vira um chip removível acima do campo; escolher um novo ADICIONA à
/// seleção, não substitui a anterior.
class _PickerField extends StatefulWidget {
  final List<FilterOption> options;
  final List<String> selectedValues;
  final String Function(String value) selectedLabel;
  final String hint;
  final bool loading;
  final ValueChanged<String> onToggle;

  const _PickerField({
    required this.options,
    required this.selectedValues,
    required this.selectedLabel,
    required this.hint,
    required this.loading,
    required this.onToggle,
  });

  @override
  State<_PickerField> createState() => _PickerFieldState();
}

class _PickerFieldState extends State<_PickerField> {
  // Controller/focusNode próprios (em vez dos que o Autocomplete criaria
  // sozinho) só pra poder limpar o texto digitado depois de escolher uma
  // opção, sem perder o que foi selecionado.
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // RawAutocomplete só recalcula sua lista interna de opções quando o
  // valor do campo de texto muda de verdade — nunca só porque a lista
  // `available` (recomputada a cada build a partir de widget.selectedValues)
  // mudou. Sem isso, um item recém-selecionado (ou removido) só refletia
  // na lista na seleção seguinte. Agendamos pro fim do frame (depois que
  // este widget já recebeu a seleção atualizada) um vaivém de texto
  // imperceptível que força o recálculo, sem mexer no foco nem no texto
  // visível.
  void _refreshOptionsCache() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _controller.value;
      _controller.value = current.copyWith(text: String.fromCharCode(0x200B));
      _controller.value = current;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Só oferece como sugestão o que ainda não foi selecionado.
    final available = widget.options
        .where((o) => !widget.selectedValues.contains(o.value))
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.selectedValues.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.selectedValues
                      .map((v) => _RemovableChip(
                            label: widget.selectedLabel(v),
                            onRemove: () {
                              widget.onToggle(v);
                              _refreshOptionsCache();
                            },
                          ))
                      .toList(),
                ),
              ),
            RawAutocomplete<FilterOption>(
              textEditingController: _controller,
              focusNode: _focusNode,
              displayStringForOption: (o) => o.label,
              optionsBuilder: (textEditingValue) {
                final query = normalizeForSearch(textEditingValue.text);
                // Vazio (campo só recebeu foco, sem digitar nada) mostra
                // todas as opções disponíveis — funciona como um dropdown.
                if (query.isEmpty) return available;
                return available
                    .where((o) => normalizeForSearch(o.label).contains(query));
              },
              onSelected: (selection) {
                widget.onToggle(selection.value);
                // Limpa o campo e recolhe o drill-down, pra agilizar a
                // digitação/seleção do próximo filtro.
                _controller.clear();
                _focusNode.unfocus();
                _refreshOptionsCache();
              },
              fieldViewBuilder: (context, controller, focusNode, _) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: widget.loading ? 'Carregando...' : widget.hint,
                      hintStyle:
                          TextStyle(fontSize: 13, color: Colors.grey[400]),
                      // Clique na seta abre/recolhe o drill-down de opções,
                      // sem precisar digitar nada — ajuda a navegar entre
                      // vários campos de seleção.
                      suffixIcon: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (focusNode.hasFocus) {
                            focusNode.unfocus();
                          } else {
                            focusNode.requestFocus();
                          }
                        },
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            color: Colors.grey[400], size: 20),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                );
              },
              optionsViewBuilder: (context, onSelectedCb, opts) {
                final list = opts.toList();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Colors.white,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: list.length > 5 ? 220 : list.length * 44.0,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final option = list[index];
                          return ListTile(
                            dense: true,
                            title: Text(option.label,
                                style: const TextStyle(fontSize: 13)),
                            onTap: () => onSelectedCb(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Chip do valor selecionado, com "×" pra remover.
class _RemovableChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _RemovableChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _pink.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _pink.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.close_rounded, size: 13, color: _pink),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _pink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
