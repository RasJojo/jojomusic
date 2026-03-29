import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'providers.dart';

final spotifyIntegrationProvider =
    FutureProvider<SpotifyIntegration>((ref) async {
      return ref.watch(apiProvider).fetchSpotifyIntegration();
    });
