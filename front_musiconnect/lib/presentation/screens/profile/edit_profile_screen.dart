import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../data/models/providers/auth_service.dart';
import '../../../data/models/providers/geo_service.dart';
import '../../widgets/auth/auth_common.dart';

/// Edição de perfil: reaproveita os mesmos campos dos passos 1 e 2 do
/// cadastro (interesses + localização), mas numa única tela — e já
/// pré-carregada com os dados atuais do usuário, incluindo a cascata de
/// país/estado/cidade (que precisa buscar os códigos certos no GeoNames
/// antes de poder selecionar o valor salvo).
class EditProfileScreen extends StatefulWidget {
  final AuthUser user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _nameController = TextEditingController(text: widget.user.name);
  late List<String> _selectedInstruments = List.of(widget.user.instruments);
  late bool _isProfessional = widget.user.isProfessional;
  late bool _isStudent = widget.user.isStudent;

  final _geoService = GeoService();
  List<GeoOption> _countries = [];
  bool _countriesLoading = true;
  GeoOption? _selectedCountry;
  List<GeoOption> _states = [];
  bool _statesLoading = false;
  GeoOption? _selectedState;
  List<GeoOption> _cities = [];
  bool _citiesLoading = false;
  GeoOption? _selectedCity;

  final _authService = AuthService();
  bool _saving = false;
  String? _error;

  bool get _nameValid => _nameController.text.trim().isNotEmpty;
  bool get _instrumentsValid => _selectedInstruments.isNotEmpty;
  bool get _ramoValid => _isProfessional || _isStudent;
  bool get _locationValid => _selectedCountry != null;
  bool get _formValid => _nameValid && _instrumentsValid && _ramoValid && _locationValid;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onChanged);
    _loadAndPrefillLocation();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _nameController.removeListener(_onChanged);
    _nameController.dispose();
    super.dispose();
  }

  // Encontra, numa lista de opções do GeoNames, a que corresponde ao nome
  // salvo no perfil (comparação sem diferenciar maiúsculas/minúsculas —
  // o GeoNames e o texto salvo podem variar em capitalização).
  GeoOption? _matchByName(List<GeoOption> options, String? name) {
    if (name == null || name.isEmpty) return null;
    for (final o in options) {
      if (o.name.toLowerCase() == name.toLowerCase()) return o;
    }
    return null;
  }

  // Carrega países/estados/cidades em cascata e já seleciona os valores
  // salvos no perfil em cada nível, conforme disponíveis.
  Future<void> _loadAndPrefillLocation() async {
    setState(() => _countriesLoading = true);
    final countries = await _geoService.fetchCountries();
    if (!mounted) return;
    final matchedCountry = _matchByName(countries, widget.user.country);
    setState(() {
      _countries = countries;
      _countriesLoading = false;
      _selectedCountry = matchedCountry;
    });

    if (matchedCountry?.countryCode == null) return;
    setState(() => _statesLoading = true);
    final states = await _geoService.fetchStates(matchedCountry!.countryCode!);
    if (!mounted) return;
    final matchedState = _matchByName(states, widget.user.state);
    setState(() {
      _states = states;
      _statesLoading = false;
      _selectedState = matchedState;
    });

    if (matchedState?.adminCode1 == null) return;
    setState(() => _citiesLoading = true);
    final cities = await _geoService.fetchCities(
      matchedCountry.countryCode!,
      matchedState!.adminCode1!,
    );
    if (!mounted) return;
    final matchedCity = _matchByName(cities, widget.user.city);
    setState(() {
      _cities = cities;
      _citiesLoading = false;
      _selectedCity = matchedCity;
    });
  }

  Future<void> _onCountrySelected(GeoOption? country) async {
    setState(() {
      _selectedCountry = country;
      // Troca de país invalida estado/cidade já escolhidos.
      _selectedState = null;
      _selectedCity = null;
      _states = [];
      _cities = [];
    });
    if (country?.countryCode == null) return;
    setState(() => _statesLoading = true);
    final states = await _geoService.fetchStates(country!.countryCode!);
    if (!mounted || country != _selectedCountry) return;
    setState(() {
      _states = states;
      _statesLoading = false;
    });
  }

  Future<void> _onStateSelected(GeoOption? state) async {
    setState(() {
      _selectedState = state;
      // Troca de estado invalida a cidade já escolhida.
      _selectedCity = null;
      _cities = [];
    });
    if (state?.adminCode1 == null || _selectedCountry?.countryCode == null) return;
    setState(() => _citiesLoading = true);
    final cities = await _geoService.fetchCities(
      _selectedCountry!.countryCode!,
      state!.adminCode1!,
    );
    if (!mounted || state != _selectedState) return;
    setState(() {
      _cities = cities;
      _citiesLoading = false;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _authService.updateProfile(
        name: _nameController.text.trim(),
        instruments: _selectedInstruments,
        isProfessional: _isProfessional,
        isStudent: _isStudent,
        country: _selectedCountry?.name,
        state: _selectedState?.name,
        city: _selectedCity?.name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    AuthBackButton(onTap: () => Navigator.of(context).pop()),
                    const Expanded(child: Center(child: AuthLogo(fontSize: 17))),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Editar perfil',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: kAuthTextDark,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AuthTextField(
                      label: 'Nome de usuário',
                      hint: 'Digite seu nome',
                      controller: _nameController,
                      required: true,
                    ),
                    const SizedBox(height: 20),
                    const SectionLabel(
                      title: 'Instrumentos',
                      subtitle:
                          'Selecione o(s) instrumento(s) que você tem experiência ou interesse em aprender.',
                      required: true,
                    ),
                    const SizedBox(height: 8),
                    AuthMultiSelectField(
                      hint: 'Selecione instrumento(s)...',
                      options: kInstrumentOptions,
                      selected: _selectedInstruments,
                      onChanged: (v) => setState(() => _selectedInstruments = v),
                    ),
                    const SizedBox(height: 20),
                    const SectionLabel(
                      title: 'Ramo de atuação',
                      subtitle:
                          'Selecione o(s) ramo(s) onde você deseja encontrar oportunidades como musicista.',
                      required: true,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        CheckRow(
                          label: 'Profissional',
                          value: _isProfessional,
                          onChanged: (v) => setState(() => _isProfessional = v),
                        ),
                        const SizedBox(width: 24),
                        CheckRow(
                          label: 'Estudante',
                          value: _isStudent,
                          onChanged: (v) => setState(() => _isStudent = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    AuthSingleSelectField<GeoOption>(
                      label: 'País',
                      hint: 'Selecione o país onde você mora',
                      required: true,
                      options: _countries,
                      selected: _selectedCountry,
                      displayString: (o) => o.name,
                      loading: _countriesLoading,
                      onChanged: _onCountrySelected,
                    ),
                    const SizedBox(height: 16),
                    AuthSingleSelectField<GeoOption>(
                      label: 'Estado',
                      hint: _selectedCountry == null
                          ? 'Selecione o país primeiro'
                          : 'Selecione o estado onde você mora',
                      options: _states,
                      selected: _selectedState,
                      displayString: (o) => o.name,
                      enabled: _selectedCountry != null,
                      loading: _statesLoading,
                      onChanged: _onStateSelected,
                    ),
                    const SizedBox(height: 16),
                    AuthSingleSelectField<GeoOption>(
                      label: 'Cidade',
                      hint: _selectedState == null
                          ? 'Selecione o estado primeiro'
                          : 'Selecione a cidade onde você mora',
                      options: _cities,
                      selected: _selectedCity,
                      displayString: (o) => o.name,
                      enabled: _selectedState != null,
                      loading: _citiesLoading,
                      onChanged: (v) => setState(() => _selectedCity = v),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: AuthPrimaryButton(
                        label: 'Salvar',
                        loading: _saving,
                        onPressed: _formValid ? _save : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
