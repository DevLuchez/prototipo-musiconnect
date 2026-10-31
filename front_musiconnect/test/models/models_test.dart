import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/models/opportunity_model.dart';
import 'package:prototipo_musiconnect/data/models/place_model.dart';

void main() {
  group('OpportunityModel.fromJson', () {
    test('lê todos os campos do backend', () {
      final opp = OpportunityModel.fromJson({
        'id': 7,
        'title': 'Audição',
        'type': 'audicao',
        'source_url': 'https://x.org/1',
        'source_name': 'Musical Chairs',
        'description': 'Desc',
        'raw_text': 'Texto',
        'institution': 'Orquestra',
        'institution_id': 'node_1',
        'city_location_id': 3,
        'instruments': ['Violino', 'Viola'],
        'country': 'Brasil',
        'state': 'SC',
        'city': 'Joinville',
        'is_remote': false,
        'is_active': true,
        'llm_confidence': 0.9,
        'deadline': '2026-12-01',
        'scraped_at': '2026-10-30T10:00:00',
        'match_percentage': 88,
        'match_breakdown': {
          'instrument': 45, 'affinity': 20, 'location': 15, 'confidence': 8,
          'instrument_max': 45, 'affinity_max': 25, 'location_max': 20, 'confidence_max': 10,
        },
        'saved_at': '2026-10-29T12:00:00',
      });

      expect(opp.id, 7);
      expect(opp.instruments, ['Violino', 'Viola']);
      expect(opp.deadline, DateTime(2026, 12, 1));
      expect(opp.matchPercentage, 88);
      expect(opp.matchBreakdown!.instrument, 45);
      expect(opp.matchBreakdown!.confidenceMax, 10);
      expect(opp.savedAt, isNotNull);
      expect(opp.sourceLabel, 'Musical Chairs');
    });

    test('campos ausentes ficam com o padrão', () {
      final opp = OpportunityModel.fromJson({'id': 1});
      expect(opp.title, '');
      expect(opp.instruments, isEmpty);
      expect(opp.isActive, isTrue);
      expect(opp.llmConfidence, 0);
      expect(opp.deadline, isNull);
      expect(opp.matchBreakdown, isNull);
      expect(opp.sourceLabel, 'Desconhecido');
    });

    test('instrumentos também aceitam texto separado por vírgulas', () {
      expect(OpportunityModel.fromJson({'id': 1, 'instruments': 'Piano, Flauta,'}).instruments,
          ['Piano', 'Flauta']);
      expect(OpportunityModel.fromJson({'id': 1, 'instruments': ''}).instruments, isEmpty);
      expect(OpportunityModel.fromJson({'id': 1, 'instruments': 3}).instruments, isEmpty);
    });

    test('data inválida vira null', () {
      expect(OpportunityModel.fromJson({'id': 1, 'deadline': 'amanhã'}).deadline, isNull);
    });
  });

  group('OpportunityModel — rótulos', () {
    OpportunityModel opp({String? type, String? city, String? state, String? country,
            bool remote = false, String? institutionId, int? cityId}) =>
        OpportunityModel(id: 1, title: 'x', type: type, city: city, state: state,
            country: country, isRemote: remote, institutionId: institutionId,
            cityLocationId: cityId);

    test('tipo por extenso, com ou sem acento', () {
      expect(opp(type: 'curso').typeLabel, 'Curso');
      expect(opp(type: 'competição').typeLabel, 'Competição');
      expect(opp(type: 'COMPETICAO').typeLabel, 'Competição');
      expect(opp(type: 'audição').typeLabel, 'Audição');
      expect(opp(type: 'emprego').typeLabel, 'Emprego');
      expect(opp(type: 'masterclass').typeLabel, 'Masterclass');
      expect(opp().typeLabel, 'Oportunidade');
    });

    test('local por extenso', () {
      expect(opp(city: 'Joinville', state: 'SC', country: 'Brasil').locationLabel,
          'Joinville, SC, Brasil');
      expect(opp(city: '', country: 'Japão').locationLabel, 'Japão');
      expect(opp(remote: true).locationLabel, 'Remoto');
      expect(opp().locationLabel, 'Endereço não informado');
    });

    test('aparece no mapa se tem pino ou cidade e não é remota', () {
      expect(opp(institutionId: 'node_1').isOnMap, isTrue);
      expect(opp(cityId: 2).isOnMap, isTrue);
      expect(opp(cityId: 2, remote: true).isOnMap, isFalse);
      expect(opp().isOnMap, isFalse);
    });
  });

  group('PlaceModel.fromBackend', () {
    test('lê a instituição do backend', () {
      final place = PlaceModel.fromBackend({
        'osm_id': 'way_256649111',
        'name': 'SCAR – Sociedade Cultura Artística',
        'address': 'Rua Jorge Czerniewicz',
        'lat': -26.48,
        'lng': -49.07,
        'category': 'arts_centre',
        'verified': true,
        'website': 'https://scar.art.br',
        'email': 'contato@scar.art.br',
        'wikidata_id': 'Q1',
        'mb_id': 'mb',
        'active_opportunities_count': 2,
        'saved_at': '2026-10-01T00:00:00',
      });

      expect(place.id, 'backend_way_256649111');
      expect(place.osmId, 'way_256649111');
      expect(place.hasActiveOpportunities, isTrue);
      expect(place.categoryLabel, 'Centro Cultural');
      expect(place.savedAt, DateTime(2026, 10, 1));
    });

    test('sem coordenadas é descartada', () {
      expect(PlaceModel.tryFromBackend({'name': 'X', 'lat': 0, 'lng': 0}), isNull);
      expect(PlaceModel.tryFromBackend({'name': 'X'}), isNull);
    });

    test('padrões e rótulos de categoria', () {
      final place = PlaceModel.fromBackend({'lat': 1, 'lng': 1});
      expect(place.name, 'Local Musical');
      expect(place.category, 'music');
      expect(place.hasActiveOpportunities, isFalse);

      String label(String c) => PlaceModel(id: 'x', name: 'x', lat: 1, lng: 1, category: c).categoryLabel;
      expect(label('music_school'), 'Escola de Música');
      expect(label('theatre'), 'Teatro');
      expect(label('music_org'), 'Orquestra / Festival');
      expect(label('desconhecida'), 'Local Musical');
    });
  });
}
