"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BROWSE_CATEGORIES = void 0;
exports.normalizeValue = normalizeValue;
exports.buildTrackKey = buildTrackKey;
exports.buildArtistKey = buildArtistKey;
exports.buildAlbumKey = buildAlbumKey;
exports.makeTrackPayload = makeTrackPayload;
exports.toUserOut = toUserOut;
exports.generateId = generateId;
const node_crypto_1 = require("node:crypto");
exports.BROWSE_CATEGORIES = [
    {
        category_id: 'new-releases',
        title: 'Nouveautés',
        subtitle: 'Dernières sorties, singles frais et nouveautés à lancer',
        color_hex: '#C04A23',
        search_seed: 'new music friday',
    },
    {
        category_id: 'pop-hits',
        title: 'Pop',
        subtitle: 'Hits immédiats, refrains massifs et grosses sorties',
        color_hex: '#8B2877',
        search_seed: 'pop hits',
    },
    {
        category_id: 'rap-hiphop',
        title: 'Rap & Hip-Hop',
        subtitle: 'Rap FR, US, trap et gros titres du moment',
        color_hex: '#B1591E',
        search_seed: 'rap hip hop',
    },
    {
        category_id: 'afro-vibes',
        title: 'Afro',
        subtitle: 'Afrobeats, amapiano et chaleur instantanée',
        color_hex: '#7A5A00',
        search_seed: 'afrobeats amapiano',
    },
    {
        category_id: 'mada-vibes',
        title: 'Madagascar',
        subtitle: 'Mada vibes, rap local, salegy et scène malgache',
        color_hex: '#007A62',
        search_seed: 'music malagasy',
    },
    {
        category_id: 'chill-mood',
        title: 'Chill',
        subtitle: 'Calme, focus, late night et textures douces',
        color_hex: '#274A9A',
        search_seed: 'chill hits',
    },
    {
        category_id: 'workout-energy',
        title: 'Workout',
        subtitle: 'Énergie, cardio, motivation et percussions lourdes',
        color_hex: '#1E8554',
        search_seed: 'workout mix',
    },
    {
        category_id: 'love-songs',
        title: 'Love',
        subtitle: 'Slow jams, pop sentimentale et titres à émotions',
        color_hex: '#A02458',
        search_seed: 'love songs rnb',
    },
    {
        category_id: 'podcasts-editorial',
        title: 'Podcasts musicaux',
        subtitle: 'Culture, interviews, société et épisodes longs',
        color_hex: '#5A276F',
        search_seed: 'podcast francais',
    },
];
function normalizeValue(value) {
    return value
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');
}
function buildTrackKey(artist, title) {
    return normalizeValue(`${artist}-${title}`);
}
function buildArtistKey(name) {
    return normalizeValue(name);
}
function buildAlbumKey(artist, title) {
    return normalizeValue(`${artist}-${title}`);
}
function makeTrackPayload(partial) {
    return {
        track_key: partial.track_key ?? buildTrackKey(partial.artist, partial.title),
        title: partial.title,
        artist: partial.artist,
        album: partial.album ?? null,
        artwork_url: partial.artwork_url ?? null,
        artist_image_url: partial.artist_image_url ?? null,
        duration_ms: partial.duration_ms ?? null,
        provider: partial.provider ?? 'internal',
        external_id: partial.external_id ?? null,
        preview_url: partial.preview_url ?? null,
        lyrics_synced_available: partial.lyrics_synced_available ?? false,
    };
}
function toUserOut(user) {
    return {
        id: user.id,
        name: user.name,
        email: user.email,
        created_at: user.createdAt,
    };
}
function generateId() {
    return (0, node_crypto_1.randomUUID)();
}
//# sourceMappingURL=payloads.js.map