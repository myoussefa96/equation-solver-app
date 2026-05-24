import 'package:equation_solver_app/state/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('advancedFunctionsEnabled defaults to false on first read', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final enabled = await container.read(advancedFunctionsEnabledProvider.future);
    expect(enabled, isFalse);
  });

  test('setAdvancedFunctionsEnabled persists across container disposal', () async {
    final c1 = ProviderContainer();
    await c1.read(appSettingsProvider.notifier).setAdvancedFunctionsEnabled(true);
    c1.dispose();

    SharedPreferences.setMockInitialValues({
      'palette.advancedFunctions': true,
    });
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);

    final enabled = await c2.read(advancedFunctionsEnabledProvider.future);
    expect(enabled, isTrue);
  });
}
