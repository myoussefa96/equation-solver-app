import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAdvancedFunctions = 'palette.advancedFunctions';

class AppSettings {
  const AppSettings({required this.advancedFunctionsEnabled});
  final bool advancedFunctionsEnabled;
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      advancedFunctionsEnabled: prefs.getBool(_kAdvancedFunctions) ?? false,
    );
  }

  Future<void> setAdvancedFunctionsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAdvancedFunctions, value);
    state = AsyncData(AppSettings(advancedFunctionsEnabled: value));
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

final advancedFunctionsEnabledProvider = FutureProvider<bool>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  return settings.advancedFunctionsEnabled;
});
