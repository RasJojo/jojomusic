import 'dart:async';

import 'package:dio/dio.dart';

import 'ytmusic_models.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kBaseUrl = 'https://music.youtube.com/youtubei/v1';
const _kClientName = 'WEB_REMIX';
const _kClientVersion = '1.20250108.01.00';

// Search type params (base64-encoded protobuf filters)
const _kParamSongs = 'EgWKAQIIAWoKEAoQCRADEAQQBQ%3D%3D';
const _kParamArtists = 'EgWKAQIgAWoKEAoQCRADEAQQBQ%3D%3D';
const _kParamAlbums = 'EgWKAQIYAWoKEAoQCRADEAQQBQ%3D%3D';

// ─── Client ───────────────────────────────────────────────────────────────────

class YtMusicClient {
  YtMusicClient()
      : _dio = Dio(
          BaseOptions(
            baseUrl: _kBaseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
              'X-Goog-Api-Format-Version': '1',
              'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
              'Origin': 'https://music.youtube.com',
              'Referer': 'https://music.youtube.com/',
            },
          ),
        );

  final Dio _dio;

  static Map<String, dynamic> get _ctx => {
    'context': {
      'client': {
        'clientName': _kClientName,
        'clientVersion': _kClientVersion,
        'hl': 'fr',
        'gl': 'FR',
        'userAgent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    },
  };

  // ─── Search ─────────────────────────────────────────────────────────────────

  Future<YtSearchResult> search(String query) async {
    final results = await Future.wait([
      _searchType(query, _kParamSongs),
      _searchType(query, _kParamArtists),
      _searchType(query, _kParamAlbums),
    ]);

    final tracks = <YtTrack>[];
    final artists = <YtArtist>[];
    final albums = <YtAlbum>[];

    for (final item in _extractShelfItems(results[0])) {
      final t = _parseTrack(item);
      if (t != null) tracks.add(t);
    }
    for (final item in _extractShelfItems(results[1])) {
      final a = _parseArtist(item);
      if (a != null) artists.add(a);
    }
    for (final item in _extractShelfItems(results[2])) {
      final a = _parseAlbum(item);
      if (a != null) albums.add(a);
    }

    return YtSearchResult(
      tracks: tracks.take(12).toList(),
      artists: artists.take(5).toList(),
      albums: albums.take(6).toList(),
    );
  }

  Future<Map<String, dynamic>> _searchType(
    String query,
    String params,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/search',
        queryParameters: {'prettyPrint': 'false'},
        data: {
          ..._ctx,
          'query': query,
          'params': params,
        },
      );
      return response.data ?? {};
    } catch (_) {
      return {};
    }
  }

  // ─── Home feed ──────────────────────────────────────────────────────────────

  Future<YtHomeFeed> fetchHome() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/browse',
        queryParameters: {'prettyPrint': 'false'},
        data: {
          ..._ctx,
          'browseId': 'FEmusic_home',
        },
      );
      return _parseHome(response.data ?? {});
    } catch (_) {
      return const YtHomeFeed(sections: []);
    }
  }

  // ─── Artist detail ──────────────────────────────────────────────────────────

  Future<YtArtistDetail?> fetchArtist(String browseId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/browse',
        queryParameters: {'prettyPrint': 'false'},
        data: {
          ..._ctx,
          'browseId': browseId,
        },
      );
      return _parseArtistDetail(response.data ?? {});
    } catch (_) {
      return null;
    }
  }

  // ─── Album detail ───────────────────────────────────────────────────────────

  Future<YtAlbumDetail?> fetchAlbum(String browseId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/browse',
        queryParameters: {'prettyPrint': 'false'},
        data: {
          ..._ctx,
          'browseId': browseId,
        },
      );
      return _parseAlbumDetail(response.data ?? {});
    } catch (_) {
      return null;
    }
  }

  // ─── Playlist detail ────────────────────────────────────────────────────────

  Future<YtPlaylistDetail?> fetchPlaylist(String browseId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/browse',
        queryParameters: {'prettyPrint': 'false'},
        data: {
          ..._ctx,
          'browseId': browseId,
        },
      );
      return _parsePlaylistDetail(response.data ?? {});
    } catch (_) {
      return null;
    }
  }

  // ─── Radio / autoplay ───────────────────────────────────────────────────────

  Future<List<YtTrack>> fetchRadio(String videoId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/next',
        queryParameters: {'prettyPrint': 'false'},
        data: {
          ..._ctx,
          'videoId': videoId,
          'playlistId': 'RDAMVM$videoId',
          'params': 'wAEB',
          'isAudioOnly': true,
        },
      );
      return _parseRadio(response.data ?? {});
    } catch (_) {
      return [];
    }
  }

  // ─── Parsing helpers ─────────────────────────────────────────────────────────

  // Safe nested navigation
  static T? _nav<T>(dynamic root, List<dynamic> path) {
    dynamic cur = root;
    for (final key in path) {
      if (cur == null) return null;
      if (cur is Map<String, dynamic> && key is String) {
        cur = cur[key];
      } else if (cur is List && key is int && key >= 0 && key < cur.length) {
        cur = cur[key];
      } else if (cur is List && key == -1 && cur.isNotEmpty) {
        cur = cur.last;
      } else {
        return null;
      }
    }
    return cur is T ? cur : null;
  }

  static String? _text(dynamic runs) {
    if (runs is! List) return null;
    return runs
        .whereType<Map<String, dynamic>>()
        .map((r) => r['text']?.toString() ?? '')
        .where((t) => t.isNotEmpty)
        .join('');
  }

  static String? _thumbnail(Map<String, dynamic> renderer) {
    // Try musicThumbnailRenderer path
    final thumbs =
        _nav<List>(renderer, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
        _nav<List>(renderer, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
        _nav<List>(renderer, ['thumbnail', 'thumbnails']);
    if (thumbs == null || thumbs.isEmpty) return null;
    final best = thumbs.last as Map<String, dynamic>?;
    return best?['url']?.toString();
  }

  static int? _parseDurationText(String? text) {
    if (text == null) return null;
    final parts = text.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return (m * 60 + s) * 1000;
    }
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return (h * 3600 + m * 60 + s) * 1000;
    }
    return null;
  }

  // ─── Search shelf extraction ─────────────────────────────────────────────────

  List<Map<String, dynamic>> _extractShelfItems(Map<String, dynamic> data) {
    final tabs =
        _nav<List>(data, ['contents', 'tabbedSearchResultsRenderer', 'tabs']);
    if (tabs == null || tabs.isEmpty) return [];

    final tab = tabs[0] as Map<String, dynamic>?;
    final sections = _nav<List>(tab, [
      'tabRenderer',
      'content',
      'sectionListRenderer',
      'contents',
    ]);
    if (sections == null) return [];

    for (final section in sections) {
      final shelf = (section as Map<String, dynamic>?)?['musicShelfRenderer']
          as Map<String, dynamic>?;
      if (shelf == null) continue;
      final contents = shelf['contents'] as List?;
      if (contents == null) continue;
      return contents
          .whereType<Map<String, dynamic>>()
          .map((c) =>
              c['musicResponsiveListItemRenderer'] as Map<String, dynamic>?)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  // ─── Track parser ────────────────────────────────────────────────────────────

  YtTrack? _parseTrack(Map<String, dynamic> r) {
    // Video ID
    final videoId =
        _nav<String>(r, [
          'overlay',
          'musicItemThumbnailOverlayRenderer',
          'content',
          'musicPlayButtonRenderer',
          'playNavigationEndpoint',
          'watchEndpoint',
          'videoId',
        ]) ??
        _nav<String>(r, [
          'flexColumns',
          0,
          'musicResponsiveListItemFlexColumnRenderer',
          'text',
          'runs',
          0,
          'navigationEndpoint',
          'watchEndpoint',
          'videoId',
        ]);
    if (videoId == null) return null;

    // Title
    final title = _nav<String>(r, [
      'flexColumns',
      0,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
      0,
      'text',
    ]);
    if (title == null) return null;

    // Subtitle runs: artist • album • duration
    final subRuns =
        _nav<List>(r, [
          'flexColumns',
          1,
          'musicResponsiveListItemFlexColumnRenderer',
          'text',
          'runs',
        ]) ??
        [];
    final nonBullet = subRuns
        .whereType<Map<String, dynamic>>()
        .map((rn) => rn['text']?.toString() ?? '')
        .where((t) => t.trim().isNotEmpty && t.trim() != '•' && t.trim() != ' • ')
        .toList();

    final artist = nonBullet.isNotEmpty ? nonBullet[0] : 'Unknown';
    final album = nonBullet.length > 2 ? nonBullet[1] : null;
    final durationText = nonBullet.isNotEmpty ? nonBullet.last : null;
    final durationMs = _parseDurationText(
      RegExp(r'^\d+:\d+').hasMatch(durationText ?? '') ? durationText : null,
    );

    return YtTrack(
      videoId: videoId,
      title: title,
      artist: artist,
      album: album,
      artworkUrl: _thumbnail(r),
      durationMs: durationMs,
    );
  }

  // ─── Artist parser ───────────────────────────────────────────────────────────

  YtArtist? _parseArtist(Map<String, dynamic> r) {
    final browseId = _nav<String>(
      r,
      ['navigationEndpoint', 'browseEndpoint', 'browseId'],
    );
    if (browseId == null) return null;

    final name = _nav<String>(r, [
      'flexColumns',
      0,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
      0,
      'text',
    ]);
    if (name == null) return null;

    final subRuns = _nav<List>(r, [
      'flexColumns',
      1,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
    ]);
    final subscribers = subRuns?.whereType<Map<String, dynamic>>()
        .map((rn) => rn['text']?.toString() ?? '')
        .where((t) => t.isNotEmpty && t != '•')
        .join(' ');

    return YtArtist(
      browseId: browseId,
      name: name,
      imageUrl: _thumbnail(r),
      subscribers: subscribers?.isNotEmpty == true ? subscribers : null,
    );
  }

  // ─── Album parser ────────────────────────────────────────────────────────────

  YtAlbum? _parseAlbum(Map<String, dynamic> r) {
    final browseId = _nav<String>(
      r,
      ['navigationEndpoint', 'browseEndpoint', 'browseId'],
    );
    if (browseId == null) return null;

    final title = _nav<String>(r, [
      'flexColumns',
      0,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
      0,
      'text',
    ]);
    if (title == null) return null;

    final subRuns =
        (_nav<List>(r, [
              'flexColumns',
              1,
              'musicResponsiveListItemFlexColumnRenderer',
              'text',
              'runs',
            ]) ??
            [])
            .whereType<Map<String, dynamic>>()
            .map((rn) => rn['text']?.toString() ?? '')
            .where((t) => t.isNotEmpty && t != '•' && t != ' • ')
            .toList();

    return YtAlbum(
      browseId: browseId,
      title: title,
      artist: subRuns.length > 1 ? subRuns[1] : (subRuns.isNotEmpty ? subRuns[0] : 'Unknown'),
      artworkUrl: _thumbnail(r),
      year: subRuns.isNotEmpty ? subRuns.last : null,
    );
  }

  // ─── Home feed parser ────────────────────────────────────────────────────────

  YtHomeFeed _parseHome(Map<String, dynamic> data) {
    final sections = <YtHomeSection>[];

    final contents =
        _nav<List>(data, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents']) ??
        _nav<List>(data, ['header', 'musicImmersiveHeaderRenderer']) ?? // fallback
        [];

    for (final raw in contents) {
      final section = raw as Map<String, dynamic>?;
      if (section == null) continue;

      // musicCarouselShelfRenderer
      final carousel =
          section['musicCarouselShelfRenderer'] as Map<String, dynamic>? ??
          section['musicImmersiveCarouselShelfRenderer'] as Map<String, dynamic>?;
      if (carousel != null) {
        final parsed = _parseCarouselSection(carousel);
        if (parsed != null) sections.add(parsed);
        continue;
      }

      // musicShelfRenderer (list of songs)
      final shelf = section['musicShelfRenderer'] as Map<String, dynamic>?;
      if (shelf != null) {
        final parsed = _parseShelfSection(shelf);
        if (parsed != null) sections.add(parsed);
      }
    }

    return YtHomeFeed(sections: sections);
  }

  YtHomeSection? _parseCarouselSection(Map<String, dynamic> carousel) {
    final titleRuns = _nav<List>(carousel, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title', 'runs']) ??
        _nav<List>(carousel, ['header', 'musicImmersiveCarouselShelfHeaderRenderer', 'title', 'runs']);
    final title = _text(titleRuns) ?? 'Recommandé';

    final rawContents = carousel['contents'] as List? ?? [];
    final items = <YtHomeItem>[];

    for (final raw in rawContents) {
      final map = raw as Map<String, dynamic>?;
      if (map == null) continue;

      // musicTwoRowItemRenderer (most common on home)
      final two = map['musicTwoRowItemRenderer'] as Map<String, dynamic>?;
      if (two != null) {
        final item = _parseTwoRowItem(two);
        if (item != null) items.add(item);
        continue;
      }

      // musicResponsiveListItemRenderer
      final list = map['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
      if (list != null) {
        final t = _parseTrack(list);
        if (t != null) {
          items.add(YtHomeItem(
            title: t.title,
            subtitle: t.artist,
            artworkUrl: t.artworkUrl,
            videoId: t.videoId,
          ));
        }
      }
    }

    if (items.isEmpty) return null;
    return YtHomeSection(title: title, items: items);
  }

  YtHomeSection? _parseShelfSection(Map<String, dynamic> shelf) {
    final titleRuns = _nav<List>(shelf, ['title', 'runs']);
    final title = _text(titleRuns) ?? 'Titres';

    final rawContents = shelf['contents'] as List? ?? [];
    final items = <YtHomeItem>[];

    for (final raw in rawContents) {
      final map = raw as Map<String, dynamic>?;
      if (map == null) continue;
      final list = map['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
      if (list == null) continue;
      final t = _parseTrack(list);
      if (t != null) {
        items.add(YtHomeItem(
          title: t.title,
          subtitle: t.artist,
          artworkUrl: t.artworkUrl,
          videoId: t.videoId,
        ));
      }
    }

    if (items.isEmpty) return null;
    return YtHomeSection(title: title, items: items);
  }

  YtHomeItem? _parseTwoRowItem(Map<String, dynamic> r) {
    final titleRuns = _nav<List>(r, ['title', 'runs']);
    final title = _text(titleRuns);
    if (title == null) return null;

    final subtitleRuns = _nav<List>(r, ['subtitle', 'runs']);
    final subtitle = subtitleRuns
        ?.whereType<Map<String, dynamic>>()
        .map((rn) => rn['text']?.toString() ?? '')
        .where((t) => t.isNotEmpty && t != '•' && t != ' • ')
        .join(' ')
        .trim();

    // Thumbnail
    final thumbs = _nav<List>(r, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
        _nav<List>(r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
    final artworkUrl = thumbs != null && thumbs.isNotEmpty
        ? _thumbUrl(thumbs.last)
        : null;

    // Navigation endpoint
    final nav = r['navigationEndpoint'] as Map<String, dynamic>?;
    final videoId = _nav<String>(nav, ['watchEndpoint', 'videoId']) ??
        _nav<String>(nav, ['watchPlaylistEndpoint', 'videoId']);
    final browseId = _nav<String>(nav, ['browseEndpoint', 'browseId']);
    final playlistId = _nav<String>(nav, ['watchEndpoint', 'playlistId']) ??
        _nav<String>(nav, ['watchPlaylistEndpoint', 'playlistId']);

    return YtHomeItem(
      title: title,
      subtitle: subtitle?.isNotEmpty == true ? subtitle : null,
      artworkUrl: artworkUrl,
      videoId: videoId,
      browseId: browseId,
      playlistId: playlistId,
    );
  }

  // ─── Artist detail parser ────────────────────────────────────────────────────

  YtArtistDetail? _parseArtistDetail(Map<String, dynamic> data) {
    final header =
        _nav<Map>(data, ['header', 'musicImmersiveHeaderRenderer']) as Map<String, dynamic>? ??
        _nav<Map>(data, ['header', 'musicVisualHeaderRenderer']) as Map<String, dynamic>?;
    if (header == null) return null;

    final nameRuns = _nav<List>(header, ['title', 'runs']);
    final name = _text(nameRuns) ?? 'Unknown Artist';

    final descRuns = _nav<List>(header, ['description', 'runs']) ?? [];
    final description = _text(descRuns);

    final subRuns = _nav<List>(header, ['subscriptionButton', 'subscribeButtonRenderer', 'longSubscriberCountText', 'runs']);
    final subscribers = _text(subRuns);

    // Artist image
    final thumbs = _nav<List>(header, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
        _nav<List>(header, ['foregroundThumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
    final imageUrl = thumbs != null && thumbs.isNotEmpty
        ? _thumbUrl(thumbs.last)
        : null;

    // Songs and albums from sections
    final songs = <YtTrack>[];
    final albums = <YtAlbum>[];

    final contents = _nav<List>(data, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents']) ?? [];
    for (final raw in contents) {
      final section = raw as Map<String, dynamic>?;
      if (section == null) continue;

      final carousel = section['musicShelfRenderer'] as Map<String, dynamic>? ??
          section['musicCarouselShelfRenderer'] as Map<String, dynamic>?;
      if (carousel == null) continue;

      final titleText = _text(
        _nav<List>(carousel, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title', 'runs']) ??
        _nav<List>(carousel, ['title', 'runs']),
      )?.toLowerCase() ?? '';

      final carouselContents = carousel['contents'] as List? ?? [];
      if (titleText.contains('chanson') || titleText.contains('song') || titleText.contains('titre')) {
        for (final item in carouselContents) {
          final r = (item as Map<String, dynamic>?)?['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
          if (r == null) continue;
          final t = _parseTrack(r);
          if (t != null) songs.add(t);
        }
      } else if (titleText.contains('album') || titleText.contains('single')) {
        for (final item in carouselContents) {
          final r = (item as Map<String, dynamic>?)?['musicTwoRowItemRenderer'] as Map<String, dynamic>?;
          if (r == null) continue;
          final titleRuns = _nav<List>(r, ['title', 'runs']);
          final t = _text(titleRuns);
          final browseId = _nav<String>(r, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
          if (t != null && browseId != null) {
            albums.add(YtAlbum(
              browseId: browseId,
              title: t,
              artist: name,
              artworkUrl: _thumbnail(r),
            ));
          }
        }
      }
    }

    return YtArtistDetail(
      name: name,
      imageUrl: imageUrl,
      description: description,
      subscribers: subscribers,
      songs: songs,
      albums: albums,
    );
  }

  // ─── Album detail parser ─────────────────────────────────────────────────────

  YtAlbumDetail? _parseAlbumDetail(Map<String, dynamic> data) {
    final header = _nav<Map>(data, ['header', 'musicDetailHeaderRenderer']) as Map<String, dynamic>? ??
        _nav<Map>(data, ['header', 'musicImmersiveHeaderRenderer']) as Map<String, dynamic>? ??
        _nav<Map>(data, ['header', 'musicResponsiveHeaderRenderer']) as Map<String, dynamic>?;
    if (header == null) return null;

    final titleRuns = _nav<List>(header, ['title', 'runs']);
    final title = _text(titleRuns) ?? 'Unknown Album';

    // musicResponsiveHeaderRenderer puts artist in straplineTextOne, year in subtitle
    final straplineRuns = _nav<List>(header, ['straplineTextOne', 'runs']);
    final straplineArtist = straplineRuns != null ? _text(straplineRuns) : null;

    final subtitleRuns = _nav<List>(header, ['subtitle', 'runs']) ?? [];
    final subtitleParts = subtitleRuns
        .whereType<Map<String, dynamic>>()
        .map((r) => r['text']?.toString() ?? '')
        .where((t) => t.isNotEmpty && t != ' • ')
        .toList();
    final artist = straplineArtist ?? (subtitleParts.isNotEmpty ? subtitleParts[0] : 'Unknown');
    // For musicResponsiveHeaderRenderer subtitle is year/type only; for others artist is first run
    String? year;
    if (straplineArtist != null) {
      final y = subtitleParts.firstWhere((t) => RegExp(r'^\d{4}$').hasMatch(t), orElse: () => '');
      year = y.isEmpty ? null : y;
    } else {
      year = subtitleParts.length > 1 ? subtitleParts[1] : null;
    }

    final thumbs = _nav<List>(header, ['thumbnail', 'croppedSquareThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
        _nav<List>(header, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
    final artworkUrl = thumbs != null && thumbs.isNotEmpty
        ? _thumbUrl(thumbs.last)
        : null;

    final tracks = <YtTrack>[];
    final contents = _nav<List>(data, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents']) ?? [];
    for (final raw in contents) {
      final shelf = (raw as Map<String, dynamic>?)?['musicShelfRenderer'] as Map<String, dynamic>?;
      if (shelf == null) continue;
      for (final item in shelf['contents'] as List? ?? []) {
        final r = (item as Map<String, dynamic>?)?['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
        if (r == null) continue;
        final t = _parseTrack(r);
        if (t != null) tracks.add(t.videoId.isNotEmpty ? t : YtTrack(videoId: t.videoId, title: t.title, artist: artist, album: title, artworkUrl: artworkUrl ?? t.artworkUrl, durationMs: t.durationMs));
      }
    }

    return YtAlbumDetail(
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
      year: year,
      tracks: tracks,
    );
  }

  // ─── Playlist detail parser ──────────────────────────────────────────────────

  YtPlaylistDetail? _parsePlaylistDetail(Map<String, dynamic> data) {
    final headerV1 = _nav<Map>(data, ['header', 'musicDetailHeaderRenderer']) as Map<String, dynamic>?;
    final headerV2 = _nav<Map>(data, ['header', 'musicEditablePlaylistDetailHeaderRenderer', 'header', 'musicDetailHeaderRenderer']) as Map<String, dynamic>?
        ?? _nav<Map>(data, ['header', 'musicImmersiveHeaderRenderer']) as Map<String, dynamic>?
        ?? _nav<Map>(data, ['header', 'musicResponsiveHeaderRenderer']) as Map<String, dynamic>?;
    final header = headerV1 ?? headerV2;

    final title = header != null
        ? _text(_nav<List>(header, ['title', 'runs'])) ?? 'Playlist'
        : 'Playlist';

    List<dynamic>? _artworkThumbs(Map<String, dynamic>? h) {
      if (h == null) return null;
      return _nav<List>(h, ['thumbnail', 'croppedSquareThumbnailRenderer', 'thumbnail', 'thumbnails'])
          ?? _nav<List>(h, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])
          ?? _nav<List>(h, ['foregroundThumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
    }
    final thumbs = _artworkThumbs(header)
        ?? _artworkThumbs(_nav<Map>(data, ['header', 'musicEditablePlaylistDetailHeaderRenderer']) as Map<String, dynamic>?);
    final artworkUrl = thumbs != null && thumbs.isNotEmpty ? _thumbUrl(thumbs.last) : null;

    // Try single-column path (mobile InnerTube)
    final singleCol = _nav<List>(data, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents']) ?? [];
    // Try two-column path (newer InnerTube playlists)
    final twoColPrimary = _nav<List>(data, ['contents', 'twoColumnBrowseResultsRenderer', 'secondaryContents', 'sectionListRenderer', 'contents']) ?? [];
    final twoColTab = _nav<List>(data, ['contents', 'twoColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents']) ?? [];
    final contents = singleCol.isNotEmpty ? singleCol : (twoColPrimary.isNotEmpty ? twoColPrimary : twoColTab);

    final tracks = <YtTrack>[];
    for (final raw in contents) {
      final shelf = (raw as Map<String, dynamic>?)?['musicShelfRenderer'] as Map<String, dynamic>?
          ?? (raw as Map<String, dynamic>?)?['musicPlaylistShelfRenderer'] as Map<String, dynamic>?;
      if (shelf == null) continue;
      for (final item in shelf['contents'] as List? ?? []) {
        final r = (item as Map<String, dynamic>?)?['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
        if (r == null) continue;
        final t = _parseTrack(r);
        if (t != null) tracks.add(t);
      }
    }

    return YtPlaylistDetail(title: title, artworkUrl: artworkUrl, tracks: tracks);
  }

  // ─── Radio parser ────────────────────────────────────────────────────────────

  List<YtTrack> _parseRadio(Map<String, dynamic> data) {
    final tracks = <YtTrack>[];
    final playlist = _nav<Map>(data, ['contents', 'singleColumnMusicWatchNextResultsRenderer', 'playlist', 'playlistPanelRenderer']) as Map<String, dynamic>?;
    if (playlist == null) return [];

    for (final item in playlist['contents'] as List? ?? []) {
      final r = (item as Map<String, dynamic>?)?['playlistPanelVideoRenderer'] as Map<String, dynamic>?;
      if (r == null) continue;

      final videoId = r['videoId']?.toString();
      if (videoId == null) continue;

      final titleRuns = _nav<List>(r, ['title', 'runs']);
      final title = _text(titleRuns) ?? 'Unknown';

      final shortByline = _nav<List>(r, ['shortBylineText', 'runs']);
      final artist = _text(shortByline) ?? 'Unknown';

      final thumbs = _nav<List>(r, ['thumbnail', 'thumbnails']);
      final artworkUrl = thumbs != null && thumbs.isNotEmpty
          ? _thumbUrl(thumbs.last)
          : null;

      tracks.add(YtTrack(
        videoId: videoId,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
      ));
    }
    return tracks;
  }

  static String? _thumbUrl(dynamic thumb) {
    if (thumb is Map<String, dynamic>) return thumb['url']?.toString();
    return null;
  }

  void dispose() => _dio.close();
}
