/// Tipos de oportunidade conhecidos: slug (usado na API e nos filtros) →
/// rótulo em português. Fonte única usada tanto pelos carrosséis dentro da
/// aba "Todas as oportunidades" quanto pelo FilterModal, pra não haver dois
/// lugares com listas de tipos que podem divergir.
const Map<String, String> kOpportunityTypeLabels = {
  'emprego': 'Emprego',
  'curso': 'Curso',
  'competicao': 'Competição',
  'audicao': 'Audição',
};

/// Mesmos tipos, no plural em minúsculo — usado em frases como "Busque
/// por audições..." dentro da subpágina de uma categoria.
const Map<String, String> kOpportunityTypePluralLabels = {
  'emprego': 'empregos',
  'curso': 'cursos',
  'competicao': 'competições',
  'audicao': 'audições',
};

/// Detalhamento do [OpportunityModel.matchPercentage] — quantos pontos cada
/// fator contribuiu, de um máximo próprio (`*Max` — pesos diferentes por
/// fator, não uma fração de 100 cada); a soma dos quatro `instrument`/
/// `affinity`/`location`/`confidence` é o próprio matchPercentage
/// (arredondamento feito por fator no backend, então bate exatamente, sem
/// sobra).
class MatchBreakdown {
  final int instrument;
  final int affinity;
  final int location;
  final int confidence;
  final int instrumentMax;
  final int affinityMax;
  final int locationMax;
  final int confidenceMax;

  const MatchBreakdown({
    required this.instrument,
    required this.affinity,
    required this.location,
    required this.confidence,
    required this.instrumentMax,
    required this.affinityMax,
    required this.locationMax,
    required this.confidenceMax,
  });

  factory MatchBreakdown.fromJson(Map<String, dynamic> json) => MatchBreakdown(
        instrument: json['instrument'] as int? ?? 0,
        affinity: json['affinity'] as int? ?? 0,
        location: json['location'] as int? ?? 0,
        confidence: json['confidence'] as int? ?? 0,
        instrumentMax: json['instrument_max'] as int? ?? 0,
        affinityMax: json['affinity_max'] as int? ?? 0,
        locationMax: json['location_max'] as int? ?? 0,
        confidenceMax: json['confidence_max'] as int? ?? 0,
      );
}

/// Modelo de uma oportunidade musical retornada pela API.
class OpportunityModel {
  final int id;
  final String title;
  final String? type;
  final String? sourceUrl;
  final String? sourceName;
  final String? description;
  final String? rawText;
  final String? institution;
  // Pino do mapa da organizadora (osm_id) — null quando remota, sem
  // organizadora identificada ou ainda não localizada pelo backend.
  final String? institutionId;
  // Marcador "oportunidades por cidade" do mapa — usado quando não há
  // [institutionId] (organizadora sem localização exata).
  final int? cityLocationId;
  final List<String> instruments;
  final String? country;
  final String? state;
  final String? city;
  final bool isRemote;
  final bool isActive;
  final double llmConfidence;
  final DateTime? deadline;
  final DateTime? scrapedAt;
  // Percentual de compatibilidade (0-100) com o usuário logado, calculado
  // pelo backend — null se a requisição não foi autenticada.
  final int? matchPercentage;
  final MatchBreakdown? matchBreakdown;
  // Quando o usuário salvou — só vem na lista de oportunidades salvas.
  final DateTime? savedAt;

  const OpportunityModel({
    required this.id,
    required this.title,
    this.type,
    this.sourceUrl,
    this.sourceName,
    this.description,
    this.rawText,
    this.institution,
    this.institutionId,
    this.cityLocationId,
    this.instruments = const [],
    this.country,
    this.state,
    this.city,
    this.isRemote = false,
    this.isActive = true,
    this.llmConfidence = 0.0,
    this.deadline,
    this.scrapedAt,
    this.matchPercentage,
    this.matchBreakdown,
    this.savedAt,
  });

  factory OpportunityModel.fromJson(Map<String, dynamic> json) {
    // Instrumentos: pode vir como lista JSON ou como string separada por vírgulas
    List<String> parseInstruments(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is String && raw.isNotEmpty) {
        return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    return OpportunityModel(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      type: json['type'] as String?,
      sourceUrl: json['source_url'] as String?,
      sourceName: json['source_name'] as String?,
      description: json['description'] as String?,
      rawText: json['raw_text'] as String?,
      institution: json['institution'] as String?,
      institutionId: json['institution_id'] as String?,
      cityLocationId: json['city_location_id'] as int?,
      instruments: parseInstruments(json['instruments']),
      country: json['country'] as String?,
      state: json['state'] as String?,
      city: json['city'] as String?,
      isRemote: json['is_remote'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      llmConfidence: (json['llm_confidence'] as num?)?.toDouble() ?? 0.0,
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'] as String)
          : null,
      scrapedAt: json['scraped_at'] != null
          ? DateTime.tryParse(json['scraped_at'] as String)
          : null,
      matchPercentage: json['match_percentage'] as int?,
      matchBreakdown: json['match_breakdown'] != null
          ? MatchBreakdown.fromJson(
              json['match_breakdown'] as Map<String, dynamic>)
          : null,
      savedAt: json['saved_at'] != null
          ? DateTime.tryParse(json['saved_at'] as String)
          : null,
    );
  }

  /// Se a oportunidade tem onde aparecer no mapa: no pino da instituição
  /// ou, na falta dele, no marcador da cidade.
  bool get isOnMap =>
      !isRemote && (institutionId != null || cityLocationId != null);

  /// Label amigável para exibição do tipo da oportunidade.
  String get typeLabel {
    switch (type?.toLowerCase()) {
      case 'curso':
        return 'Curso';
      case 'competicao':
      case 'competição':
        return 'Competição';
      case 'audicao':
      case 'audição':
        return 'Audição';
      case 'emprego':
        return 'Emprego';
      default:
        return type != null ? _capitalize(type!) : 'Oportunidade';
    }
  }

  /// Nome da fonte formatado.
  String get sourceLabel => sourceName ?? 'Desconhecido';

  /// Localização composta (país + estado + cidade).
  String get locationLabel {
    final parts = <String>[
      if (city != null && city!.isNotEmpty) city!,
      if (state != null && state!.isNotEmpty) state!,
      if (country != null && country!.isNotEmpty) country!,
    ];
    if (parts.isEmpty) return isRemote ? 'Remoto' : 'Endereço não informado';
    return parts.join(', ');
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
