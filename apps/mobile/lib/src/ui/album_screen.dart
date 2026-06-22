import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ytmusic/ytmusic_models.dart';
import '../models/app_models.dart';
import '../state/album_controller.dart';
import '../state/library_controller.dart';
import '../state/player_controller.dart';
import 'artist_screen.dart';
import 'profile_screen.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/media_artwork.dart';
import 'widgets/shell_chrome.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({
    this.ytAlbum,
    this.album,
    required this.onTrackAction,
    super.key,
  }) : assert(ytAlbum != null || album != null);

  final YtAlbum? ytAlbum;
  final Album? album;
  final Future<void> Function(BuildContext, Track, List<Track>) onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = album?.title ?? ytAlbum?.title ?? 'Album';

    return ShellChrome(
      topColor: const Color(0xFF2A1A0D),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      headerTitle: title,
      showBackButton: true,
      showProfileShortcut: false,
      child: _usesCatalogAlbum
          ? _buildCatalogAlbum(context, ref, album!)
          : _buildYtAlbum(context, ref, _effectiveYtAlbum),
    );
  }

  bool get _usesCatalogAlbum =>
      album != null && album!.provider.toLowerCase() != 'youtube';

  YtAlbum get _effectiveYtAlbum {
    final currentYtAlbum = ytAlbum;
    if (currentYtAlbum != null) return currentYtAlbum;

    final currentAlbum = album!;
    return YtAlbum(
      browseId: currentAlbum.externalId ?? currentAlbum.albumKey,
      title: currentAlbum.title,
      artist: currentAlbum.artist,
      artworkUrl: currentAlbum.artworkUrl,
      year: currentAlbum.releaseDate == null
          ? null
          : '${currentAlbum.releaseDate!.year}',
    );
  }

  Widget _buildCatalogAlbum(BuildContext context, WidgetRef ref, Album album) {
    final details = ref.watch(albumDetailProvider(album));
    return details.when(
      data: (data) => _buildAlbumContent(
        context,
        ref,
        _AlbumViewData.fromAlbumDetails(data, fallback: album),
      ),
      error: (e, _) => Center(child: Text('Erreur album: $e')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildYtAlbum(BuildContext context, WidgetRef ref, YtAlbum ytAlbum) {
    if (ytAlbum.browseId.trim().isEmpty) {
      return _buildMissingAlbum(ytAlbum.title);
    }

    final details = ref.watch(ytAlbumDetailProvider(ytAlbum.browseId));
    return details.when(
      data: (data) {
        if (data == null) return _buildMissingAlbum(ytAlbum.title);
        return _buildAlbumContent(
          context,
          ref,
          _AlbumViewData.fromYtAlbumDetail(data, fallback: ytAlbum),
        );
      },
      error: (e, _) => Center(child: Text('Erreur album: $e')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildMissingAlbum(String title) {
    return Center(child: Text('Album "$title" introuvable.'));
  }

  Widget _buildAlbumContent(
    BuildContext context,
    WidgetRef ref,
    _AlbumViewData data,
  ) {
    final tracks = data.tracks;
    final subtitleParts = [
      if (data.artist.trim().isNotEmpty) data.artist,
      if (data.year != null) data.year!,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 148),
      children: [
        Center(
          child: MediaArtwork(
            url: data.artworkUrl,
            size: 160,
            borderRadius: 16,
            icon: Icons.album_rounded,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          data.title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitleParts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitleParts.join(' · '),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white60),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: tracks.isEmpty
                  ? null
                  : () => ref
                        .read(playerControllerProvider)
                        .playTrack(tracks.first, queue: tracks),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Lire'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: data.artist.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtistScreen(
                          browseId: '',
                          artistName: data.artist,
                          onTrackAction: onTrackAction,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.person_outline_rounded),
              label: const Text('Artiste'),
            ),
            const SizedBox(width: 4),
            Builder(
              builder: (context) {
                final library = ref.watch(libraryControllerProvider);
                final saved =
                    library.asData?.value.isAlbumSaved(
                      data.libraryAlbum.albumKey,
                    ) ??
                    false;
                return IconButton(
                  tooltip: saved
                      ? 'Retirer de la bibliothèque'
                      : 'Ajouter à la bibliothèque',
                  onPressed: () {
                    ref
                        .read(libraryControllerProvider.notifier)
                        .toggleSaveAlbum(data.libraryAlbum);
                  },
                  icon: Icon(
                    saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    color: saved
                        ? Theme.of(context).colorScheme.secondary
                        : null,
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (tracks.isEmpty)
          const JojoStateMessage(
            icon: Icons.music_off_rounded,
            message: 'Aucun titre disponible pour cet album.',
          )
        else
          ...tracks.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: JojoTrackTile(
                track: entry.value,
                onTap: () => ref
                    .read(playerControllerProvider)
                    .playTrack(entry.value, queue: tracks),
                onMore: () => onTrackAction(context, entry.value, tracks),
              ),
            ),
          ),
      ],
    );
  }
}

class _AlbumViewData {
  const _AlbumViewData({
    required this.title,
    required this.artist,
    required this.libraryAlbum,
    required this.tracks,
    this.artworkUrl,
    this.year,
  });

  final String title;
  final String artist;
  final String? artworkUrl;
  final String? year;
  final Album libraryAlbum;
  final List<Track> tracks;

  factory _AlbumViewData.fromAlbumDetails(
    AlbumDetails details, {
    required Album fallback,
  }) {
    final album = details.album;
    final title = album.title.trim().isEmpty ? fallback.title : album.title;
    final artist = album.artist.trim().isEmpty ? fallback.artist : album.artist;
    final artworkUrl = album.artworkUrl ?? fallback.artworkUrl;
    final externalId = album.externalId ?? fallback.externalId;
    final releaseDate = album.releaseDate ?? fallback.releaseDate;
    final albumKey = album.albumKey.trim().isEmpty
        ? fallback.albumKey
        : album.albumKey;

    return _AlbumViewData(
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
      year: releaseDate == null ? null : '${releaseDate.year}',
      tracks: details.tracks,
      libraryAlbum: Album(
        albumKey: albumKey,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        provider: album.provider,
        externalId: externalId,
        summary: album.summary ?? fallback.summary,
        releaseDate: releaseDate,
        trackCount: album.trackCount ?? details.tracks.length,
      ),
    );
  }

  factory _AlbumViewData.fromYtAlbumDetail(
    YtAlbumDetail details, {
    required YtAlbum fallback,
  }) {
    final title =
        (details.title == 'Playlist' || details.title == 'Unknown Album')
        ? fallback.title
        : details.title;
    final artist = (details.artist.isEmpty || details.artist == 'Unknown')
        ? fallback.artist
        : details.artist;
    final tracks = details.tracks.map((t) => t.toTrack()).toList();

    return _AlbumViewData(
      title: title,
      artist: artist,
      artworkUrl: details.artworkUrl ?? fallback.artworkUrl,
      year: details.year ?? fallback.year,
      tracks: tracks,
      libraryAlbum: Album(
        albumKey: fallback.browseId,
        title: title,
        artist: artist,
        artworkUrl: details.artworkUrl ?? fallback.artworkUrl,
        provider: 'youtube',
        externalId: fallback.browseId,
        releaseDate: (details.year ?? fallback.year) == null
            ? null
            : DateTime.tryParse('${details.year ?? fallback.year}-01-01'),
        trackCount: tracks.length,
      ),
    );
  }
}
