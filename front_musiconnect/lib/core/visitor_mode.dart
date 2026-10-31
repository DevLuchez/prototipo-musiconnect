/// Modo visitante: usar o app sem conta, só para conhecê-lo.
///
/// Fica só na memória, de propósito: some quando o app é encerrado, e na
/// próxima abertura a pessoa volta à tela de boas-vindas — o visitante não
/// substitui o cadastro. As telas que recebem o usuário consultam
/// `AuthUser.isVisitor`; esta flag serve às peças que aparecem em todo lugar
/// e não recebem o usuário (card de oportunidade, coração de favoritar).
class VisitorMode {
  VisitorMode._();

  static bool active = false;
}
