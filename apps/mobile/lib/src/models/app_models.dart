class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final DateTime? createdAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.tryParse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    if (createdAt != null) 'created_at': createdAt?.toIso8601String(),
  };
}

const favoritesPlaylistId = '__favorites__';

class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final UserProfile user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['access_token'] as String,
    user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'user': user.toJson(),
  };
}

class SpotifyIntegration {
  const SpotifyIntegration({
    required this.configured,
    required this.connected,
    required this.savedShows,
    this.configurationHint,
    this.spotifyUserId,
    this.displayName,
    this.email,
    this.avatarUrl,
    this.country,
    this.product,
    this.importedAt,
    this.likedTracksImported = 0,
    this.savedShowsImported = 0,
    this.savedEpisodesImported = 0,
    this.recentTracksImported = 0,
  });

  final bool configured;
  final bool connected;
  final String? configurationHint;
  final String? spotifyUserId;
  final String? displayName;
  final String? email;
  final String? avatarUrl;
  final String? country;
  final String? product;
  final DateTime? importedAt;
  final int likedTracksImported;
  final int savedShowsImported;
  final int savedEpisodesImported;
  final int recentTracksImported;
  final List<Podcast> savedShows;

  factory SpotifyIntegration.fromJson(Map<String, dynamic> json) =>
      SpotifyIntegration(
        configured: (json['configured'] as bool?) ?? false,
        connected: (json['connected'] as bool?) ?? false,
        configurationHint: json['configuration_hint'] as String?,
        spotifyUserId: json['spotify_user_id'] as String?,
        displayName: json['display_name'] as String?,
        email: json['email'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        country: json['country'] as String?,
        product: json['product'] as String?,
        importedAt: json['imported_at'] == null
            ? null
            : DateTime.tryParse(json['imported_at'] as String),
        likedTracksImported: (json['liked_tracks_imported'] as int?) ?? 0,
        savedShowsImported: (json['saved_shows_imported'] as int?) ?? 0,
        savedEpisodesImported: (json['saved_episodes_imported'] as int?) ?? 0,
        recentTracksImported: (json['recent_tracks_imported'] as int?) ?? 0,
        savedShows: (json['saved_shows'] as List<dynamic>? ?? [])
            .map((item) => Podcast.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class Track {
  const Track({
    required this.trackKey,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    this.artistImageUrl,
    this.durationMs,
    this.provider = 'internal',
    this.externalId,
    this.previewUrl,
    this.lyricsSyncedAvailable = false,
  });

  final String trackKey;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final String? artistImageUrl;
  final int? durationMs;
  final String provider;
  final String? externalId;
  final String? previewUrl;
  final bool lyricsSyncedAvailable;

  String? get displayArtworkUrl {
    if (artworkUrl != null && artworkUrl!.isNotEmpty) {
      return artworkUrl;
    }
    if (artistImageUrl != null && artistImageUrl!.isNotEmpty) {
      return artistImageUrl;
    }
    return null;
  }

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    trackKey: json['track_key'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    album: json['album'] as String?,
    artworkUrl: json['artwork_url'] as String?,
    artistImageUrl: json['artist_image_url'] as String?,
    durationMs: json['duration_ms'] as int?,
    provider: (json['provider'] as String?) ?? 'internal',
    externalId: json['external_id'] as String?,
    previewUrl: json['preview_url'] as String?,
    lyricsSyncedAvailable: (json['lyrics_synced_available'] as bool?) ?? false,
  );

  Track copyWith({
    String? trackKey,
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    String? artistImageUrl,
    int? durationMs,
    String? provider,
    String? externalId,
    String? previewUrl,
    bool? lyricsSyncedAvailable,
  }) => Track(
    trackKey: trackKey ?? this.trackKey,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    artworkUrl: artworkUrl ?? this.artworkUrl,
    artistImageUrl: artistImageUrl ?? this.artistImageUrl,
    durationMs: durationMs ?? this.durationMs,
    provider: provider ?? this.provider,
    externalId: externalId ?? this.externalId,
    previewUrl: previewUrl ?? this.previewUrl,
    lyricsSyncedAvailable: lyricsSyncedAvailable ?? this.lyricsSyncedAvailable,
  );

  Map<String, dynamic> toJson() => {
    'track_key': trackKey,
    'title': title,
    'artist': artist,
    'album': album,
    'artwork_url': artworkUrl,
    'artist_image_url': artistImageUrl,
    'duration_ms': durationMs,
    'provider': provider,
    'external_id': externalId,
    'preview_url': previewUrl,
    'lyrics_synced_available': lyricsSyncedAvailable,
  };
}

class Artist {
  const Artist({
    required this.artistKey,
    required this.name,
    this.imageUrl,
    this.provider = 'internal',
    this.externalId,
    this.url,
    this.listeners,
    this.summary,
  });

  final String artistKey;
  final String name;
  final String? imageUrl;
  final String provider;
  final String? externalId;
  final String? url;
  final int? listeners;
  final String? summary;

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
    artistKey: json['artist_key'] as String,
    name: json['name'] as String,
    imageUrl: json['image_url'] as String?,
    provider: (json['provider'] as String?) ?? 'internal',
    externalId: json['external_id'] as String?,
    url: json['url'] as String?,
    listeners: json['listeners'] as int?,
    summary: json['summary'] as String?,
  );
}

class Album {
  const Album({
    required this.albumKey,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.provider = 'internal',
    this.externalId,
    this.summary,
    this.releaseDate,
    this.trackCount,
  });

  final String albumKey;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String provider;
  final String? externalId;
  final String? summary;
  final DateTime? releaseDate;
  final int? trackCount;

  factory Album.fromJson(Map<String, dynamic> json) => Album(
    albumKey: json['album_key'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    artworkUrl: json['artwork_url'] as String?,
    provider: (json['provider'] as String?) ?? 'internal',
    externalId: json['external_id'] as String?,
    summary: json['summary'] as String?,
    releaseDate: json['release_date'] == null
        ? null
        : DateTime.tryParse(json['release_date'] as String),
    trackCount: json['track_count'] as int?,
  );
}

class Podcast {
  const Podcast({
    required this.podcastKey,
    required this.title,
    required this.publisher,
    this.description,
    this.artworkUrl,
    this.feedUrl,
    this.externalUrl,
    this.episodeCount,
    this.releaseDate,
  });

  final String podcastKey;
  final String title;
  final String publisher;
  final String? description;
  final String? artworkUrl;
  final String? feedUrl;
  final String? externalUrl;
  final int? episodeCount;
  final DateTime? releaseDate;

  factory Podcast.fromJson(Map<String, dynamic> json) => Podcast(
    podcastKey: json['podcast_key'] as String,
    title: json['title'] as String,
    publisher: json['publisher'] as String,
    description: json['description'] as String?,
    artworkUrl: json['artwork_url'] as String?,
    feedUrl: json['feed_url'] as String?,
    externalUrl: json['external_url'] as String?,
    episodeCount: json['episode_count'] as int?,
    releaseDate: json['release_date'] == null
        ? null
        : DateTime.tryParse(json['release_date'] as String),
  );

  Map<String, dynamic> toJson() => {
    'podcast_key': podcastKey,
    'title': title,
    'publisher': publisher,
    'description': description,
    'artwork_url': artworkUrl,
    'feed_url': feedUrl,
    'external_url': externalUrl,
    'episode_count': episodeCount,
    'release_date': releaseDate?.toIso8601String(),
  };
}

class PodcastEpisode {
  const PodcastEpisode({
    required this.episodeKey,
    required this.podcastTitle,
    required this.title,
    this.publisher,
    this.description,
    this.artworkUrl,
    this.audioUrl,
    this.externalUrl,
    this.durationSeconds,
    this.publishedAt,
  });

  final String episodeKey;
  final String podcastTitle;
  final String title;
  final String? publisher;
  final String? description;
  final String? artworkUrl;
  final String? audioUrl;
  final String? externalUrl;
  final int? durationSeconds;
  final DateTime? publishedAt;

  factory PodcastEpisode.fromJson(Map<String, dynamic> json) => PodcastEpisode(
    episodeKey: json['episode_key'] as String,
    podcastTitle: json['podcast_title'] as String,
    title: json['title'] as String,
    publisher: json['publisher'] as String?,
    description: json['description'] as String?,
    artworkUrl: json['artwork_url'] as String?,
    audioUrl: json['audio_url'] as String?,
    externalUrl: json['external_url'] as String?,
    durationSeconds: json['duration_seconds'] as int?,
    publishedAt: json['published_at'] == null
        ? null
        : DateTime.tryParse(json['published_at'] as String),
  );
}

class BrowseCategory {
  const BrowseCategory({
    required this.categoryId,
    required this.title,
    required this.subtitle,
    required this.colorHex,
    required this.searchSeed,
    this.artworkUrl,
  });

  final String categoryId;
  final String title;
  final String subtitle;
  final String colorHex;
  final String searchSeed;
  final String? artworkUrl;

  factory BrowseCategory.fromJson(Map<String, dynamic> json) => BrowseCategory(
    categoryId: json['category_id'] as String,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String,
    colorHex: json['color_hex'] as String,
    searchSeed: json['search_seed'] as String,
    artworkUrl: json['artwork_url'] as String?,
  );
}

class GeneratedPlaylist {
  const GeneratedPlaylist({
    required this.playlistKey,
    required this.title,
    required this.subtitle,
    required this.tracks,
    this.artworkUrl,
  });

  final String playlistKey;
  final String title;
  final String subtitle;
  final List<Track> tracks;
  final String? artworkUrl;

  String? get displayArtworkUrl {
    if (artworkUrl != null && artworkUrl!.isNotEmpty) {
      return artworkUrl;
    }
    for (final track in tracks) {
      final artworkUrl = track.displayArtworkUrl;
      if (artworkUrl != null && artworkUrl.isNotEmpty) {
        return artworkUrl;
      }
    }
    return null;
  }

  factory GeneratedPlaylist.fromJson(Map<String, dynamic> json) =>
      GeneratedPlaylist(
        playlistKey: json['playlist_key'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String,
        artworkUrl: json['artwork_url'] as String?,
        tracks: (json['tracks'] as List<dynamic>? ?? [])
            .map((item) => Track.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class PlaylistTrackItem {
  const PlaylistTrackItem({
    required this.id,
    required this.position,
    required this.track,
  });

  final String id;
  final int position;
  final Track track;

  factory PlaylistTrackItem.fromJson(Map<String, dynamic> json) =>
      PlaylistTrackItem(
        id: json['id'] as String,
        position: json['position'] as int,
        track: Track.fromJson(json['track_payload'] as Map<String, dynamic>),
      );
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.description,
    required this.tracks,
    this.artworkUrl,
  });

  final String id;
  final String name;
  final String description;
  final String? artworkUrl;
  final List<PlaylistTrackItem> tracks;

  String? get displayArtworkUrl {
    if (artworkUrl != null && artworkUrl!.isNotEmpty) {
      return artworkUrl;
    }
    for (final item in tracks) {
      final artworkUrl = item.track.displayArtworkUrl;
      if (artworkUrl != null && artworkUrl.isNotEmpty) {
        return artworkUrl;
      }
    }
    return null;
  }

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    artworkUrl: json['artwork_url'] as String?,
    tracks: (json['tracks'] as List<dynamic>? ?? [])
        .map((item) => PlaylistTrackItem.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class HomeData {
  const HomeData({
    required this.recentlyPlayed,
    required this.likedTracks,
    required this.recommendations,
    required this.generatedPlaylists,
    required this.browseCategories,
    required this.featuredPodcasts,
  });

  final List<Track> recentlyPlayed;
  final List<Track> likedTracks;
  final List<Track> recommendations;
  final List<GeneratedPlaylist> generatedPlaylists;
  final List<BrowseCategory> browseCategories;
  final List<Podcast> featuredPodcasts;

  factory HomeData.fromJson(Map<String, dynamic> json) => HomeData(
    recentlyPlayed: (json['recently_played'] as List<dynamic>)
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList(),
    likedTracks: (json['liked_tracks'] as List<dynamic>)
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList(),
    recommendations: (json['recommendations'] as List<dynamic>)
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList(),
    generatedPlaylists: (json['generated_playlists'] as List<dynamic>? ?? [])
        .map((item) => GeneratedPlaylist.fromJson(item as Map<String, dynamic>))
        .toList(),
    browseCategories: (json['browse_categories'] as List<dynamic>? ?? [])
        .map((item) => BrowseCategory.fromJson(item as Map<String, dynamic>))
        .toList(),
    featuredPodcasts: (json['featured_podcasts'] as List<dynamic>? ?? [])
        .map((item) => Podcast.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class LyricsData {
  const LyricsData({
    required this.artist,
    required this.title,
    this.plainLyrics,
    this.syncedLyrics,
  });

  final String artist;
  final String title;
  final String? plainLyrics;
  final String? syncedLyrics;

  factory LyricsData.fromJson(Map<String, dynamic> json) => LyricsData(
    artist: json['artist'] as String,
    title: json['title'] as String,
    plainLyrics: json['plain_lyrics'] as String?,
    syncedLyrics: json['synced_lyrics'] as String?,
  );
}

class ResolvedStream {
  const ResolvedStream({
    required this.streamUrl,
    required this.title,
    required this.artist,
    this.source,
    this.webpageUrl,
    this.thumbnailUrl,
    this.durationMs,
  });

  final String streamUrl;
  final String title;
  final String artist;
  final String? source;
  final String? webpageUrl;
  final String? thumbnailUrl;
  final int? durationMs;

  factory ResolvedStream.fromJson(Map<String, dynamic> json) => ResolvedStream(
    streamUrl: json['stream_url'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    source: json['source'] as String?,
    webpageUrl: json['webpage_url'] as String?,
    thumbnailUrl: json['thumbnail_url'] as String?,
    durationMs: json['duration_ms'] as int?,
  );
}

class SearchResult {
  const SearchResult({
    required this.query,
    required this.artists,
    required this.tracks,
    required this.albums,
    required this.podcasts,
  });

  final String query;
  final List<Artist> artists;
  final List<Track> tracks;
  final List<Album> albums;
  final List<Podcast> podcasts;

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    query: json['query'] as String,
    artists: (json['artists'] as List<dynamic>? ?? [])
        .map((item) => Artist.fromJson(item as Map<String, dynamic>))
        .toList(),
    tracks: (json['tracks'] as List<dynamic>? ?? [])
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList(),
    albums: (json['albums'] as List<dynamic>? ?? [])
        .map((item) => Album.fromJson(item as Map<String, dynamic>))
        .toList(),
    podcasts: (json['podcasts'] as List<dynamic>? ?? [])
        .map((item) => Podcast.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class ArtistDetails {
  const ArtistDetails({
    required this.artist,
    required this.topTracks,
    required this.topAlbums,
    required this.similarArtists,
  });

  final Artist artist;
  final List<Track> topTracks;
  final List<Album> topAlbums;
  final List<Artist> similarArtists;

  factory ArtistDetails.fromJson(Map<String, dynamic> json) => ArtistDetails(
    artist: Artist.fromJson(json['artist'] as Map<String, dynamic>),
    topTracks: (json['top_tracks'] as List<dynamic>? ?? [])
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList(),
    topAlbums: (json['top_albums'] as List<dynamic>? ?? [])
        .map((item) => Album.fromJson(item as Map<String, dynamic>))
        .toList(),
    similarArtists: (json['similar_artists'] as List<dynamic>? ?? [])
        .map((item) => Artist.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class AlbumDetails {
  const AlbumDetails({required this.album, required this.tracks});

  final Album album;
  final List<Track> tracks;

  factory AlbumDetails.fromJson(Map<String, dynamic> json) => AlbumDetails(
    album: Album.fromJson(json['album'] as Map<String, dynamic>),
    tracks: (json['tracks'] as List<dynamic>? ?? [])
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class BrowseCategoryResult {
  const BrowseCategoryResult({
    required this.category,
    required this.tracks,
    required this.artists,
    required this.albums,
    required this.podcasts,
  });

  final BrowseCategory category;
  final List<Track> tracks;
  final List<Artist> artists;
  final List<Album> albums;
  final List<Podcast> podcasts;

  factory BrowseCategoryResult.fromJson(Map<String, dynamic> json) =>
      BrowseCategoryResult(
        category: BrowseCategory.fromJson(
          json['category'] as Map<String, dynamic>,
        ),
        tracks: (json['tracks'] as List<dynamic>? ?? [])
            .map((item) => Track.fromJson(item as Map<String, dynamic>))
            .toList(),
        artists: (json['artists'] as List<dynamic>? ?? [])
            .map((item) => Artist.fromJson(item as Map<String, dynamic>))
            .toList(),
        albums: (json['albums'] as List<dynamic>? ?? [])
            .map((item) => Album.fromJson(item as Map<String, dynamic>))
            .toList(),
        podcasts: (json['podcasts'] as List<dynamic>? ?? [])
            .map((item) => Podcast.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class PodcastDetails {
  const PodcastDetails({required this.podcast, required this.episodes});

  final Podcast podcast;
  final List<PodcastEpisode> episodes;

  factory PodcastDetails.fromJson(Map<String, dynamic> json) => PodcastDetails(
    podcast: Podcast.fromJson(json['podcast'] as Map<String, dynamic>),
    episodes: (json['episodes'] as List<dynamic>? ?? [])
        .map((item) => PodcastEpisode.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}
