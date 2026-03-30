import { MusicService } from './music.service';
import {
  ArtistPayload,
  SearchResponse,
  buildArtistKey,
  makeTrackPayload,
} from '../common/payloads';

describe('MusicService exact-title youtube fallback', () => {
  const service = Object.create(MusicService.prototype) as any;

  const melkyArtist: ArtistPayload = {
    artist_key: buildArtistKey('Melky'),
    name: 'Melky',
    provider: 'lastfm',
    image_url: null,
    external_id: null,
    url: null,
    listeners: 1_000,
    summary: null,
  };

  it('forces youtube fallback when a title matches but featured artists are missing', () => {
    const tracks = [
      makeTrackPayload({
        artist: 'Melky',
        title: 'Te hanaraka anao',
        provider: 'lastfm',
      }),
    ];

    expect(
      service.shouldUseYoutubeSearchFallback(
        'MELKY ft. PRINCIO - TE HANARAKA ANAO',
        tracks,
        [melkyArtist],
      ),
    ).toBe(true);
  });

  it('keeps the catalog result for clean artist-title searches that already match exactly', () => {
    const tracks = [
      makeTrackPayload({
        artist: 'Joji',
        title: 'Glimpse of Us',
        provider: 'itunes',
      }),
    ];

    expect(
      service.shouldUseYoutubeSearchFallback('Joji - Glimpse of Us', tracks, [
        {
          artist_key: buildArtistKey('Joji'),
          name: 'Joji',
          provider: 'itunes',
          image_url: null,
          external_id: null,
          url: null,
          listeners: 1_000_000,
          summary: null,
        },
      ]),
    ).toBe(false);
  });

  it('rejects indexed results that only match the title part of a youtube-style query', () => {
    const indexed: SearchResponse = {
      query: 'MELKY ft. PRINCIO - TE HANARAKA ANAO',
      artists: [melkyArtist],
      tracks: [
        makeTrackPayload({
          artist: 'Melky',
          title: 'Te hanaraka anao',
          provider: 'lastfm',
        }),
      ],
      albums: [
        {
          album_key: 'album:test',
          title: 'Some album',
          artist: 'Melky',
          provider: 'itunes',
          artwork_url: null,
          external_id: null,
          summary: null,
          release_date: null,
          track_count: null,
        },
      ],
      podcasts: [],
    };

    expect(
      service.hasUsefulIndexedSearch(
        indexed,
        'MELKY ft. PRINCIO - TE HANARAKA ANAO',
        8,
      ),
    ).toBe(false);
  });

  it('forces youtube fallback for explicit video-style queries even when generic catalog titles partially match', () => {
    const tracks = [
      makeTrackPayload({
        artist: 'Coldplay',
        title: 'A Sky Full of Stars',
        provider: 'itunes',
      }),
      makeTrackPayload({
        artist: 'Chris Brown',
        title: 'Party',
        provider: 'itunes',
      }),
    ];

    expect(
      service.shouldUseYoutubeSearchFallback('D-FULL PARTY 2015 Music Video', tracks, []),
    ).toBe(true);
  });
});
