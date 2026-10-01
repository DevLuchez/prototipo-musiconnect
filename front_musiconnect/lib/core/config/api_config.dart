/// Configuração central da URL do backend MusiConnect.
///
/// Em desenvolvimento local:
///   - Emulador Android → use _androidEmulatorUrl
///   - Simulador iOS / Web / Desktop → use _localhostBaseUrl
///   - Dispositivo físico na mesma rede → use _deviceBaseUrl (IP da máquina)
///
/// Para produção, troque por uma URL pública (ex: https://api.musiconnect.app).
class ApiConfig {
  ApiConfig._();

  // ── URLs por ambiente ────────────────────────────────────────
  static const String _localhostBaseUrl   = 'http://localhost:8000';
  static const String _androidEmulatorUrl = 'http://10.0.2.2:8000';
  // IP atual da máquina na rede Wi-Fi (rodar: Get-NetIPAddress -AddressFamily IPv4)
  // Atenção: esse IP muda se a rede Wi-Fi mudar ou o DHCP renovar o lease —
  // se o app voltar a acusar timeout, confira esse valor de novo.
  static const String _deviceBaseUrl      = 'http://192.168.1.8:8000';

  static const String baseUrl = _deviceBaseUrl; // celular físico na mesma Wi-Fi

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

  // ── GeoNames (país/estado/cidade do cadastro) ──────────────────
  // Conta gratuita em https://www.geonames.org/login — depois de criar,
  // ative "Free Web Services" no perfil (geonames.org/manageaccount) e
  // troque o valor abaixo pelo seu username. A conta de demonstração
  // ("demo") fica sempre esgotada — não funciona pra uso real.
  static const String geoNamesUsername = 'laura.luchez';
  static const String geoNamesBaseUrl = 'http://api.geonames.org';
}
