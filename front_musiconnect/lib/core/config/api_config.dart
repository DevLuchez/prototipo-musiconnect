/// Configuração central da URL do backend MusiConnect.
///
/// Em desenvolvimento local:
///   - Emulador Android → use androidEmulatorBaseUrl
///   - Simulador iOS / Web / Desktop → use localhostBaseUrl
///   - Dispositivo físico na mesma rede → use deviceBaseUrl (IP da máquina)
///
/// Para produção, troque por uma URL pública (ex: https://api.musiconnect.app).
class ApiConfig {
  ApiConfig._();

  // ── URLs por ambiente ────────────────────────────────────────
  static const String _localhostBaseUrl    = 'http://localhost:8000';
  static const String _androidEmulatorUrl  = 'http://10.0.2.2:8000';
  // IP da máquina na rede Wi-Fi local (detectado automaticamente):
  static const String _deviceBaseUrl       = 'http://192.168.1.18:8000';

  /// URL ativa — altere aqui para trocar de ambiente.
  static const String baseUrl = _deviceBaseUrl; // dispositivo físico na mesma rede Wi-Fi

  // ── Endpoints ────────────────────────────────────────────────
  static const String nearby = '$baseUrl/api/institutions/nearby';
  static const String all    = '$baseUrl/api/institutions/all';
  static const String stats  = '$baseUrl/api/institutions/stats';
  static const String health = '$baseUrl/';
}
