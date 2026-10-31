import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/presentation/view_models/dashboard_view_model.dart';
import 'package:prototipo_musiconnect/presentation/view_models/map_explorer_view_model.dart';
import 'package:prototipo_musiconnect/presentation/view_models/profile_view_model.dart';

import '../helpers/fakes.dart';

/// Sem serviços simulados, os ViewModels usam os de verdade (como no app).
void main() {
  test('Início', () {
    final vm = DashboardViewModel(user: fakeUser());
    expect(vm.firstName, 'Laura');
    vm.dispose();
    expect(vm.isDisposed, isTrue);
  });

  test('Perfil', () {
    final vm = ProfileViewModel(user: fakeUser());
    expect(vm.user.name, 'Laura Heloísa');
    vm.dispose();
  });

  test('Mapa', () {
    final vm = MapExplorerViewModel(filterGroups: const {'music_school': {'music_school'}});
    expect(vm.onlyWithOpportunities, isFalse);
    expect(vm.showCityMarkers, isTrue);
    vm.dispose();
  });
}
