import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'providers.dart';

final homeControllerProvider = AsyncNotifierProvider<HomeController, HomeData>(
  HomeController.new,
);

const _homeFetchTimeout = Duration(seconds: 8);
const _homeCacheKey = 'jojomusic.home.cache';

class HomeController extends AsyncNotifier<HomeData> {
  @override
  Future<HomeData> build() async {
    final cached = await _restoreCachedHome();
    if (cached != null) {
      unawaited(_refreshInBackground());
      return cached;
    }
    return _fetchAndCacheHome();
  }

  Future<void> refresh() async {
    final fallback = state.asData?.value ?? await _restoreCachedHome();
    if (fallback == null) {
      state = const AsyncLoading();
    }
    try {
      final home = await _fetchAndCacheHome();
      state = AsyncData(home);
    } on DioException catch (error, stackTrace) {
      if (_canUseCachedHome(error) && fallback != null) {
        state = AsyncData(fallback);
        return;
      }
      state = AsyncError(error, stackTrace);
    } on TimeoutException catch (error, stackTrace) {
      if (fallback != null) {
        state = AsyncData(fallback);
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  Future<HomeData> _fetchAndCacheHome() async {
    final home = await ref
        .read(apiProvider)
        .fetchHome()
        .timeout(_homeFetchTimeout);
    await _persistHome(home);
    return home;
  }

  Future<void> _refreshInBackground() async {
    try {
      final home = await _fetchAndCacheHome();
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(home);
    } on DioException catch (_) {
      return;
    } on TimeoutException {
      return;
    }
  }

  Future<void> _persistHome(HomeData home) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _homeCacheKey,
          jsonEncode({
            'recently_played': home.recentlyPlayed
                .map((track) => track.toJson())
                .toList(),
            'liked_tracks': home.likedTracks
                .map((track) => track.toJson())
                .toList(),
            'recommendations': home.recommendations
                .map((track) => track.toJson())
                .toList(),
            'generated_playlists': home.generatedPlaylists
                .map(
                  (playlist) => {
                    'playlist_key': playlist.playlistKey,
                    'title': playlist.title,
                    'subtitle': playlist.subtitle,
                    'artwork_url': playlist.artworkUrl,
                    'tracks': playlist.tracks
                        .map((track) => track.toJson())
                        .toList(),
                  },
                )
                .toList(),
            'browse_categories': home.browseCategories
                .map(
                  (category) => {
                    'category_id': category.categoryId,
                    'title': category.title,
                    'subtitle': category.subtitle,
                    'color_hex': category.colorHex,
                    'search_seed': category.searchSeed,
                    'artwork_url': category.artworkUrl,
                  },
                )
                .toList(),
            'featured_podcasts': home.featuredPodcasts
                .map(
                  (podcast) => {
                    'podcast_key': podcast.podcastKey,
                    'title': podcast.title,
                    'publisher': podcast.publisher,
                    'description': podcast.description,
                    'artwork_url': podcast.artworkUrl,
                    'feed_url': podcast.feedUrl,
                    'external_url': podcast.externalUrl,
                    'episode_count': podcast.episodeCount,
                    'release_date': podcast.releaseDate?.toIso8601String(),
                  },
                )
                .toList(),
          }),
        );
  }

  Future<HomeData?> _restoreCachedHome() async {
    final encoded = ref
        .read(sharedPreferencesProvider)
        .getString(_homeCacheKey);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return HomeData.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  bool _canUseCachedHome(DioException error) {
    return error.response?.statusCode == null;
  }
}
