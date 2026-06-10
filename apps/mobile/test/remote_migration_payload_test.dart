import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/models/app_models.dart';

const _baseUrl = 'https://convex-site.jojoserv.com';
const _email = 'joela.rasam@gmail.com';

void main() {
  test('migrated library payloads parse with mobile models', () async {
    final password = Platform.environment['JOJOMUSIC_TEST_PASSWORD'];
    if (password == null || password.isEmpty) {
      markTestSkipped('JOJOMUSIC_TEST_PASSWORD is not set');
      return;
    }

    final client = HttpClient();
    addTearDown(client.close);

    Future<_Response> request(
      String method,
      String path, {
      Object? body,
      String? token,
    }) async {
      final request = await client.openUrl(method, Uri.parse('$_baseUrl$path'));
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return _Response(response.statusCode, text);
    }

    final login = await request(
      'POST',
      '/auth/login',
      body: {'email': _email, 'password': password},
    );
    expect(login.statusCode, 200, reason: login.text);
    final loginJson = jsonDecode(login.text) as Map<String, dynamic>;
    final token = loginJson['access_token'] as String;

    final likes = await request('GET', '/me/likes', token: token);
    expect(likes.statusCode, 200, reason: likes.text);
    final likeItems = jsonDecode(likes.text) as List<dynamic>;
    expect(
      likeItems
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .length,
      greaterThan(0),
    );

    final playlists = await request('GET', '/playlists', token: token);
    expect(playlists.statusCode, 200, reason: playlists.text);
    final playlistItems = jsonDecode(playlists.text) as List<dynamic>;
    expect(
      playlistItems
          .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
          .length,
      greaterThan(0),
    );

    final podcasts = await request('GET', '/me/podcasts', token: token);
    expect(podcasts.statusCode, 200, reason: podcasts.text);
    final podcastItems = jsonDecode(podcasts.text) as List<dynamic>;
    expect(
      podcastItems
          .map((item) => Podcast.fromJson(item as Map<String, dynamic>))
          .length,
      greaterThan(0),
    );

    final home = await request('GET', '/me/home', token: token);
    expect(home.statusCode, 200, reason: home.text);
    HomeData.fromJson(jsonDecode(home.text) as Map<String, dynamic>);
  });
}

class _Response {
  const _Response(this.statusCode, this.text);

  final int statusCode;
  final String text;
}
