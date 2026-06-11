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
      final resolved = await _resolveConvexId(session);
      await _persistSession(resolved);
      return resolved;
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
      final resolved = await _resolveConvexId(session);
      await _persistSession(resolved);
      return resolved;
    });
  }

  /// Ensures the session has a valid Convex _id (not a NestJS UUID).
  Future<AuthSession> _resolveConvexId(AuthSession session) async {
    final existing = session.convexUserId;
    if (existing != null && !existing.contains('-')) return session;
    try {
      final convexId = await ConvexService.instance.upsertUser(
        externalId: session.user.id,
        name: session.user.name,
        email: session.user.email,
      );
      return session.withConvexUserId(convexId);
    } catch (_) {
      return session;
    }
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

      // Resolve the real Convex _id via upsertUser when:
      // - convexUserId was never stored (pre-migration sessions), or
      // - it was incorrectly stored as the NestJS UUID (contains '-').
      // upsertByExternalId is idempotent — safe to call on every validation.
      String? convexUserId = session.convexUserId;
      if (convexUserId == null || convexUserId.contains('-')) {
        try {
          convexUserId = await ConvexService.instance.upsertUser(
            externalId: user.id,
            name: user.name,
            email: user.email,
          );
        } catch (_) {
          // Convex unreachable — proceed without it; library will fall back to HTTP.
        }
      }

      final validated = AuthSession(
        accessToken: session.accessToken,
        user: user,
        convexUserId: convexUserId,
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
