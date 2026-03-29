import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/models/app_models.dart';

void main() {
  test('Track serializes and deserializes', () {
    const track = Track(
      trackKey: 'daft-punk-one-more-time',
      title: 'One More Time',
      artist: 'Daft Punk',
      album: 'Discovery',
      artworkUrl: 'https://example.com/cover.jpg',
      durationMs: 320000,
    );

    final json = track.toJson();
    final rebuilt = Track.fromJson(json);

    expect(rebuilt.trackKey, track.trackKey);
    expect(rebuilt.title, track.title);
    expect(rebuilt.artist, track.artist);
    expect(rebuilt.album, track.album);
    expect(rebuilt.durationMs, track.durationMs);
  });
}
