import 'dart:convert';
import 'package:flutter/services.dart';
import '../place_model.dart';

/// Carrega o dataset curado de instituições musicais globais
/// embutido no app como asset. Sem internet, sem API, sem limite de zoom.
class CuratedInstitutionsService {
  static List<PlaceModel>? _cache;

  Future<List<PlaceModel>> loadAll() async {
    if (_cache != null) return _cache!;

    final raw = await rootBundle.loadString('assets/data/music_institutions.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    final list = (data['institutions'] as List<dynamic>)
        .map((e) => _fromJson(e as Map<String, dynamic>))
        .toList();

    _cache = list;
    print('[Curated] ${list.length} instituições carregadas do dataset local.');
    return list;
  }

  PlaceModel _fromJson(Map<String, dynamic> j) => PlaceModel(
        id: 'curated_${j['id']}',
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        category: j['category'] as String,
        address: '${j['city']}, ${j['country']}',
      );
}
