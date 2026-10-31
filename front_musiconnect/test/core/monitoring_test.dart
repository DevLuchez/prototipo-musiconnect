import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/core/monitoring.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sem Firebase, o app segue e respeita a escolha salva', () async {
    SharedPreferences.setMockInitialValues({'usage_data_enabled': false});

    await Monitoring.init();
    expect(Monitoring.usageDataEnabled.value, isFalse);

    // Sem Firebase, os registros não fazem nada (e não quebram).
    Monitoring.logEvent('save_opportunity', {'type': 'curso'});
    Monitoring.logScreen('Início');
    Monitoring.recordError(Exception('x'), StackTrace.current, reason: 'teste');
  });

  test('ligar/desligar o envio fica salvo no aparelho', () async {
    SharedPreferences.setMockInitialValues({});

    await Monitoring.setUsageDataEnabled(false);
    expect(Monitoring.usageDataEnabled.value, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('usage_data_enabled'), isFalse);

    await Monitoring.setUsageDataEnabled(true);
    expect((await SharedPreferences.getInstance()).getBool('usage_data_enabled'), isTrue);
  });
}
