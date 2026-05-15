import 'package:dio/dio.dart';

import '../models/app_models.dart';

class LrclibService {
  LrclibService()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 6),
          ),
        );

  final Dio _dio;

  static const _endpoint = 'https://lrclib.net/api/get';

  Future<LyricsData?> fetchLyrics({
    required String artist,
    required String title,
    int? durationSeconds,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        _endpoint,
        queryParameters: {
          'artist_name': artist,
          'track_name': title,
          'duration': durationSeconds,
        }..removeWhere((key, val) => val == null),
      );
      if (response.statusCode != 200 || response.data == null) return null;
      final data = response.data as Map<String, dynamic>;
      final synced = data['syncedLyrics'] as String?;
      final plain = data['plainLyrics'] as String?;
      if ((synced == null || synced.isEmpty) && (plain == null || plain.isEmpty)) {
        return null;
      }
      return LyricsData(
        artist: artist,
        title: title,
        syncedLyrics: synced?.isNotEmpty == true ? synced : null,
        plainLyrics: plain?.isNotEmpty == true ? plain : null,
      );
    } catch (_) {
      return null;
    }
  }
}
