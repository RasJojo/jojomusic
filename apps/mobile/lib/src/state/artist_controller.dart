import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'providers.dart';

final artistDetailsProvider = FutureProvider.family<ArtistDetails, String>((
  ref,
  artistName,
) {
  return ref.watch(apiProvider).fetchArtistDetails(artistName);
});
