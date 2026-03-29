import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'providers.dart';

const _sessionStorageKey = 'jojomusic.session';
const _sessionValidationTimeout = Duration(seconds: 2);

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, AuthSession?>(
      SessionController.new,
    );

class SessionController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    final preferences = ref.read(sharedPreferencesProvider);
    final encoded = preferences.getString(_sessionStorageKey);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    final session = AuthSession.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
    unawaited(_validateStoredSession(session));
    return session;
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await ref
          .read(baseApiProvider)
          .login(email: email, password: password);
      await _persistSession(session);
      return session;
    });
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await ref
          .read(baseApiProvider)
          .register(name: name, email: email, password: password);
      await _persistSession(session);
      return session;
    });
  }

  Future<void> logout() async {
    await ref.read(sharedPreferencesProvider).remove(_sessionStorageKey);
    state = const AsyncData(null);
  }

  Future<void> _persistSession(AuthSession session) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_sessionStorageKey, jsonEncode(session.toJson()));
  }

  Future<void> _validateStoredSession(AuthSession session) async {
    final preferences = ref.read(sharedPreferencesProvider);
    try {
      final user = await ref
          .read(baseApiProvider)
          .withToken(session.accessToken)
          .fetchCurrentUser()
          .timeout(_sessionValidationTimeout);
      final validated = AuthSession(
        accessToken: session.accessToken,
        user: user,
      );
      await _persistSession(validated);
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(validated);
    } on TimeoutException {
      return;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        await preferences.remove(_sessionStorageKey);
        if (!ref.mounted) {
          return;
        }
        state = const AsyncData(null);
      }
    }
  }
}
