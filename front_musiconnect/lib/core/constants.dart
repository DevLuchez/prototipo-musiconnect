// Cores e constantes globais

/// Lista curada de instrumentos oferecida no cadastro (e reaproveitável em
/// outras telas, como edição de perfil).
///
/// Ancorada nos valores reais já usados em `/api/opportunities/filter-options`
/// (deduplicando variantes como "Clarinete"/"Clarinetas" e "Fagot"/"Fagote",
/// e removendo categorias de vaga que não são instrumentos, como "Cordas" ou
/// "Sopros"), acrescida de instrumentos populares ainda ausentes desse
/// dataset (hoje bem voltado a orquestra/clássico). Isso maximiza a
/// compatibilidade de string com as oportunidades existentes para quando o
/// matching perfil↔oportunidade for implementado.
const List<String> kInstrumentOptions = [
  'Baixo', // ainda ausente do dataset atual, sem oportunidades atuais
  'Bateria', // ainda ausente do dataset atual, sem oportunidades atuais
  'Clarinete',
  'Contrabaixo',
  'Corne Inglês',
  'Cornet',
  'Cravo',
  'Eufônio',
  'Fagote',
  'Flauta',
  'Guitarra', // ainda ausente do dataset atual, sem oportunidades atuais
  'Harpa',
  'Oboé',
  'Órgão',
  'Percussão',
  'Piano',
  'Piccolo',
  'Saxofone',
  'Teclado', // ainda ausente do dataset atual, sem oportunidades atuais
  'Trombone',
  'Trompa',
  'Trompete',
  'Tuba',
  'Tímpanos',
  'Ukulele', // ainda ausente do dataset atual, sem oportunidades atuais
  'Viola',
  'Violino',
  'Violoncelo',
  'Violão',
  'Vocal',
];
