import 'package:dio/dio.dart';

import '../config/app_environment.dart';
import '../models/app_models.dart';

class ApiService {
  ApiService({required AppEnvironment environment, this.accessToken})
    : _environment = environment,
      _dio = Dio(
        BaseOptions(
          baseUrl: environment.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: accessToken == null
              ? null
              : {'Authorization': 'Bearer $accessToken'},
        ),
      );

  final AppEnvironment _environment;
  final String? accessToken;
  final Dio _dio;
  static final Map<String, _SearchCacheEntry> _searchCache = {};
  static final Map<String, Future<SearchResult>> _searchInFlight = {};
  static const Duration _searchCacheTtl = Duration(minutes: 6);

  ApiService withToken(String? token) =>
      ApiService(environment: _environment, accessToken: token);

  Future<bool> pingHealth() async {
    try {
      final response = await Dio(
        BaseOptions(
          baseUrl: _environment.apiBaseUrl,
          connectTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
        ),
      ).get<Map<String, dynamic>>('/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/register',
      data: {'name': name, 'email': email, 'password': password},
    );
    return AuthSession.fromJson(response.data!);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: {'email': email, 'password': password},
    );
    return AuthSession.fromJson(response.data!);
  }

  Future<UserProfile> fetchCurrentUser() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/auth/me');
    return UserProfile.fromJson(response.data!);
  }

  Future<SpotifyIntegration> fetchSpotifyIntegration() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/me/integrations/spotify',
    );
    return SpotifyIntegration.fromJson(response.data!);
  }

  Future<Uri> createSpotifyConnectUrl() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/me/integrations/spotify/connect',
    );
    return Uri.parse(response.data!['authorize_url'] as String);
  }

  Future<SpotifyIntegration> syncSpotifyIntegration() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/me/integrations/spotify/sync',
    );
    return SpotifyIntegration.fromJson(response.data!);
  }

  Future<void> disconnectSpotifyIntegration() async {
    await _dio.delete('/api/v1/me/integrations/spotify');
  }

  Future<HomeData> fetchHome() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/me/home');
    return HomeData.fromJson(response.data!);
  }

  Future<SearchResult> search(String query, {int limit = 20}) async {
    final normalizedQuery = query.trim().toLowerCase();
    final cacheKey = '$normalizedQuery::$limit::${accessToken ?? 'anon'}';
    final cached = _searchCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.result;
    }

    final inFlight = _searchInFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = (() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/search',
        queryParameters: {'query': query, 'limit': limit},
      );
      final result = SearchResult.fromJson(response.data!);
      _searchCache[cacheKey] = _SearchCacheEntry(
        result: result,
        expiresAt: DateTime.now().add(_searchCacheTtl),
      );
      return result;
    })();
    _searchInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _searchInFlight.remove(cacheKey);
    }
  }

  Future<ArtistDetails> fetchArtistDetails(String name) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/artists/details',
      queryParameters: {'name': name},
    );
    return ArtistDetails.fromJson(response.data!);
  }

  Future<AlbumDetails> fetchAlbumDetails(Album album) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/albums/details',
      queryParameters: {
        'artist': album.artist,
        'title': album.title,
        if (album.externalId != null) 'external_id': album.externalId,
      },
    );
    return AlbumDetails.fromJson(response.data!);
  }

  Future<List<BrowseCategory>> fetchBrowseCategories() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/browse/categories');
    return response.data!
        .map((item) => BrowseCategory.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<BrowseCategoryResult> fetchBrowseCategory(String categoryId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/browse/categories/$categoryId',
    );
    return BrowseCategoryResult.fromJson(response.data!);
  }

  Future<List<Podcast>> searchPodcasts(String query, {int limit = 12}) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/podcasts/search',
      queryParameters: {'query': query, 'limit': limit},
    );
    return response.data!
        .map((item) => Podcast.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<PodcastDetails> fetchPodcastDetails(String podcastKey) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/podcasts/$podcastKey',
    );
    return PodcastDetails.fromJson(response.data!);
  }

  Future<List<Podcast>> fetchFollowedPodcasts() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/me/podcasts');
    return response.data!
        .map((item) => Podcast.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> followPodcast(Podcast podcast) async {
    await _dio.post('/api/v1/me/podcasts', data: {'podcast': podcast.toJson()});
  }

  Future<void> unfollowPodcast(String podcastKey) async {
    await _dio.delete('/api/v1/me/podcasts/$podcastKey');
  }

  Future<ResolvedStream> resolveTrack(Track track) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/tracks/resolve',
      data: {'track': track.toJson()},
    );
    return ResolvedStream.fromJson(response.data!);
  }

  Future<List<Track>> fetchSimilarTracks(
    Track track, {
    int limit = 12,
    List<String> excludeTrackKeys = const [],
  }) async {
    final response = await _dio.post<List<dynamic>>(
      '/api/v1/tracks/similar',
      data: {
        'track': track.toJson(),
        'limit': limit,
        'exclude_track_keys': excludeTrackKeys,
      },
    );
    return response.data!
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Track>> fetchLikes() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/me/likes');
    return response.data!
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> likeTrack(Track track) async {
    await _dio.post('/api/v1/me/likes', data: track.toJson());
  }

  Future<void> unlikeTrack(String trackKey) async {
    await _dio.delete('/api/v1/me/likes/$trackKey');
  }

  Future<void> reportPlayback({
    required String eventType,
    required Track track,
    int listenedMs = 0,
    double completionRatio = 0,
  }) async {
    await _dio.post(
      '/api/v1/me/history',
      data: {
        'event_type': eventType,
        'listened_ms': listenedMs,
        'completion_ratio': completionRatio,
        'track': track.toJson(),
      },
    );
  }

  Future<List<Playlist>> fetchPlaylists() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/playlists');
    return response.data!
        .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Playlist> createPlaylist({
    required String name,
    String description = '',
    String? artworkUrl,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/playlists',
      data: {
        'name': name,
        'description': description,
        'artwork_url': artworkUrl,
      },
    );
    return Playlist.fromJson(response.data!);
  }

  Future<Playlist> updatePlaylist({
    required String playlistId,
    String? name,
    String? description,
    String? artworkUrl,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/playlists/$playlistId',
      data: {
        'name': name,
        'description': description,
        'artwork_url': artworkUrl,
      },
    );
    return Playlist.fromJson(response.data!);
  }

  Future<Playlist> addTrackToPlaylist({
    required String playlistId,
    required Track track,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/playlists/$playlistId/tracks',
      data: {'track': track.toJson()},
    );
    return Playlist.fromJson(response.data!);
  }

  Future<Playlist> removeTrackFromPlaylist({
    required String playlistId,
    required String trackKey,
  }) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/api/v1/playlists/$playlistId/tracks/$trackKey',
    );
    return Playlist.fromJson(response.data!);
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _dio.delete('/api/v1/playlists/$playlistId');
  }

  Future<LyricsData?> fetchLyrics(Track track) async {
    final response = await _dio.get<Map<String, dynamic>?>(
      '/api/v1/lyrics',
      queryParameters: {'artist': track.artist, 'title': track.title},
    );
    final data = response.data;
    if (data == null) {
      return null;
    }
    return LyricsData.fromJson(data);
  }
}

class _SearchCacheEntry {
  const _SearchCacheEntry({required this.result, required this.expiresAt});

  final SearchResult result;
  final DateTime expiresAt;
}
// API
// YT fallback
