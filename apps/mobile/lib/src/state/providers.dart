import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/jojo_audio_handler.dart';
import '../config/app_environment.dart';
import '../data/api_service.dart';
import '../data/app_database.dart';
import 'session_controller.dart';

final environmentProvider = Provider<AppEnvironment>((ref) {
  throw UnimplementedError();
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError();
});

final audioHandlerProvider = Provider<JojoAudioHandler>((ref) {
  throw UnimplementedError();
});

final baseApiProvider = Provider<ApiService>((ref) {
  final environment = ref.watch(environmentProvider);
  return ApiService(environment: environment);
});

final connectivityStatusProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  bool resolveStatus(List<ConnectivityResult> results) {
    return !_isOfflineConnectivity(results);
  }

  yield resolveStatus(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(resolveStatus).distinct();
});

final apiProvider = Provider<ApiService>((ref) {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  return ref.watch(baseApiProvider).withToken(session?.accessToken);
});

final shellTabIndexProvider = NotifierProvider<ShellTabIndexNotifier, int>(
  ShellTabIndexNotifier.new,
);

class ShellTabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int value) {
    state = value.clamp(0, 2);
  }
}

bool _isOfflineConnectivity(List<ConnectivityResult> results) {
  return results.isEmpty ||
      (results.length == 1 && results.first == ConnectivityResult.none);
}
