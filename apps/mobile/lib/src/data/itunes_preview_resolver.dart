import 'package:dio/dio.dart';

import '../models/app_models.dart';

class ItunesPreviewResolver {
  ItunesPreviewResolver()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

  final Dio _dio;
  final Map<String, ResolvedStream?> _cache = {};
  final Map<String, Future<ResolvedStream?>> _inFlight = {};

  Future<ResolvedStream?> resolve(Track track) {
    final key = '${track.artist}\x00${track.title}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _resolve(track);
    _inFlight[key] = future;
    return future
        .then((value) {
          _cache[key] = value;
          return value;
        })
        .whenComplete(() => _inFlight.remove(key));
  }

  Future<ResolvedStream?> _resolve(Track track) async {
    final itunes = await _resolveItunes(track);
    if (itunes != null) return itunes;
    return _resolveDeezer(track);
  }

  Future<ResolvedStream?> _resolveItunes(Track track) async {
    for (final query in _queries(track)) {
      final rows = await _searchItunes(query);
      final match = _bestItunesMatch(track, rows);
      if (match == null) continue;

      final previewUrl = (match['previewUrl'] as String?)?.trim();
      if (previewUrl == null || previewUrl.isEmpty) continue;

      final artwork = (match['artworkUrl100'] as String?)?.replaceFirst(
        '100x100bb',
        '600x600bb',
      );
      return ResolvedStream(
        streamUrl: previewUrl,
        title: track.title,
        artist: track.artist,
        source: 'itunes_preview',
        thumbnailUrl: track.displayArtworkUrl ?? artwork,
        durationMs: null,
      );
    }
    return null;
  }

  Future<ResolvedStream?> _resolveDeezer(Track track) async {
    for (final query in _deezerQueries(track)) {
      final rows = await _searchDeezer(query);
      final match = _bestDeezerMatch(track, rows);
      if (match == null) continue;

      final previewUrl = (match['preview'] as String?)?.trim();
      if (previewUrl == null || previewUrl.isEmpty) continue;

      final album = match['album'] is Map<String, dynamic>
          ? match['album'] as Map<String, dynamic>
          : const <String, dynamic>{};
      return ResolvedStream(
        streamUrl: previewUrl,
        title: track.title,
        artist: track.artist,
        source: 'deezer_preview',
        thumbnailUrl:
            track.displayArtworkUrl ??
            album['cover_xl'] as String? ??
            album['cover_big'] as String? ??
            album['cover_medium'] as String?,
        durationMs: null,
      );
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _searchItunes(String query) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://itunes.apple.com/search',
        queryParameters: {
          'term': query,
          'entity': 'song',
          'limit': '6',
          'media': 'music',
        },
      );
      return ((response.data?['results'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchDeezer(String query) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.deezer.com/search/track',
        queryParameters: {'q': query, 'limit': '8'},
      );
      return ((response.data?['data'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic>? _bestItunesMatch(
    Track track,
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return null;
    final artist = _normalize(_primaryArtist(track.artist));
    final title = _normalize(track.title);

    Map<String, dynamic>? titleOnly;
    for (final row in rows) {
      final rowTitle = _normalize('${row['trackName'] ?? ''}');
      final rowArtist = _normalize(
        _primaryArtist('${row['artistName'] ?? ''}'),
      );
      final titleMatches =
          rowTitle == title ||
          rowTitle.contains(title) ||
          title.contains(rowTitle);
      if (!titleMatches) continue;
      titleOnly ??= row;
      if (rowArtist.isNotEmpty &&
          (rowArtist == artist ||
              rowArtist.contains(artist) ||
              artist.contains(rowArtist))) {
        return row;
      }
    }
    return titleOnly;
  }

  Map<String, dynamic>? _bestDeezerMatch(
    Track track,
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return null;
    final artist = _normalize(_primaryArtist(track.artist));
    final title = _normalize(track.title);

    Map<String, dynamic>? titleOnly;
    for (final row in rows) {
      if ((row['preview'] as String?)?.trim().isEmpty ?? true) continue;
      final rowArtistValue = row['artist'] is Map<String, dynamic>
          ? (row['artist'] as Map<String, dynamic>)['name']
          : '';
      final rowTitle = _normalize('${row['title'] ?? ''}');
      final rowArtist = _normalize(_primaryArtist('$rowArtistValue'));
      final titleMatches =
          rowTitle == title ||
          rowTitle.contains(title) ||
          title.contains(rowTitle);
      if (!titleMatches) continue;
      titleOnly ??= row;
      if (rowArtist.isNotEmpty &&
          (rowArtist == artist ||
              rowArtist.contains(artist) ||
              artist.contains(rowArtist))) {
        return row;
      }
    }
    return titleOnly;
  }

  List<String> _queries(Track track) {
    final primary = _primaryArtist(track.artist);
    return <String>{
      if (primary.isNotEmpty && primary != track.artist)
        '$primary ${track.title}',
      '${track.artist} ${track.title}',
      track.title,
    }.where((query) => query.trim().isNotEmpty).toList();
  }

  List<String> _deezerQueries(Track track) {
    final primary = _primaryArtist(track.artist);
    final foldedTitle = _foldAccents(track.title);
    return <String>{
      if (primary.isNotEmpty) 'artist:"$primary" track:"${track.title}"',
      if (primary.isNotEmpty && foldedTitle != track.title)
        'artist:"$primary" track:"$foldedTitle"',
      'artist:"${track.artist}" track:"${track.title}"',
      if (foldedTitle != track.title)
        'artist:"${track.artist}" track:"$foldedTitle"',
      '${track.artist} ${track.title}',
      if (foldedTitle != track.title) '${track.artist} $foldedTitle',
      track.title,
      if (foldedTitle != track.title) foldedTitle,
    }.where((query) => query.trim().isNotEmpty).toList();
  }

  String _primaryArtist(String artist) => artist
      .split(
        RegExp(
          r'\s*(?:&|,|feat\.?|ft\.?|featuring|avec)\s*',
          caseSensitive: false,
        ),
      )
      .first
      .trim();

  String _normalize(String value) => _foldAccents(value)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  String _foldAccents(String value) {
    const replacements = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'æ': 'ae',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'œ': 'oe',
      'α': 'a',
    };
    final buffer = StringBuffer();
    for (final codePoint in value.runes) {
      final char = String.fromCharCode(codePoint).toLowerCase();
      buffer.write(replacements[char] ?? char);
    }
    return buffer.toString();
  }
}
