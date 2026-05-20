import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/convex_service.dart';
import '../models/app_models.dart';
import 'providers.dart';
import 'session_controller.dart';

/// État de lecture distant — mis à jour en temps réel via Convex WebSocket.
/// Utilisé pour la sync cross-device : si un autre appareil joue une musique,
/// ce provider reflète l'état de cet appareil en temps réel.
final remotePlaybackStateProvider =
    StreamProvider<RemotePlaybackState?>((ref) {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  final convexId = session?.convexUserId;
  if (convexId == null) {
    return Stream.value(null);
  }
  return ref.read(convexServiceProvider).watchPlaybackState(convexId);
});

/// Provider pour la dernière track jouée sur un autre appareil.
/// Utile pour proposer à l'utilisateur de reprendre la lecture là où
/// il s'était arrêté sur un autre device.
final crossDeviceTrackProvider = Provider<Track?>((ref) {
  final remote = ref.watch(remotePlaybackStateProvider).asData?.value;
  if (remote == null) return null;
  return remote.track;
});
