const _kWithDiacritics =
    'ÀÁÂÃÄÅàáâãäåÒÓÔÕÖòóôõöÈÉÊËèéêëÇçÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
const _kWithoutDiacritics =
    'AAAAAAaaaaaaOOOOOoooooEEEEeeeeCcIIIIiiiiUUUUuuuuNnSsYyyZz';

/// Remove acentos/diacríticos comuns (á→a, ç→c, ã→a...), pra permitir
/// busca que ignora acentuação (ex: digitar "sao paulo" encontra
/// "São Paulo").
String stripDiacritics(String input) {
  var result = input;
  for (var i = 0; i < _kWithDiacritics.length; i++) {
    result = result.replaceAll(_kWithDiacritics[i], _kWithoutDiacritics[i]);
  }
  return result;
}

/// [stripDiacritics] + minúsculas — normalização padrão pra comparar
/// texto de busca contra os nomes das opções de um campo.
String normalizeForSearch(String input) => stripDiacritics(input).toLowerCase();
