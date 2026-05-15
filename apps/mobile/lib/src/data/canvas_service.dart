import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class CanvasService {
  static final _videoIdRe = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  static final Map<String, String?> _cache = {};

  Future<String?> getCanvasUrl(String videoId) async {
    if (!_videoIdRe.hasMatch(videoId)) return null;
    if (_cache.containsKey(videoId)) return _cache[videoId];

    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      // Use lowest-res video-only stream — small download, good enough for BG
      final streams = manifest.videoOnly
          .where((s) => s.videoResolution.height <= 360)
          .toList()
        ..sort(
          (a, b) => a.videoResolution.height.compareTo(b.videoResolution.height),
        );
      final url = streams.isNotEmpty ? streams.first.url.toString() : null;
      _cache[videoId] = url;
      return url;
    } catch (_) {
      _cache[videoId] = null;
      return null;
    } finally {
      yt.close();
    }
  }
}
