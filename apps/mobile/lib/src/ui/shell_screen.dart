import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final pages = [
      _HomeTab(
        active: selectedIndex == 0,
        onTrackAction: _showTrackActions,
        onGeneratedPlaylistSelected: _openGeneratedPlaylist,
        onBrowseCategorySelected: _openBrowseCategory,
        onPodcastSelected: _openPodcast,
      ),
      _SearchTab(
        active: selectedIndex == 1,
        searchController: _searchController,
        searchState: _searchState,
        searchingQuery: _searchingQuery,
        isSearching: _isSearching,
        onClearSearch: _clearSearch,
        onSearch: _runSearch,
        onQueryChanged: _scheduleSearch,
        onAlbumSelected: _openAlbum,
        onArtistSelected: _openArtist,
        onBrowseCategorySelected: _openBrowseCategory,
        onPlaylistSelected: _openPlaylist,
        onPodcastSelected: _openPodcast,
        onTrackAction: _showTrackActions,
      ),
      _LibraryTab(active: selectedIndex == 2, onTrackAction: _showTrackActions),
    ];

    return ShellChrome(
      onProfilePressed: _openProfile,
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
    final result = await AsyncValue.guard(
      () => ref.read(apiProvider).search(query),
    );
    if (!mounted || requestId != _searchRequestId) {
      return;
    }
    if (_searchController.text.trim() != query) {
      return;
    }
    setState(() {
      _searchState = result;
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

  void _openArtist(Artist artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ArtistScreen(artist: artist, onTrackAction: _showTrackActions),
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
                subtitle: const Text(
                  'Choisis une ou plusieurs playlists.',
                ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active) {
      return const SizedBox.shrink();
    }
    final home = ref.watch(homeControllerProvider);
    final session = ref.watch(sessionControllerProvider).asData?.value;

    return home.when(
      data: (data) {
        final firstName =
            session?.user.name
                .split(' ')
                .firstWhere(
                  (value) => value.trim().isNotEmpty,
                  orElse: () => 'toi',
                ) ??
            'toi';
        final featured = data.generatedPlaylists.isNotEmpty
            ? data.generatedPlaylists.first
            : null;
        final spotlightCollections = <GeneratedPlaylist>[
          if (data.recommendations.isNotEmpty)
            GeneratedPlaylist(
              playlistKey: 'recommendations-collection',
              title: 'À découvrir',
              subtitle: 'Une collection rapide de titres proposés pour toi',
              artworkUrl: data.recommendations.first.displayArtworkUrl,
              tracks: data.recommendations,
            ),
          if (data.recentlyPlayed.isNotEmpty)
            GeneratedPlaylist(
              playlistKey: 'recently-played-collection',
              title: 'Récemment écouté',
              subtitle: 'Retrouve vite ce que tu avais lancé récemment',
              artworkUrl: data.recentlyPlayed.first.displayArtworkUrl,
              tracks: data.recentlyPlayed,
            ),
        ];

        return RefreshIndicator(
          onRefresh: ref.read(homeControllerProvider.notifier).refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 160),
            children: [
              JojoPageHeader(
                title: 'Bonjour $firstName',
                subtitle:
                    'Mixes personnalisés, catégories, podcasts et titres à relancer dans un home plus éditorial.',
                trailing: const _HeaderBadge(
                  icon: Icons.wifi_tethering_rounded,
                ),
              ),
              const SizedBox(height: 22),
              if (featured != null) ...[
                JojoHeroPanel(
                  label: 'Sélection du jour',
                  title: featured.title,
                  subtitle: featured.subtitle,
                  artworkUrl: featured.displayArtworkUrl,
                  accentColor: const Color(0xFF13382F),
                  metadata: [
                    '${featured.tracks.length} titres',
                    if (data.recommendations.isNotEmpty)
                      '${data.recommendations.length} recommandations',
                  ],
                  actions: [
                    FilledButton.icon(
                      onPressed: featured.tracks.isEmpty
                          ? null
                          : () => ref
                                .read(playerControllerProvider)
                                .playTrack(
                                  featured.tracks.first,
                                  queue: featured.tracks,
                                ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Lancer'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onGeneratedPlaylistSelected(featured),
                      icon: const Icon(Icons.queue_music_rounded),
                      label: const Text('Voir la sélection'),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
              ],
              if (spotlightCollections.isNotEmpty) ...[
                const JojoSectionHeading(
                  title: 'Pour reprendre',
                  subtitle:
                      'Des collections rapides au lieu de listes de titres.',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 290,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: spotlightCollections.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final collection = spotlightCollections[index];
                      return JojoPosterCard(
                        title: collection.title,
                        subtitle: collection.subtitle,
                        artworkUrl: collection.displayArtworkUrl,
                        badge: index == 0 ? 'Pour toi' : 'Reprendre',
                        width: 210,
                        height: 184,
                        onTap: () => onGeneratedPlaylistSelected(collection),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 26),
              ],
              if (data.generatedPlaylists.isNotEmpty) ...[
                const JojoSectionHeading(
                  title: 'Faits pour toi',
                  subtitle:
                      'Daily Mix, découvertes, radios et sélections automatiques.',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 290,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: data.generatedPlaylists.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final playlist = data.generatedPlaylists[index];
                      return JojoPosterCard(
                        title: playlist.title,
                        subtitle: playlist.subtitle,
                        artworkUrl: playlist.displayArtworkUrl,
                        badge: 'Pour toi',
                        width: 190,
                        height: 176,
                        onTap: () => onGeneratedPlaylistSelected(playlist),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 26),
              ],
              if (data.browseCategories.isNotEmpty) ...[
                const JojoSectionHeading(
                  title: 'Explorer tout',
                  subtitle:
                      'Nouveautés, genres, moods, training, love et podcasts.',
                ),
                const SizedBox(height: 14),
                _BrowseCategoryGrid(
                  categories: data.browseCategories,
                  onCategorySelected: onBrowseCategorySelected,
                ),
                const SizedBox(height: 26),
              ],
              if (data.featuredPodcasts.isNotEmpty) ...[
                const JojoSectionHeading(
                  title: 'Podcasts à suivre',
                  subtitle:
                      'Sélection éditoriale musique, société, humour et longs formats.',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 282,
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
                        width: 188,
                        height: 176,
                        backgroundColor: const Color(0xFF15181F),
                        onTap: () => onPodcastSelected(podcast),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 26),
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
    required this.searchingQuery,
    required this.isSearching,
    required this.onClearSearch,
    required this.onSearch,
    required this.onQueryChanged,
    required this.onAlbumSelected,
    required this.onArtistSelected,
    required this.onBrowseCategorySelected,
    required this.onPlaylistSelected,
    required this.onPodcastSelected,
    required this.onTrackAction,
  });

  final bool active;
  final TextEditingController searchController;
  final AsyncValue<SearchResult>? searchState;
  final String searchingQuery;
  final bool isSearching;
  final VoidCallback onClearSearch;
  final Future<void> Function() onSearch;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Album> onAlbumSelected;
  final ValueChanged<Artist> onArtistSelected;
  final ValueChanged<BrowseCategory> onBrowseCategorySelected;
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
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 160),
      children: [
        const JojoPageHeader(
          title: 'Recherche',
          subtitle:
              'Artistes d’abord, titres phares ensuite, puis albums, playlists et podcasts.',
        ),
        const SizedBox(height: 18),
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
              const SizedBox(height: 14),
              Text(
                trimmedQuery.isEmpty
                    ? 'Tape un nom pour sortir des thèmes et aller sur des résultats ciblés.'
                    : isSearching
                    ? 'Recherche de "$searchingLabel" en cours... les résultats restent visibles.'
                    : 'Résultats filtrés pour "$trimmedQuery".',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
            categories: home?.browseCategories ?? const <BrowseCategory>[],
            podcasts: home?.featuredPodcasts ?? const <Podcast>[],
            onBrowseCategorySelected: onBrowseCategorySelected,
            onPodcastSelected: onPodcastSelected,
          )
        else
          searchState!.when(
            data: (data) => _SearchResultsContent(
              result: data,
              playlists: matchingPlaylists,
              onAlbumSelected: onAlbumSelected,
              onArtistSelected: onArtistSelected,
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
    required this.onPlaylistSelected,
    required this.onPodcastSelected,
    required this.onTrackAction,
  });

  final SearchResult result;
  final List<Playlist> playlists;
  final ValueChanged<Album> onAlbumSelected;
  final ValueChanged<Artist> onArtistSelected;
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
    if (result.artists.isEmpty &&
        result.tracks.isEmpty &&
        result.albums.isEmpty &&
        result.podcasts.isEmpty &&
        playlists.isEmpty) {
      return const JojoStateMessage(
        icon: Icons.search_off_rounded,
        message: 'Aucun résultat exploitable pour cette recherche.',
      );
    }

    final topArtist = result.artists.isNotEmpty ? result.artists.first : null;
    final topPodcast = result.podcasts.isNotEmpty ? result.podcasts.first : null;
    final prioritizePodcasts =
        topPodcast != null &&
        _podcastPriorityScore(result.query, topPodcast) >=
            _artistPriorityScore(result.query, topArtist);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (prioritizePodcasts) ...[
          JojoHeroPanel(
            label: 'Meilleur résultat',
            title: topPodcast.title,
            subtitle: topPodcast.description?.isNotEmpty == true
                ? topPodcast.description!
                : 'Podcast • ouvre la page pour voir les épisodes récents.',
            artworkUrl: topPodcast.artworkUrl,
            accentColor: const Color(0xFF3A1A2D),
            metadata: [
              topPodcast.publisher,
              if ((topPodcast.episodeCount ?? 0) > 0)
                '${topPodcast.episodeCount} épisodes',
            ],
            actions: [
              FilledButton.icon(
                onPressed: () => onPodcastSelected(topPodcast),
                icon: const Icon(Icons.podcasts_rounded),
                label: const Text('Ouvrir le podcast'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ] else if (topArtist != null) ...[
          JojoHeroPanel(
            label: 'Meilleur résultat',
            title: topArtist.name,
            subtitle: topArtist.summary?.isNotEmpty == true
                ? topArtist.summary!
                : 'Artiste • ouvre la page pour voir titres, albums et proches.',
            artworkUrl: topArtist.imageUrl,
            circularArtwork: true,
            accentColor: const Color(0xFF13382F),
            metadata: [
              if (topArtist.listeners != null)
                '${topArtist.listeners} auditeurs',
            ],
            actions: [
              FilledButton.icon(
                onPressed: () => onArtistSelected(topArtist),
                icon: const Icon(Icons.person_search_rounded),
                label: const Text('Ouvrir la page artiste'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (prioritizePodcasts) ...[
          if (result.podcasts.isNotEmpty)
            _PodcastResultsSection(
              podcasts: result.podcasts,
              onPodcastSelected: onPodcastSelected,
            ),
          if (result.podcasts.isNotEmpty && result.artists.isNotEmpty)
            const SizedBox(height: 18),
          if (result.artists.isNotEmpty)
            _ArtistResultsSection(
              artists: result.artists,
              onArtistSelected: onArtistSelected,
            ),
        ] else ...[
          if (result.artists.isNotEmpty)
            _ArtistResultsSection(
              artists: result.artists,
              onArtistSelected: onArtistSelected,
            ),
          if (result.artists.isNotEmpty && result.podcasts.isNotEmpty)
            const SizedBox(height: 18),
          if (result.podcasts.isNotEmpty)
            _PodcastResultsSection(
              podcasts: result.podcasts,
              onPodcastSelected: onPodcastSelected,
            ),
        ],
        if ((result.artists.isNotEmpty || result.podcasts.isNotEmpty) &&
            result.tracks.isNotEmpty)
          const SizedBox(height: 18),
        if (result.tracks.isNotEmpty)
          _TrackSection(
            title: 'Titres phares',
            subtitle:
                'Les morceaux les plus exploitables pour lancer la lecture.',
            tracks: result.tracks,
            onTrackAction: onTrackAction,
          ),
        if (result.tracks.isNotEmpty && result.albums.isNotEmpty)
          const SizedBox(height: 18),
        if (result.albums.isNotEmpty)
          _AlbumResultsSection(
            albums: result.albums,
            onAlbumSelected: onAlbumSelected,
          ),
        if (result.albums.isNotEmpty && playlists.isNotEmpty)
          const SizedBox(height: 18),
        if (playlists.isNotEmpty)
          _PlaylistResultsSection(
            playlists: playlists,
            onPlaylistSelected: onPlaylistSelected,
          ),
      ],
    );
  }

  int _artistPriorityScore(String query, Artist? artist) {
    if (artist == null) {
      return 0;
    }
    return _searchPriorityScore(query, artist.name);
  }

  int _podcastPriorityScore(String query, Podcast podcast) {
    final titleScore = _searchPriorityScore(query, podcast.title);
    final publisherScore = _searchPriorityScore(query, podcast.publisher);
    return titleScore + (publisherScore ~/ 3);
  }

  int _searchPriorityScore(String query, String value) {
    final normalizedQuery = _normalizeSearchValue(query);
    final normalizedValue = _normalizeSearchValue(value);
    final compactQuery = normalizedQuery.replaceAll(' ', '');
    final compactValue = normalizedValue.replaceAll(' ', '');

    if (normalizedValue == normalizedQuery || compactValue == compactQuery) {
      return 4000;
    }
    if (normalizedValue.startsWith(normalizedQuery) ||
        compactValue.startsWith(compactQuery)) {
      return 2800;
    }
    if (normalizedValue.contains(normalizedQuery) ||
        compactValue.contains(compactQuery)) {
      return 2200;
    }
    return 0;
  }
}

class _SearchDiscoveryState extends StatelessWidget {
  const _SearchDiscoveryState({
    required this.categories,
    required this.podcasts,
    required this.onBrowseCategorySelected,
    required this.onPodcastSelected,
  });

  final List<BrowseCategory> categories;
  final List<Podcast> podcasts;
  final ValueChanged<BrowseCategory> onBrowseCategorySelected;
  final ValueChanged<Podcast> onPodcastSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JojoHeroPanel(
          label: 'À découvrir',
          title: 'Lance une recherche ciblée',
          subtitle:
              'La recherche met en avant les artistes exacts avant les titres et réduit le bruit hors sujet.',
          accentColor: Color(0xFF232A42),
          metadata: ['Artistes', 'Titres phares', 'Albums', 'Playlists'],
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 22),
          const JojoSectionHeading(
            title: 'Par thèmes',
            subtitle:
                'Des portes d’entrée rapides quand tu ne sais pas quoi lancer.',
          ),
          const SizedBox(height: 14),
          _BrowseCategoryGrid(
            categories: categories,
            onCategorySelected: onBrowseCategorySelected,
          ),
        ],
        if (podcasts.isNotEmpty) ...[
          const SizedBox(height: 24),
          const JojoSectionHeading(
            title: 'Podcasts à suivre',
            subtitle:
                'Tu peux aussi partir d’un show et lire ses derniers épisodes.',
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

class _ArtistResultsSection extends StatelessWidget {
  const _ArtistResultsSection({
    required this.artists,
    required this.onArtistSelected,
  });

  final List<Artist> artists;
  final ValueChanged<Artist> onArtistSelected;

  @override
  Widget build(BuildContext context) {
    return JojoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JojoSectionHeading(
            title: 'Artistes',
            subtitle: 'Matches prioritaires et variantes proches.',
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 238,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: artists.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final artist = artists[index];
                return JojoPosterCard(
                  title: artist.name,
                  subtitle: artist.listeners == null
                      ? 'Artiste'
                      : '${artist.listeners} auditeurs',
                  artworkUrl: artist.imageUrl,
                  badge: 'Artiste',
                  width: 164,
                  height: 136,
                  circularArtwork: true,
                  onTap: () => onArtistSelected(artist),
                );
              },
            ),
          ),
        ],
      ),
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
    return JojoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JojoSectionHeading(
            title: 'Albums',
            subtitle: 'Sorties, EPs et singles liés à la recherche.',
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 272,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: albums.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final album = albums[index];
                final meta = [
                  album.artist,
                  if (album.releaseDate != null) '${album.releaseDate!.year}',
                ].join(' • ');
                return JojoPosterCard(
                  title: album.title,
                  subtitle: meta,
                  artworkUrl: album.artworkUrl,
                  badge: album.trackCount == null
                      ? 'Album'
                      : '${album.trackCount} titres',
                  width: 176,
                  height: 160,
                  onTap: () => onAlbumSelected(album),
                );
              },
            ),
          ),
        ],
      ),
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
    return JojoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JojoSectionHeading(
            title: 'Playlists',
            subtitle: 'Playlists locales qui matchent la recherche.',
          ),
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
      ),
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
    return JojoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JojoSectionHeading(
            title: 'Podcasts',
            subtitle: 'Shows et flux pertinents autour de la recherche.',
          ),
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
      ),
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

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 160),
          children: [
            JojoPageHeader(
              title: 'Bibliothèque',
              subtitle:
                  'Playlists, favoris et podcasts suivis dans un seul espace.',
              trailing: FilledButton.tonalIcon(
                onPressed: () => _showCreatePlaylistDialog(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Playlist'),
              ),
            ),
            const SizedBox(height: 20),
            JojoHeroPanel(
              label: 'Collection perso',
              title:
                  '${data.likes.length} favoris • ${playlistRows.length} playlists • ${followedPodcasts.length} podcasts',
              subtitle:
                  'Les favoris sont traités comme une playlist, et les podcasts suivis restent ici comme des sélections durables.',
              accentColor: const Color(0xFF243742),
              metadata: [
                '${data.likes.length} titres aimés',
                '${playlistRows.length} playlists',
                '${followedPodcasts.length} podcasts suivis',
              ],
              actions: [
                FilledButton.icon(
                  onPressed: favoritesPlaylist == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PlaylistScreen(
                                playlistId: favoritesPlaylistId,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.favorite_rounded),
                  label: const Text('Ouvrir Favoris'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (followedPodcasts.isNotEmpty) ...[
              JojoSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const JojoSectionHeading(
                      title: 'Podcasts suivis',
                      subtitle:
                          'Chaque podcast suivi vit ici comme une sélection permanente.',
                    ),
                    const SizedBox(height: 14),
                    ...followedPodcasts.map(
                      (podcast) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PodcastRowCard(
                          podcast: podcast,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PodcastScreen(podcast: podcast),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            JojoSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const JojoSectionHeading(
                    title: 'Playlists',
                    subtitle:
                        'Favoris inclus, plus tes playlists perso modifiables.',
                  ),
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
                          'Pas de connexion. Les playlists hors ligne apparaîtront ici dès qu’une bibliothèque locale existe.',
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
                await ref
                    .read(libraryControllerProvider.notifier)
                    .createPlaylist(name: name);
                if (context.mounted) {
                  Navigator.of(context).pop();
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
    return 'Accueil trop lent à répondre. Le serveur a fini par répondre, mais l’app a abandonné trop tôt. Réessaie.';
  }
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return 'Accueil indisponible pour le moment (code $statusCode). Tes playlists locales restent accessibles.';
    }
    return 'Connexion à l’accueil impossible pour le moment. Tes playlists locales restent accessibles.';
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
    return JojoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JojoSectionHeading(title: widget.title, subtitle: widget.subtitle),
          const SizedBox(height: 12),
          if (widget.tracks.isEmpty)
            const JojoStateMessage(
              message:
                  'Commence à écouter ou à liker des titres pour nourrir cette section.',
            )
          else
            ...widget.tracks.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TrackTile(
                  track: entry.value,
                  queue: widget.tracks,
                  onTrackAction: widget.onTrackAction,
                  index: entry.key,
                ),
              ),
            ),
        ],
      ),
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
              SnackBar(content: Text('Lecture impossible: $error')),
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

class _BrowseCategoryGrid extends StatelessWidget {
  const _BrowseCategoryGrid({
    required this.categories,
    required this.onCategorySelected,
  });

  final List<BrowseCategory> categories;
  final ValueChanged<BrowseCategory> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 1180
            ? 4
            : maxWidth >= 840
            ? 3
            : maxWidth >= 520
            ? 2
            : 1;
        const spacing = 14.0;
        final cardWidth = columns == 1
            ? maxWidth
            : (maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: categories
              .map(
                (category) => SizedBox(
                  width: cardWidth,
                  child: _BrowseCategoryCard(
                    category: category,
                    onTap: () => onCategorySelected(category),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _BrowseCategoryCard extends StatelessWidget {
  const _BrowseCategoryCard({required this.category, required this.onTap});

  final BrowseCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(category.colorHex);
    final categoryIcon = _browseCategoryIcon(category.categoryId);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.98),
              color.withValues(alpha: 0.66),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: AspectRatio(
          aspectRatio: 1.14,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (category.artworkUrl != null &&
                  category.artworkUrl!.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: MediaArtwork(
                      url: category.artworkUrl,
                      size: 420,
                      borderRadius: 24,
                      backgroundColor: color.withValues(alpha: 0.82),
                      icon: categoryIcon,
                    ),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.12),
                        Colors.black.withValues(
                          alpha: category.artworkUrl == null ? 0.14 : 0.3,
                        ),
                        Colors.black.withValues(alpha: 0.76),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -24,
                bottom: -24,
                child: Icon(
                  categoryIcon,
                  size: 132,
                  color: Colors.white.withValues(alpha: 0.11),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(categoryIcon, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            _browseCategoryBadge(category.categoryId),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      category.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      category.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _browseCategoryIcon(String categoryId) {
  return switch (categoryId) {
    'new-releases' => Icons.auto_awesome_rounded,
    'pop-hits' => Icons.flash_on_rounded,
    'rap-hiphop' => Icons.graphic_eq_rounded,
    'afro-vibes' => Icons.wb_sunny_rounded,
    'mada-vibes' => Icons.travel_explore_rounded,
    'chill-mood' => Icons.nightlight_round,
    'workout-energy' => Icons.fitness_center_rounded,
    'love-songs' => Icons.favorite_rounded,
    'podcasts-editorial' => Icons.mic_rounded,
    _ => Icons.library_music_rounded,
  };
}

String _browseCategoryBadge(String categoryId) {
  return switch (categoryId) {
    'new-releases' => 'Nouveau',
    'pop-hits' => 'Hits',
    'rap-hiphop' => 'Rap',
    'afro-vibes' => 'Afro',
    'mada-vibes' => 'Mada',
    'chill-mood' => 'Chill',
    'workout-energy' => 'Énergie',
    'love-songs' => 'Love',
    'podcasts-editorial' => 'Podcast',
    _ => 'Explorer',
  };
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0x660C1718),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Icon(icon, color: JojoColors.primary),
    );
  }
}

String _normalizeSearchValue(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

Color _colorFromHex(String value) {
  final buffer = StringBuffer();
  if (value.length == 7) {
    buffer.write('ff');
  }
  buffer.write(value.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
