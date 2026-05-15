import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ytmusic/ytmusic_models.dart';
import 'providers.dart';

final ytArtistDetailProvider = FutureProvider.family<YtArtistDetail?, String>((
  ref,
  browseId,
) {
  if (browseId.isEmpty) return Future.value(null);
  return ref.watch(ytMusicClientProvider).fetchArtist(browseId);
});

final ytArtistByNameProvider = FutureProvider.family<YtArtistDetail?, String>((
  ref,
  name,
) async {
  if (name.isEmpty) return null;
  final client = ref.watch(ytMusicClientProvider);
  final results = await client.search(name);
  final firstArtist =
      results.artists.isNotEmpty ? results.artists.first : null;
  if (firstArtist == null) return null;
  return client.fetchArtist(firstArtist.browseId);
});
