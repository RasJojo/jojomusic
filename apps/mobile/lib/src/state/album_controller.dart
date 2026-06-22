import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ytmusic/ytmusic_models.dart';
import '../models/app_models.dart';
import 'providers.dart';

final ytAlbumDetailProvider = FutureProvider.family<YtAlbumDetail?, String>((
  ref,
  browseId,
) async {
  if (browseId.isEmpty) return null;
  final client = ref.watch(ytMusicClientProvider);
  final album = await client.fetchAlbum(browseId);
  if (album != null) return album;
  // Fallback: browseId may be a playlist/mix — try parsing as playlist
  final playlist = await client.fetchPlaylist(browseId);
  if (playlist == null) return null;
  final artworkUrl =
      playlist.artworkUrl ??
      playlist.tracks
          .map((t) => t.artworkUrl)
          .firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);
  return YtAlbumDetail(
    title: playlist.title,
    artist: playlist.subtitle ?? '',
    artworkUrl: artworkUrl,
    tracks: playlist.tracks,
  );
});

final albumDetailProvider = FutureProvider.family<AlbumDetails, Album>((
  ref,
  album,
) async {
  final api = ref.watch(apiProvider);
  return api.fetchAlbumDetails(album);
});
