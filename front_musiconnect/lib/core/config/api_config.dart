/// Configuração central da URL do backend MusiConnect.
///
/// Por padrão o app usa a API pública (servidor de produção). Para testar
/// com a API rodando no próprio computador, passe o endereço no build:
///
///   flutter run --dart-define=API_URL=http://192.168.1.15:8000
///
/// (IP da máquina na rede Wi-Fi — `Get-NetIPAddress -AddressFamily IPv4`;
/// no emulador Android, http://10.0.2.2:8000.)
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.musiconnect.app.br',
  );

  // ── Endpoints ────────────────────────────────────────────────
  static const String nearby               = '$baseUrl/api/institutions/nearby';
  static const String all                  = '$baseUrl/api/institutions/all';
  static const String stats                = '$baseUrl/api/institutions/stats';
  // GET /api/institutions/{osm_id} e /api/institutions/{osm_id}/opportunities
  static const String institutions         = '$baseUrl/api/institutions';
  static const String health               = '$baseUrl/';
  static const String opportunities        = '$baseUrl/api/opportunities/';
  static const String opportunityFilterOptions = '$baseUrl/api/opportunities/filter-options';
  // GET /ids, /opportunities, /institutions; PUT/DELETE /opportunities/{id} e /institutions/{osm_id}
  static const String favorites            = '$baseUrl/api/favorites';
  // Resumo da aba Início
  static const String dashboard            = '$baseUrl/api/dashboard';

  // ── Autenticação (cadastro/login/confirmação de e-mail) ─────────
  static const String authSignup  = '$baseUrl/api/auth/signup';
  static const String authResend  = '$baseUrl/api/auth/resend';
  static const String authConfirm = '$baseUrl/api/auth/confirm';
  static const String authStatus  = '$baseUrl/api/auth/status';
  static const String authLogin   = '$baseUrl/api/auth/login';
  static const String authForgotPassword = '$baseUrl/api/auth/forgot-password';
  static const String authResetPassword  = '$baseUrl/api/auth/reset-password';
  static const String authMe             = '$baseUrl/api/auth/me';
  static const String authChangePassword = '$baseUrl/api/auth/change-password';
  static const String authLogout         = '$baseUrl/api/auth/logout';
  static const String authAcceptPrivacy  = '$baseUrl/api/auth/accept-privacy';

  // ── GeoNames (país/estado/cidade do cadastro) ──────────────────
  // Conta gratuita em https://www.geonames.org/login — depois de criar,
  // ative "Free Web Services" no perfil (geonames.org/manageaccount) e
  // troque o valor abaixo pelo seu username. A conta de demonstração
  // ("demo") fica sempre esgotada — não funciona pra uso real.
  static const String geoNamesUsername = 'laura.luchez';
  static const String geoNamesBaseUrl = 'https://secure.geonames.org';
}
