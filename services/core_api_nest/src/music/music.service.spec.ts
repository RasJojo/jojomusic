import { MusicService } from './music.service';
import {
  ArtistPayload,
  PodcastPayload,
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

  it('maps podcast episodes safely when XML fields are objects with attributes', () => {
    const podcast: PodcastPayload = {
      podcast_key: '1612444837',
      title: 'Zack en Roue Libre by Zack Nani',
      publisher: 'Zack Nani',
      description: null,
      artwork_url: 'https://example.com/show.jpg',
      feed_url: 'https://example.com/feed.xml',
      external_url: 'https://example.com',
      episode_count: 10,
      release_date: new Date('2026-03-25T11:22:00.000Z'),
    };

    const episodes = service.mapPodcastEpisodes(
      podcast,
      [
        {
          guid: {
            '#text':
              '9ffecc30-b8a3-4ea5-bcb9-488a1b61e47c',
            isPermaLink: 'false',
          },
          title: 'Episode 1',
          description: '<p>Bonjour &amp; bienvenue</p>',
          enclosure: { url: 'https://cdn.example.com/episode.mp3' },
          'itunes:duration': '01:29:44',
          pubDate: 'Wed, 25 Mar 2026 11:22:00 GMT',
          'itunes:image': {
            href: 'https://cdn.example.com/episode.jpg',
          },
        },
      ],
      16,
    );

    expect(episodes).toHaveLength(1);
    expect(episodes[0]?.episode_key).toBe(
      '1612444837-9ffecc30-b8a3-4ea5-bcb9-488a1b61e47c',
    );
    expect(episodes[0]?.title).toBe('Episode 1');
    expect(episodes[0]?.description).toBe('Bonjour & bienvenue');
    expect(episodes[0]?.audio_url).toBe('https://cdn.example.com/episode.mp3');
    expect(episodes[0]?.artwork_url).toBe('https://cdn.example.com/episode.jpg');
    expect(episodes[0]?.duration_seconds).toBe(5384);
  });

  it('extracts xml text from nested attribute objects', () => {
    expect(
      service.xmlText({
        '#text': 'Lock In',
        lang: 'fr',
      }),
    ).toBe('Lock In');
  });

  it('generates podcast search variants for long creator queries', () => {
    const variants = service.podcastSearchVariants(
      'lockin arthur zack joel',
    );

    expect(variants).toContain('lock in arthur zack joel');
    expect(variants).toContain('lockin');
    expect(variants).toContain('arthur zack joel');
  });

  it('scores exact podcast title matches above artist-only matches', () => {
    const podcast: PodcastPayload = {
      podcast_key: '1793316009',
      title: 'RADIO CONFESSION',
      publisher: 'Henry Tran',
      description: null,
      artwork_url: null,
      feed_url: null,
      external_url: null,
      episode_count: 16,
      release_date: new Date('2026-03-25T11:22:00.000Z'),
    };

    expect(
      service.scorePodcastSearchResult(
        'radio confession henry tran',
        podcast,
      ),
    ).toBeGreaterThan(0);
  });
});
