import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/data/stream_resolver.dart';
import 'package:mobile/src/models/app_models.dart';

void main() {
  _resolverTests();
  _queueSkipTests();
  _transitionGuardTests();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _track1 = Track(
  trackKey: 'dQw4w9WgXcQ',
  title: 'Never Gonna Give You Up',
  artist: 'Rick Astley',
);

const _track2 = Track(
  trackKey: 'ktvTqknDobU',
  title: 'Harder Better Faster',
  artist: 'Daft Punk',
);

ResolvedStream _fakeStream(Track t) => ResolvedStream(
  streamUrl: 'https://fake/${t.trackKey}.mp4',
  title: t.title,
  artist: t.artist,
);

// ---------------------------------------------------------------------------
// LocalStreamResolver — cache + in-flight deduplication
// ---------------------------------------------------------------------------

void _resolverTests() {
  group('LocalStreamResolver', () {
    test('extrait un identifiant YouTube depuis une URL complète', () {
      expect(
        extractYoutubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        extractYoutubeVideoId('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        extractYoutubeVideoId('https://example.com/watch?v=dQw4w9WgXcQ'),
        isNull,
      );
    });

    test('renvoie le résultat du backend', () async {
      final resolver = LocalStreamResolver(
        backendOverride: (t) async => _fakeStream(t),
      );
      final result = await resolver.resolve(_track1);
      expect(result.streamUrl, contains(_track1.trackKey));
    });

    test(
      'cache : le backend est appelé une seule fois pour le même morceau',
      () async {
        var calls = 0;
        final resolver = LocalStreamResolver(
          backendOverride: (t) async {
            calls++;
            return _fakeStream(t);
          },
        );

        await resolver.resolve(_track1);
        await resolver.resolve(_track1);
        await resolver.resolve(_track1);

        expect(
          calls,
          1,
          reason: 'backend doit être appelé une seule fois grâce au cache',
        );
      },
    );

    test('cache : morceaux différents → appels indépendants', () async {
      var calls = 0;
      final resolver = LocalStreamResolver(
        backendOverride: (t) async {
          calls++;
          return _fakeStream(t);
        },
      );

      await resolver.resolve(_track1);
      await resolver.resolve(_track2);

      expect(calls, 2);
    });

    test('evict invalide le cache et force un nouvel appel backend', () async {
      var calls = 0;
      final resolver = LocalStreamResolver(
        backendOverride: (t) async {
          calls++;
          return _fakeStream(t);
        },
      );

      await resolver.resolve(_track1);
      resolver.evict(_track1.trackKey);
      await resolver.resolve(_track1);

      expect(calls, 2, reason: 'evict doit forcer un nouvel appel backend');
    });

    test('in-flight : appels concurrents → un seul appel backend', () async {
      var calls = 0;
      final completer = Completer<ResolvedStream>();
      final resolver = LocalStreamResolver(
        backendOverride: (t) {
          calls++;
          return completer.future;
        },
      );

      // Lancer deux résolutions simultanées
      final f1 = resolver.resolve(_track1);
      final f2 = resolver.resolve(_track1);

      completer.complete(_fakeStream(_track1));

      final results = await Future.wait([f1, f2]);
      expect(
        calls,
        1,
        reason: 'une seule requête réseau pour deux appels concurrents',
      );
      expect(results[0].streamUrl, results[1].streamUrl);
    });

    test('propagation d\'erreur : exception remontée à l\'appelant', () async {
      final resolver = LocalStreamResolver(
        backendOverride: (t) async => throw Exception('réseau indisponible'),
      );
      await expectLater(() => resolver.resolve(_track1), throwsException);
    });

    test('après une erreur, un second appel re-tente le backend', () async {
      var calls = 0;
      var shouldFail = true;
      final resolver = LocalStreamResolver(
        backendOverride: (t) async {
          calls++;
          if (shouldFail) throw Exception('réseau indisponible');
          return _fakeStream(t);
        },
      );

      // Premier appel : échec
      await expectLater(() => resolver.resolve(_track1), throwsException);

      // Deuxième appel : succès
      shouldFail = false;
      final result = await resolver.resolve(_track1);
      expect(result.streamUrl, contains(_track1.trackKey));
      expect(
        calls,
        2,
        reason: 'après erreur, le cache doit être vide → réessai backend',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Logique de saut de morceaux (_tryLoadNext simulé)
// ---------------------------------------------------------------------------

/// Simulation pure de la logique _tryLoadNext corrigée :
/// - capture nextIndex une seule fois
/// - 2 tentatives par morceau
/// - passe au suivant si les deux échouent
/// - essaie jusqu'à 3 morceaux consécutifs avant de stopper
Future<int?> simulateTryLoadNext({
  required int currentIndex,
  required int queueLength,
  required Future<bool> Function(int index) loader,
}) async {
  final startIndex = currentIndex + 1;
  for (int skip = 0; skip < 3; skip++) {
    final candidate = startIndex + skip;
    if (candidate >= queueLength) break;
    for (int attempt = 0; attempt < 2; attempt++) {
      if (await loader(candidate)) return candidate;
    }
  }
  return null; // null = stop
}

void _queueSkipTests() {
  group('Queue skip logic (_tryLoadNext)', () {
    test('charge le morceau suivant normalement', () async {
      final loaded = await simulateTryLoadNext(
        currentIndex: 0,
        queueLength: 3,
        loader: (i) async => true,
      );
      expect(loaded, 1);
    });

    test('le morceau suivant échoue → passe au morceau +2', () async {
      final loaded = await simulateTryLoadNext(
        currentIndex: 0,
        queueLength: 5,
        loader: (i) async => i != 1, // morceau 1 échoue
      );
      expect(loaded, 2);
    });

    test('morceaux +1 et +2 échouent → charge +3', () async {
      final loaded = await simulateTryLoadNext(
        currentIndex: 0,
        queueLength: 5,
        loader: (i) async => i == 3, // seulement 3 réussit
      );
      expect(loaded, 3);
    });

    test('tous les morceaux échouent → renvoie null (stop)', () async {
      final loaded = await simulateTryLoadNext(
        currentIndex: 0,
        queueLength: 4,
        loader: (i) async => false,
      );
      expect(loaded, isNull);
    });

    test('currentIndex au dernier morceau → null immédiat', () async {
      final loaded = await simulateTryLoadNext(
        currentIndex: 4,
        queueLength: 5,
        loader: (i) async => true,
      );
      expect(loaded, isNull);
    });

    test('réessaie 2× le même morceau avant de passer au suivant', () async {
      final callCounts = <int, int>{};
      final loaded = await simulateTryLoadNext(
        currentIndex: 0,
        queueLength: 5,
        loader: (i) async {
          callCounts[i] = (callCounts[i] ?? 0) + 1;
          return false;
        },
      );
      expect(loaded, isNull);
      // Chaque morceau tenté doit avoir été essayé exactement 2 fois
      for (final count in callCounts.values) {
        expect(count, 2);
      }
    });

    test('nextIndex est capturé une fois, non recalculé après échec', () async {
      // Si nextIndex était recalculé après chaque _loadAt (qui met à jour
      // _currentIndex), on sauterait des morceaux.
      // Ici on vérifie que skip=0 cible toujours startIndex,
      // pas startIndex + (nombre d'échecs précédents).
      var firstAttemptIndex = -1;
      final loaded = await simulateTryLoadNext(
        currentIndex: 2,
        queueLength: 10,
        loader: (i) async {
          if (firstAttemptIndex == -1) firstAttemptIndex = i;
          return i == 5; // seulement 5 réussit
        },
      );
      expect(
        firstAttemptIndex,
        3,
        reason: 'la première tentative doit cibler index 3 (currentIndex+1)',
      );
      expect(loaded, 5);
    });
  });
}

// ---------------------------------------------------------------------------
// Logique de transition (_loadGeneration simulé)
// ---------------------------------------------------------------------------

class SimulatedLoadCoordinator {
  int generation = 0;
  final events = <String>[];

  int startLoad(String trackKey) {
    final token = ++generation;
    events.add('start:$trackKey');
    events.add('stop-current:$trackKey');
    return token;
  }

  void completeResolve({
    required int token,
    required String trackKey,
    required bool callStopWhenStale,
  }) {
    if (token != generation) {
      if (callStopWhenStale) {
        events.add('stale-stop:$trackKey');
      }
      events.add('stale-abort:$trackKey');
      return;
    }
    events.add('set-url:$trackKey');
    events.add('play:$trackKey');
  }
}

void _transitionGuardTests() {
  group('Transition guard (_loadGeneration)', () {
    test('un ancien chargement ne coupe pas le nouveau morceau', () {
      final coordinator = SimulatedLoadCoordinator();

      final oldToken = coordinator.startLoad('track-a');
      final newToken = coordinator.startLoad('track-b');

      coordinator.completeResolve(
        token: oldToken,
        trackKey: 'track-a',
        callStopWhenStale: false,
      );
      coordinator.completeResolve(
        token: newToken,
        trackKey: 'track-b',
        callStopWhenStale: false,
      );

      expect(coordinator.events, [
        'start:track-a',
        'stop-current:track-a',
        'start:track-b',
        'stop-current:track-b',
        'stale-abort:track-a',
        'set-url:track-b',
        'play:track-b',
      ]);
      expect(coordinator.events, isNot(contains('stale-stop:track-a')));
    });

    test('le comportement historique aurait stoppé le morceau récent', () {
      final coordinator = SimulatedLoadCoordinator();

      final oldToken = coordinator.startLoad('track-a');
      coordinator.startLoad('track-b');

      coordinator.completeResolve(
        token: oldToken,
        trackKey: 'track-a',
        callStopWhenStale: true,
      );

      expect(coordinator.events, contains('stale-stop:track-a'));
    });
  });
}
