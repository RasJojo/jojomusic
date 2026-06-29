import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ytmusic/ytmusic_models.dart';
import '../models/app_models.dart';
import '../state/downloads_controller.dart';
import '../state/home_controller.dart';
import '../state/library_controller.dart';
import '../state/player_controller.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'browse_category_screen.dart';
import 'collection_screen.dart';
import 'playlist_screen.dart';
import 'podcast_screen.dart';
import 'profile_screen.dart';
import 'theme/jojo_theme.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/media_artwork.dart';
import 'widgets/shell_chrome.dart';
import 'widgets/track_playlist_picker_sheet.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  final _searchController = TextEditingController();
  AsyncValue<SearchResult>? _searchState;
  AsyncValue<YtSearchResult>? _ytSearchState;
  Timer? _searchDebounce;
  bool _isSearching = false;
  String _searchingQuery = '';
  int _searchRequestId = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(shellTabIndexProvider).clamp(0, 2);
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final firstName =
        session?.user.name
            .split(' ')
            .firstWhere((v) => v.trim().isNotEmpty, orElse: () => 'toi') ??
        'toi';
    final headerTitles = ['Bonjour $firstName', 'Recherche', 'Bibliothèque'];
    final pages = [
      _HomeTab(
        active: selectedIndex == 0,
        onTrackAction: _showTrackActions,
        onGeneratedPlaylistSelected: _openGeneratedPlaylist,
        onBrowseCategorySelected: _openBrowseCategory,
        onPodcastSelected: _openPodcast,
        onYtArtistSelected: _openYtArtist,
        onYtAlbumSelected: _openYtAlbum,
      ),
      _SearchTab(
        active: selectedIndex == 1,
        searchController: _searchController,
        searchState: _searchState,
        ytSearchState: _ytSearchState,
        searchingQuery: _searchingQuery,
        isSearching: _isSearching,
        onClearSearch: _clearSearch,
        onSearch: _runSearch,
        onQueryChanged: _scheduleSearch,
        onAlbumSelected: _openAlbum,
        onArtistSelected: _openArtist,
        onYtArtistSelected: _openYtArtist,
        onPlaylistSelected: _openPlaylist,
        onPodcastSelected: _openPodcast,
        onTrackAction: _showTrackActions,
      ),
      _LibraryTab(active: selectedIndex == 2, onTrackAction: _showTrackActions),
    ];

    return ShellChrome(
      onProfilePressed: _openProfile,
      headerTitle: headerTitles[selectedIndex],
      child: IndexedStack(index: selectedIndex, children: pages),
    );
  }

  void _openProfile() {
    openProfileScreen(context);
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchState = null;
        _ytSearchState = null;
        _isSearching = false;
        _searchingQuery = '';
      });
      return;
    }
    final requestId = ++_searchRequestId;
    setState(() {
      _isSearching = true;
      _searchingQuery = query;
      _searchState ??= const AsyncLoading();
    });

    AsyncValue<SearchResult>? backendResult;
    AsyncValue<YtSearchResult>? ytResult;
    await Future.wait([
      AsyncValue.guard(() => ref.read(apiProvider).search(query))
          .then((v) => backendResult = v),
      AsyncValue.guard(() => ref.read(ytMusicClientProvider).search(query))
          .then((v) => ytResult = v),
    ]);

    if (!mounted || requestId != _searchRequestId) {
      return;
    }
    if (_searchController.text.trim() != query) {
      return;
    }
    setState(() {
      _searchState = backendResult;
      _ytSearchState = ytResult;
      _isSearching = false;
      _searchingQuery = query;
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchRequestId++;
    _searchController.clear();
    if (mounted) {
      setState(() {
        _searchState = null;
        _ytSearchState = null;
        _isSearching = false;
        _searchingQuery = '';
      });
    }
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _searchState = null;
        _isSearching = false;
        _searchingQuery = '';
      });
      return;
    }
    if (mounted) {
      setState(() {
        _isSearching = true;
        _searchingQuery = value.trim();
      });
    }
    _searchDebounce = Timer(const Duration(milliseconds: 180), _runSearch);
  }

  void _openYtArtist(YtArtist artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistScreen(
          browseId: artist.browseId,
          artistName: artist.name,
          imageUrl: artist.imageUrl,
          onTrackAction: _showTrackActions,
        ),
      ),
    );
  }

  void _openYtAlbum(YtAlbum album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AlbumScreen(ytAlbum: album, onTrackAction: _showTrackActions),
      ),
    );
  }

  void _openArtist(Artist artist) {
    _openYtArtist(
      YtArtist(
        browseId: artist.externalId ?? '',
        name: artist.name,
        imageUrl: artist.imageUrl,
      ),
    );
  }

  void _openAlbum(Album album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AlbumScreen(album: album, onTrackAction: _showTrackActions),
      ),
    );
  }

  void _openPlaylist(Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistScreen(playlistId: playlist.id),
      ),
    );
  }

  void _openGeneratedPlaylist(GeneratedPlaylist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollectionScreen(
          title: playlist.title,
          subtitle: playlist.subtitle,
          artworkUrl: playlist.displayArtworkUrl,
          tracks: playlist.tracks,
          onTrackAction: _showTrackActions,
        ),
      ),
    );
  }

  void _openBrowseCategory(BrowseCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowseCategoryScreen(
          category: category,
          onAlbumSelected: _openAlbum,
          onArtistSelected: _openArtist,
          onTrackAction: _showTrackActions,
        ),
      ),
    );
  }

  void _openPodcast(Podcast podcast) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PodcastScreen(podcast: podcast)),
    );
  }

  Future<void> _showTrackActions(
    BuildContext context,
    Track track,
    List<Track> queue,
  ) async {
    final library = ref.read(libraryControllerProvider).asData?.value;
    final isLiked = library?.isLiked(track) ?? false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Lire maintenant'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(playerControllerProvider)
                      .playTrack(track, queue: queue);
                },
              ),
              ListTile(
                leading: Icon(
                  isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  color: isLiked ? const Color(0xFFFF6B8E) : null,
                ),
                title: Text(
                  isLiked ? 'Retirer des favoris' : 'Ajouter aux favoris',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(libraryControllerProvider.notifier)
                      .toggleLike(track);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Ajouter à une playlist'),
                subtitle: const Text('Choisis une ou plusieurs playlists.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await showTrackPlaylistPickerSheet(
                    context,
                    ref,
                    track: track,
                    preferDownloaded: true,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeTab extends ConsumerWidget {
  const _HomeTab({
    required this.active,
    required this.onTrackAction,
    required this.onGeneratedPlaylistSelected,
    required this.onBrowseCategorySelected,
    required this.onPodcastSelected,
    required this.onYtArtistSelected,
    required this.onYtAlbumSelected,
  });

  final bool active;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;
  final ValueChanged<GeneratedPlaylist> onGeneratedPlaylistSelected;
  final ValueChanged<BrowseCategory> onBrowseCategorySelected;
  final ValueChanged<Podcast> onPodcastSelected;
  final ValueChanged<YtArtist> onYtArtistSelected;
  final ValueChanged<YtAlbum> onYtAlbumSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active) {
      return const SizedBox.shrink();
    }
    final home = ref.watch(homeControllerProvider);
    final ytFeed = ref.watch(ytHomeFeedProvider);

    return home.when(
      data: (data) {
        final nonEmptyPlaylists = data.generatedPlaylists
            .where((p) => p.tracks.isNotEmpty)
            .toList();
        final featured = nonEmptyPlaylists.isNotEmpty
            ? nonEmptyPlaylists.first
            : null;
        final spotlightCollections = <GeneratedPlaylist>[
          if (data.recommendations.isNotEmpty)
            GeneratedPlaylist(
              playlistKey: 'recommendations-collection',
              title: 'À découvrir',
              artworkUrl: data.recommendations.first.displayArtworkUrl,
              tracks: data.recommendations,
            ),
          if (data.recentlyPlayed.isNotEmpty)
            GeneratedPlaylist(
              playlistKey: 'recently-played-collection',
              title: 'Récemment écouté',
              artworkUrl: data.recentlyPlayed.first.displayArtworkUrl,
              tracks: data.recentlyPlayed,
            ),
        ];
        final ytFeedData = ytFeed.asData?.value;

        return RefreshIndicator(
          onRefresh: () async {
            await ref.read(homeControllerProvider.notifier).refresh();
            await ref.read(ytHomeFeedProvider.notifier).refresh();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
            children: [
              if (ytFeedData != null && !ytFeedData.isEmpty) ...[
                for (final section in ytFeedData.sections) ...[
                  _YtHomeSectionWidget(
                    section: section,
                    onTrackTap: (track) => ref
                        .read(playerControllerProvider)
                        .playTrack(track, queue: [track]),
                    onArtistTap: onYtArtistSelected,
                    onAlbumTap: onYtAlbumSelected,
                  ),
                  const SizedBox(height: 16),
                ],
              ],
              if (featured != null) ...[
                _FeaturedRow(
                  featured: featured,
                  onPlay: () => ref
                      .read(playerControllerProvider)
                      .playTrack(featured.tracks.first, queue: featured.tracks)
                      .catchError((_) {}),
                  onOpen: () => onGeneratedPlaylistSelected(featured),
                ),
                const SizedBox(height: 18),
              ],
              if (spotlightCollections.isNotEmpty) ...[
                const JojoSectionHeading(title: 'Pour reprendre'),
                const SizedBox(height: 14),
                SizedBox(
                  height: 228,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: spotlightCollections.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final collection = spotlightCollections[index];
                      return JojoPosterCard(
                        title: collection.title,
                        artworkUrl: collection.displayArtworkUrl,
                        badge: index == 0 ? 'Pour toi' : 'Reprendre',
                        width: 148,
                        height: 136,
                        onTap: () => onGeneratedPlaylistSelected(collection),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (nonEmptyPlaylists.isNotEmpty) ...[
                const JojoSectionHeading(title: 'Faits pour toi'),
                const SizedBox(height: 14),
                SizedBox(
                  height: 228,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: nonEmptyPlaylists.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final playlist = nonEmptyPlaylists[index];
                      return JojoPosterCard(
                        title: playlist.title,
                        artworkUrl: playlist.displayArtworkUrl,
                        badge: 'Pour toi',
                        width: 148,
                        height: 136,
                        onTap: () => onGeneratedPlaylistSelected(playlist),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (data.featuredPodcasts.isNotEmpty) ...[
                const JojoSectionHeading(title: 'Podcasts à suivre'),
                const SizedBox(height: 14),
                SizedBox(
                  height: 228,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: data.featuredPodcasts.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final podcast = data.featuredPodcasts[index];
                      return JojoPosterCard(
                        title: podcast.title,
                        subtitle: podcast.publisher,
                        artworkUrl: podcast.artworkUrl,
                        badge: 'Podcast',
                        width: 148,
                        height: 136,
                        backgroundColor: const Color(0xFF15181F),
                        onTap: () => onPodcastSelected(podcast),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ],
          ),
        );
      },
      error: (error, stackTrace) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: JojoSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                JojoStateMessage(
                  icon: Icons.cloud_off_rounded,
                  message: _describeHomeLoadError(error),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(shellTabIndexProvider.notifier).setIndex(2),
                      icon: const Icon(Icons.library_music_rounded),
                      label: const Text('Ouvrir Bibliothèque'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(homeControllerProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      loading: () {
        final hasNetwork = ref.watch(connectivityStatusProvider).asData?.value;
        if (hasNetwork == false) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: JojoSurfaceCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const JojoStateMessage(
                      icon: Icons.cloud_off_rounded,
                      message:
                          'Pas de connexion. Accueil se remettra à jour dès que le réseau revient.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(shellTabIndexProvider.notifier).setIndex(2),
                      icon: const Icon(Icons.library_music_rounded),
                      label: const Text('Voir Bibliothèque'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

class _SearchTab extends ConsumerWidget {
  const _SearchTab({
    required this.active,
    required this.searchController,
    required this.searchState,
    required this.ytSearchState,
    required this.searchingQuery,
    required this.isSearching,
    required this.onClearSearch,
    required this.onSearch,
    required this.onQueryChanged,
    required this.onAlbumSelected,
    required this.onArtistSelected,
    required this.onYtArtistSelected,
    required this.onPlaylistSelected,
    required this.onPodcastSelected,
    required this.onTrackAction,
  });

  final bool active;
  final TextEditingController searchController;
  final AsyncValue<SearchResult>? searchState;
  final AsyncValue<YtSearchResult>? ytSearchState;
  final String searchingQuery;
  final bool isSearching;
  final VoidCallback onClearSearch;
  final Future<void> Function() onSearch;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Album> onAlbumSelected;
  final ValueChanged<Artist> onArtistSelected;
  final ValueChanged<YtArtist> onYtArtistSelected;
  final ValueChanged<Playlist> onPlaylistSelected;
  final ValueChanged<Podcast> onPodcastSelected;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active) {
      return const SizedBox.shrink();
    }
    final trimmedQuery = searchController.text.trim();
    final library = ref.watch(libraryControllerProvider).asData?.value;
    final home = ref.watch(homeControllerProvider).asData?.value;
    final matchingPlaylists = _filterPlaylists(
      library?.playlists ?? const <Playlist>[],
      trimmedQuery,
    );
    final searchingLabel = searchingQuery.isNotEmpty
        ? searchingQuery
        : trimmedQuery;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
      children: [
        JojoSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SearchBar(
                controller: searchController,
                hintText: 'Artiste, morceau, album, podcast',
                leading: const Icon(Icons.search_rounded),
                onChanged: onQueryChanged,
                onSubmitted: (_) => onSearch(),
                trailing: [
                  if (trimmedQuery.isNotEmpty)
                    IconButton(
                      onPressed: onClearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  IconButton(
                    onPressed: onSearch,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isSearching && searchingLabel.isNotEmpty) ...[
                const SizedBox(height: 12),
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  child: LinearProgressIndicator(minHeight: 4),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (searchState == null)
          _SearchDiscoveryState(
            podcasts: home?.featuredPodcasts ?? const <Podcast>[],
            onPodcastSelected: onPodcastSelected,
          )
        else
          searchState!.when(
            data: (data) => _SearchResultsContent(
              result: data,
              ytResult: ytSearchState?.asData?.value,
              playlists: matchingPlaylists,
              onAlbumSelected: onAlbumSelected,
              onArtistSelected: onArtistSelected,
              onYtArtistSelected: onYtArtistSelected,
              onPlaylistSelected: onPlaylistSelected,
              onPodcastSelected: onPodcastSelected,
              onTrackAction: onTrackAction,
            ),
            error: (error, stackTrace) => JojoStateMessage(
              icon: Icons.error_outline_rounded,
              message: 'Erreur recherche: $error',
            ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }

  List<Playlist> _filterPlaylists(List<Playlist> playlists, String query) {
    final normalizedQuery = _normalizeSearchValue(query);
    if (normalizedQuery.isEmpty) {
      return const <Playlist>[];
    }
    return playlists.where((playlist) {
      final haystacks = [
        playlist.name,
        playlist.description,
        ...playlist.tracks.map(
          (item) => '${item.track.artist} ${item.track.title}',
        ),
      ];
      return haystacks.any(
        (value) => _normalizeSearchValue(value).contains(normalizedQuery),
      );
    }).toList();
  }
}

class _SearchResultsContent extends StatelessWidget {
  const _SearchResultsContent({
    required this.result,
    required this.playlists,
    required this.onAlbumSelected,
    required this.onArtistSelected,
    required this.onYtArtistSelected,
    required this.onPlaylistSelected,
    required this.onPodcastSelected,
    required this.onTrackAction,
    this.ytResult,
  });

  final SearchResult result;
  final YtSearchResult? ytResult;
  final List<Playlist> playlists;
  final ValueChanged<Album> onAlbumSelected;
  final ValueChanged<Artist> onArtistSelected;
  final ValueChanged<YtArtist> onYtArtistSelected;
  final ValueChanged<Playlist> onPlaylistSelected;
  final ValueChanged<Podcast> onPodcastSelected;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;

  @override
  Widget build(BuildContext context) {
    final ytTracks = (ytResult?.tracks ?? []).map((t) => t.toTrack()).toList();
    final ytArtists = ytResult?.artists ?? [];

    final displayTracks = ytTracks.isNotEmpty ? ytTracks : result.tracks;

    final hasResults = displayTracks.isNotEmpty ||
        ytArtists.isNotEmpty ||
        result.artists.isNotEmpty ||
        result.albums.isNotEmpty ||
        result.podcasts.isNotEmpty ||
        playlists.isNotEmpty;

    if (!hasResults) {
      return const JojoStateMessage(
        icon: Icons.search_off_rounded,
        message: 'Aucun résultat pour cette recherche.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (displayTracks.isNotEmpty) ...[
          _TrackSection(
            title: 'Titres',
            subtitle: 'Résultats pour cette recherche.',
            tracks: displayTracks,
            onTrackAction: onTrackAction,
          ),
          const SizedBox(height: 18),
        ],
        if (ytArtists.isNotEmpty) ...[
          _YtArtistResultsSection(
            artists: ytArtists,
            onArtistSelected: onYtArtistSelected,
          ),
          const SizedBox(height: 18),
        ] else if (result.artists.isNotEmpty) ...[
          _ArtistResultsSection(
            artists: result.artists,
            onArtistSelected: onArtistSelected,
          ),
          const SizedBox(height: 18),
        ],
        if (result.albums.isNotEmpty) ...[
          _AlbumResultsSection(
            albums: result.albums,
            onAlbumSelected: onAlbumSelected,
          ),
          const SizedBox(height: 18),
        ],
        if (result.podcasts.isNotEmpty) ...[
          _PodcastResultsSection(
            podcasts: result.podcasts,
            onPodcastSelected: onPodcastSelected,
          ),
          const SizedBox(height: 18),
        ],
        if (playlists.isNotEmpty) ...[
          _PlaylistResultsSection(
            playlists: playlists,
            onPlaylistSelected: onPlaylistSelected,
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _SearchDiscoveryState extends StatelessWidget {
  const _SearchDiscoveryState({
    required this.podcasts,
    required this.onPodcastSelected,
  });

  final List<Podcast> podcasts;
  final ValueChanged<Podcast> onPodcastSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JojoHeroPanel(
          label: 'À découvrir',
          title: 'Lance une recherche ciblée',
          accentColor: Color(0xFF232A42),
          metadata: ['Artistes', 'Titres', 'Albums', 'Playlists'],
        ),
        if (podcasts.isNotEmpty) ...[
          const SizedBox(height: 24),
          const JojoSectionHeading(
            title: 'Podcasts à suivre',
            subtitle:
                'Tu peux aussi partir d\'un show et lire ses derniers épisodes.',
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 282,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: podcasts.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final podcast = podcasts[index];
                return JojoPosterCard(
                  title: podcast.title,
                  subtitle: podcast.publisher,
                  artworkUrl: podcast.artworkUrl,
                  badge: 'Podcast',
                  width: 188,
                  height: 176,
                  backgroundColor: const Color(0xFF15181F),
                  onTap: () => onPodcastSelected(podcast),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _YtArtistResultsSection extends StatelessWidget {
  const _YtArtistResultsSection({
    required this.artists,
    required this.onArtistSelected,
  });

  final List<YtArtist> artists;
  final ValueChanged<YtArtist> onArtistSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JojoSectionHeading(title: 'Artistes'),
        const SizedBox(height: 14),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final artist = artists[index];
              return JojoPosterCard(
                title: artist.name,
                subtitle: artist.subscribers,
                artworkUrl: artist.imageUrl,
                width: 148,
                height: 120,
                circularArtwork: true,
                onTap: () => onArtistSelected(artist),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArtistResultsSection extends StatelessWidget {
  const _ArtistResultsSection({
    required this.artists,
    required this.onArtistSelected,
  });

  final List<Artist> artists;
  final ValueChanged<Artist> onArtistSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JojoSectionHeading(title: 'Artistes'),
        const SizedBox(height: 14),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final artist = artists[index];
              return JojoPosterCard(
                title: artist.name,
                subtitle: artist.listeners != null
                    ? '${_formatCount(artist.listeners!)} auditeurs'
                    : null,
                artworkUrl: artist.imageUrl,
                width: 148,
                height: 120,
                circularArtwork: true,
                onTap: () => onArtistSelected(artist),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AlbumResultsSection extends StatelessWidget {
  const _AlbumResultsSection({
    required this.albums,
    required this.onAlbumSelected,
  });

  final List<Album> albums;
  final ValueChanged<Album> onAlbumSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JojoSectionHeading(title: 'Albums'),
        const SizedBox(height: 14),
        SizedBox(
          height: 256,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final album = albums[index];
              return JojoPosterCard(
                title: album.title,
                subtitle: [
                  album.artist,
                  if (album.releaseDate != null) '${album.releaseDate!.year}',
                ].join(' · '),
                artworkUrl: album.artworkUrl,
                width: 160,
                height: 148,
                onTap: () => onAlbumSelected(album),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PodcastResultsSection extends StatelessWidget {
  const _PodcastResultsSection({
    required this.podcasts,
    required this.onPodcastSelected,
  });

  final List<Podcast> podcasts;
  final ValueChanged<Podcast> onPodcastSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JojoSectionHeading(title: 'Podcasts'),
        const SizedBox(height: 12),
        ...podcasts.map(
          (podcast) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PodcastRowCard(
              podcast: podcast,
              onTap: () => onPodcastSelected(podcast),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaylistResultsSection extends StatelessWidget {
  const _PlaylistResultsSection({
    required this.playlists,
    required this.onPlaylistSelected,
  });

  final List<Playlist> playlists;
  final ValueChanged<Playlist> onPlaylistSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JojoSectionHeading(title: 'Playlists'),
        const SizedBox(height: 12),
        ...playlists.map(
          (playlist) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PlaylistRowCard(
              playlist: playlist,
              onTap: () => onPlaylistSelected(playlist),
            ),
          ),
        ),
      ],
    );
  }
}

class _LibraryTab extends ConsumerWidget {
  const _LibraryTab({required this.active, required this.onTrackAction});

  final bool active;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active) {
      return const SizedBox.shrink();
    }
    final library = ref.watch(libraryControllerProvider);
    final downloadedPlaylistIds =
        ref.watch(downloadedPlaylistIdsProvider).asData?.value ??
        const <String>{};

    return library.when(
      data: (data) {
        final favoritesPlaylist = data.favoritesPlaylist;
        final playlistRows = <Playlist?>[
          favoritesPlaylist,
          ...data.playlists,
        ].whereType<Playlist>().toList(growable: false);
        final followedPodcasts = data.followedPodcasts;
        final savedAlbums = data.savedAlbums;

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
              children: [
                // Stats compactes
                Row(
                  children: [
                    _LibraryStat(
                      icon: Icons.favorite_rounded,
                      label: '${data.likes.length}',
                      sub: 'favoris',
                      onTap: favoritesPlaylist == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PlaylistScreen(
                                  playlistId: favoritesPlaylistId,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    _LibraryStat(
                      icon: Icons.queue_music_rounded,
                      label: '${playlistRows.length}',
                      sub: 'playlists',
                    ),
                    if (savedAlbums.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      _LibraryStat(
                        icon: Icons.album_rounded,
                        label: '${savedAlbums.length}',
                        sub: 'albums',
                      ),
                    ],
                    if (followedPodcasts.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      _LibraryStat(
                        icon: Icons.podcasts_rounded,
                        label: '${followedPodcasts.length}',
                        sub: 'podcasts',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 28),
                if (savedAlbums.isNotEmpty) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const JojoSectionHeading(title: 'Albums sauvegardés'),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 220,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: savedAlbums.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, index) {
                            final album = savedAlbums[index];
                            return JojoPosterCard(
                              title: album.title,
                              subtitle: album.artist,
                              artworkUrl: album.artworkUrl,
                              width: 140,
                              height: 130,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AlbumScreen(
                                    album: album,
                                    onTrackAction: onTrackAction,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                if (followedPodcasts.isNotEmpty) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const JojoSectionHeading(title: 'Podcasts suivis'),
                      const SizedBox(height: 14),
                      ...followedPodcasts.map(
                        (podcast) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PodcastRowCard(
                            podcast: podcast,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      PodcastScreen(podcast: podcast),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const JojoSectionHeading(title: 'Playlists'),
                    const SizedBox(height: 14),
                    if (playlistRows.isEmpty)
                      const JojoStateMessage(
                        icon: Icons.playlist_add_check_rounded,
                        message:
                            'Crée ta première playlist pour organiser tes titres.',
                      )
                    else
                      ...playlistRows.map(
                        (playlist) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PlaylistRowCard(
                            playlist: playlist,
                            isOfflineEnabled: downloadedPlaylistIds.contains(
                              playlist.id,
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      PlaylistScreen(playlistId: playlist.id),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _showCreatePlaylistDialog(context, ref),
                backgroundColor: JojoColors.primary,
                foregroundColor: Colors.black,
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Playlist',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        );
      },
      error: (error, stackTrace) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: JojoSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                JojoStateMessage(
                  icon: Icons.library_music_rounded,
                  message: _describeLibraryLoadError(error),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(libraryControllerProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
      loading: () {
        final hasNetwork = ref.watch(connectivityStatusProvider).asData?.value;
        if (hasNetwork == false) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: JojoSurfaceCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const JojoStateMessage(
                      icon: Icons.cloud_off_rounded,
                      message:
                          "Pas de connexion. Les playlists hors ligne apparaîtront ici dès qu'une bibliothèque locale existe.",
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(libraryControllerProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Future<void> _showCreatePlaylistDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nouvelle playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nom',
              hintText: 'Par exemple: Nuit, Mada, Rap 2026',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  return;
                }
                try {
                  await ref
                      .read(libraryControllerProvider.notifier)
                      .createPlaylist(name: name);
                } finally {
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
              child: const Text('Créer'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }
}

String _describeHomeLoadError(Object error) {
  if (error is TimeoutException) {
    return "Accueil trop lent à répondre. Le serveur a fini par répondre, mais l'app a abandonné trop tôt. Réessaie.";
  }
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return 'Accueil indisponible pour le moment (code $statusCode). Tes playlists locales restent accessibles.';
    }
    return "Connexion à l'accueil impossible pour le moment. Tes playlists locales restent accessibles.";
  }
  return 'Accueil indisponible pour le moment. Tes playlists locales restent accessibles.';
}

String _describeLibraryLoadError(Object error) {
  if (error is TimeoutException) {
    return 'Bibliothèque trop lente à charger. Réessaie.';
  }
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return 'Bibliothèque indisponible pour le moment (code $statusCode).';
    }
    return 'Connexion à la bibliothèque impossible pour le moment.';
  }
  return 'Bibliothèque indisponible pour le moment. Réessaie.';
}

class _TrackSection extends ConsumerStatefulWidget {
  const _TrackSection({
    required this.title,
    required this.subtitle,
    required this.tracks,
    required this.onTrackAction,
  });

  final String title;
  final String subtitle;
  final List<Track> tracks;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;

  @override
  ConsumerState<_TrackSection> createState() => _TrackSectionState();
}

class _TrackSectionState extends ConsumerState<_TrackSection> {
  String? _prewarmedSignature;

  @override
  void initState() {
    super.initState();
    _schedulePrewarm();
  }

  @override
  void didUpdateWidget(covariant _TrackSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePrewarm();
  }

  void _schedulePrewarm() {
    final signature = widget.tracks
        .take(3)
        .map((track) => track.trackKey)
        .join('|');
    if (signature.isEmpty || signature == _prewarmedSignature) {
      return;
    }
    _prewarmedSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      for (final track in widget.tracks.take(3)) {
        unawaited(ref.read(playerControllerProvider).prewarmTrack(track));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JojoSectionHeading(title: widget.title),
        const SizedBox(height: 12),
        if (widget.tracks.isEmpty)
          const JojoStateMessage(
            message:
                'Commence à écouter ou à liker des titres pour nourrir cette section.',
          )
        else
          ...widget.tracks.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TrackTile(
                track: entry.value,
                queue: widget.tracks,
                onTrackAction: widget.onTrackAction,
                index: entry.key,
              ),
            ),
          ),
      ],
    );
  }
}

class _TrackTile extends ConsumerWidget {
  const _TrackTile({
    required this.track,
    required this.queue,
    required this.onTrackAction,
    this.index,
  });

  final Track track;
  final List<Track> queue;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;
  final int? index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return JojoTrackTile(
      track: track,
      index: index,
      onTap: () async {
        try {
          await ref
              .read(playerControllerProvider)
              .playTrack(track, queue: queue);
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lecture impossible : $error'),
                duration: const Duration(seconds: 8),
                action: SnackBarAction(label: 'OK', onPressed: () {}),
              ),
            );
          }
        }
      },
      onMore: () => onTrackAction(context, track, queue),
    );
  }
}

class _PlaylistRowCard extends StatelessWidget {
  const _PlaylistRowCard({
    required this.playlist,
    required this.onTap,
    this.isOfflineEnabled = false,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final bool isOfflineEnabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: const Color(0x660C1718),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          children: [
            MediaArtwork(
              url: playlist.displayArtworkUrl,
              size: 64,
              borderRadius: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    playlist.description.isEmpty
                        ? '${playlist.tracks.length} titres'
                        : '${playlist.description} • ${playlist.tracks.length} titres',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (isOfflineEnabled) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: JojoColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: JojoColors.primary.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Text(
                        'Hors ligne activé',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: JojoColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _PodcastRowCard extends StatelessWidget {
  const _PodcastRowCard({required this.podcast, required this.onTap});

  final Podcast podcast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: const Color(0x6617131B),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          children: [
            MediaArtwork(
              url: podcast.artworkUrl,
              size: 64,
              borderRadius: 18,
              backgroundColor: const Color(0xFF4D1D34),
              icon: Icons.mic_rounded,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    podcast.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    podcast.publisher,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _YtHomeSectionWidget extends ConsumerWidget {
  const _YtHomeSectionWidget({
    required this.section,
    required this.onTrackTap,
    required this.onArtistTap,
    required this.onAlbumTap,
  });

  final YtHomeSection section;
  final ValueChanged<Track> onTrackTap;
  final ValueChanged<YtArtist> onArtistTap;
  final ValueChanged<YtAlbum> onAlbumTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (section.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JojoSectionHeading(title: section.title),
        const SizedBox(height: 12),
        SizedBox(
          height: 228,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: section.items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = section.items[index];
              final tappable = item.isTrack || item.browseId != null;
              return JojoPosterCard(
                title: item.title,
                subtitle: item.subtitle,
                artworkUrl: item.artworkUrl,
                badge: item.isTrack ? 'Titre' : null,
                width: 148,
                height: 136,
                onTap: tappable
                    ? () {
                        if (item.isTrack) {
                          final track = Track(
                            trackKey: item.videoId!,
                            title: item.title,
                            artist: item.subtitle ?? '',
                            artworkUrl: item.artworkUrl,
                            provider: 'youtube',
                            externalId: item.videoId,
                          );
                          onTrackTap(track);
                        } else {
                          final browseId = item.browseId!;
                          if (browseId.startsWith('UC')) {
                            onArtistTap(
                              YtArtist(
                                browseId: browseId,
                                name: item.title,
                                imageUrl: item.artworkUrl,
                              ),
                            );
                          } else {
                            onAlbumTap(
                              YtAlbum(
                                browseId: browseId,
                                title: item.title,
                                artist: item.subtitle ?? '',
                                artworkUrl: item.artworkUrl,
                              ),
                            );
                          }
                        }
                      }
                    : () {},
              );
            },
          ),
        ),
      ],
    );
  }
}

String _normalizeSearchValue(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

String _formatCount(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(0)}k';
  return '$count';
}

// Compact featured row on home screen
class _FeaturedRow extends StatelessWidget {
  const _FeaturedRow({
    required this.featured,
    required this.onPlay,
    required this.onOpen,
  });

  final GeneratedPlaylist featured;
  final VoidCallback onPlay;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: 0.07),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: featured.displayArtworkUrl != null
                    ? Image.network(
                        featured.displayArtworkUrl!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const _PlaceholderArt(size: 52),
                      )
                    : const _PlaceholderArt(size: 52),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      featured.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${featured.tracks.length} titres',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: JojoColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: featured.tracks.isEmpty ? null : onPlay,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderArt extends StatelessWidget {
  const _PlaceholderArt({this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFF0D0D0D),
      child: const Icon(Icons.music_note_rounded, color: JojoColors.primary),
    );
  }
}

class _LibraryStat extends StatelessWidget {
  const _LibraryStat({
    required this.icon,
    required this.label,
    required this.sub,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0x660C1718),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x1FFFFFFF)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: JojoColors.primary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(sub, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
