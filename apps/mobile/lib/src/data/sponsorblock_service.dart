import 'package:dio/dio.dart';

class SponsorSegment {
  const SponsorSegment({
    required this.start,
    required this.end,
    required this.category,
  });

  final Duration start;
  final Duration end;
  final String category;

  bool contains(Duration position) => position >= start && position < end;
}

class SponsorBlockService {
  SponsorBlockService()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );

  final Dio _dio;

  static const _endpoint = 'https://sponsor.ajay.app/api/skipSegments';

  Future<List<SponsorSegment>> fetchSegments(String videoId) async {
    try {
      final response = await _dio.get<dynamic>(
        _endpoint,
        queryParameters: {
          'videoID': videoId,
          'categories': '["sponsor","selfpromo","interaction","intro","outro"]',
        },
      );
      if (response.statusCode != 200 || response.data == null) return const [];
      final list = response.data as List<dynamic>;
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        final segment = (map['segment'] as List<dynamic>).cast<num>();
        if (segment.length < 2) return null;
        return SponsorSegment(
          start: Duration(milliseconds: (segment[0].toDouble() * 1000).round()),
          end: Duration(milliseconds: (segment[1].toDouble() * 1000).round()),
          category: map['category'] as String? ?? 'sponsor',
        );
      }).whereType<SponsorSegment>().toList();
    } catch (_) {
      return const [];
    }
  }
}
