import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/convex_service.dart';
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
      final withConvex = await _upsertConvexUser(session);
      await _persistSession(withConvex);
      return withConvex;
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
      final withConvex = await _upsertConvexUser(session);
      await _persistSession(withConvex);
      return withConvex;
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

  /// Upsert l'utilisateur dans Convex et retourne la session enrichie du convexUserId.
  Future<AuthSession> _upsertConvexUser(AuthSession session) async {
    try {
      final convexId = await ConvexService.instance.upsertUser(
        externalId: session.user.id,
        name: session.user.name,
        email: session.user.email,
      );
      return session.withConvexUserId(convexId);
    } catch (_) {
      // Ne pas bloquer le login si Convex est indisponible
      return session;
    }
  }

  Future<void> _validateStoredSession(AuthSession session) async {
    final preferences = ref.read(sharedPreferencesProvider);
    try {
      final user = await ref
          .read(baseApiProvider)
          .withToken(session.accessToken)
          .fetchCurrentUser()
          .timeout(_sessionValidationTimeout);

      // Garantir que convexUserId est présent (migration sessions anciennes)
      var validated = AuthSession(
        accessToken: session.accessToken,
        user: user,
        convexUserId: session.convexUserId,
      );
      if (validated.convexUserId == null) {
        validated = await _upsertConvexUser(validated);
      }
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
