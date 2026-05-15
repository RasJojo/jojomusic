import '../../models/app_models.dart';

// ─── Core ─────────────────────────────────────────────────────────────────────

class YtTrack {
  const YtTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    this.durationMs,
  });

  final String videoId;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final int? durationMs;

  Track toTrack() => Track(
    trackKey: videoId,
    title: title,
    artist: artist,
    album: album,
    artworkUrl: artworkUrl,
    durationMs: durationMs,
    provider: 'youtube',
    externalId: videoId,
  );
}

class YtArtist {
  const YtArtist({
    required this.browseId,
    required this.name,
    this.imageUrl,
    this.subscribers,
  });

  final String browseId;
  final String name;
  final String? imageUrl;
  final String? subscribers;

  Artist toArtist() => Artist(
    artistKey: browseId,
    name: name,
    imageUrl: imageUrl,
    provider: 'youtube',
    externalId: browseId,
  );
}

class YtAlbum {
  const YtAlbum({
    required this.browseId,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.year,
  });

  final String browseId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? year;

  Album toAlbum() => Album(
    albumKey: browseId,
    title: title,
    artist: artist,
    artworkUrl: artworkUrl,
    provider: 'youtube',
    externalId: browseId,
    releaseDate: year != null ? DateTime.tryParse('$year-01-01') : null,
  );
}

class YtPlaylist {
  const YtPlaylist({
    required this.playlistId,
    required this.title,
    this.subtitle,
    this.artworkUrl,
  });

  final String playlistId;
  final String title;
  final String? subtitle;
  final String? artworkUrl;
}

// ─── Search ───────────────────────────────────────────────────────────────────

class YtSearchResult {
  const YtSearchResult({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
  });

  final List<YtTrack> tracks;
  final List<YtArtist> artists;
  final List<YtAlbum> albums;
  final List<YtPlaylist> playlists;

  bool get isEmpty =>
      tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty;
}

// ─── Home ─────────────────────────────────────────────────────────────────────

class YtHomeSection {
  const YtHomeSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<YtHomeItem> items;
}

class YtHomeItem {
  const YtHomeItem({
    required this.title,
    this.subtitle,
    this.artworkUrl,
    this.videoId,
    this.browseId,
    this.playlistId,
  });

  final String title;
  final String? subtitle;
  final String? artworkUrl;
  final String? videoId;
  final String? browseId;
  final String? playlistId;

  bool get isTrack => videoId != null;
  bool get isBrowseable => browseId != null;
}

class YtHomeFeed {
  const YtHomeFeed({required this.sections});
  final List<YtHomeSection> sections;
  bool get isEmpty => sections.isEmpty;
}

// ─── Artist Detail ────────────────────────────────────────────────────────────

class YtArtistDetail {
  const YtArtistDetail({
    required this.name,
    this.imageUrl,
    this.description,
    this.subscribers,
    this.songs = const [],
    this.albums = const [],
  });

  final String name;
  final String? imageUrl;
  final String? description;
  final String? subscribers;
  final List<YtTrack> songs;
  final List<YtAlbum> albums;
}

// ─── Album Detail ─────────────────────────────────────────────────────────────

class YtAlbumDetail {
  const YtAlbumDetail({
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.year,
    this.tracks = const [],
  });

  final String title;
  final String artist;
  final String? artworkUrl;
  final String? year;
  final List<YtTrack> tracks;
}

// ─── Playlist Detail ──────────────────────────────────────────────────────────

class YtPlaylistDetail {
  const YtPlaylistDetail({
    required this.title,
    this.subtitle,
    this.artworkUrl,
    this.tracks = const [],
  });

  final String title;
  final String? subtitle;
  final String? artworkUrl;
  final List<YtTrack> tracks;
}
