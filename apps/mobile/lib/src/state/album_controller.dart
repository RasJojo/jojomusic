import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'providers.dart';

final albumDetailsProvider = FutureProvider.family<AlbumDetails, Album>((
  ref,
  album,
) {
  return ref.watch(apiProvider).fetchAlbumDetails(album);
});
