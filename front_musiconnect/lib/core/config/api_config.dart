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
  static const String _deviceBaseUrl      = 'http://192.168.33.3:8000';

  static const String baseUrl = _deviceBaseUrl; // celular físico na mesma Wi-Fi

  // ── Endpoints ────────────────────────────────────────────────
  static const String nearby               = '$baseUrl/api/institutions/nearby';
  static const String all                  = '$baseUrl/api/institutions/all';
  static const String stats                = '$baseUrl/api/institutions/stats';
  static const String institutionSearch    = '$baseUrl/api/institutions/search';
  static const String institutionCreate    = '$baseUrl/api/institutions/create';
  static const String health               = '$baseUrl/';
  static const String opportunities        = '$baseUrl/api/opportunities/';
  static const String opportunityFilterOptions = '$baseUrl/api/opportunities/filter-options';
}
