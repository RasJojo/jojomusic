"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PlaylistsService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
const payloads_1 = require("../common/payloads");
const music_service_1 = require("../music/music.service");
let PlaylistsService = class PlaylistsService {
    prisma;
    musicService;
    constructor(prisma, musicService) {
        this.prisma = prisma;
        this.musicService = musicService;
    }
    async list(user) {
        const playlists = await this.prisma.playlist.findMany({
            where: { userId: user.id },
            include: { tracks: { orderBy: { position: 'asc' } } },
            orderBy: { updatedAt: 'desc' },
        });
        const hydratedPlaylists = await Promise.all(playlists.map((playlist) => this.hydratePlaylistVisuals(playlist)));
        void this.musicService.primeAudioAssets(hydratedPlaylists.flatMap((playlist) => this.trackPayloads(playlist.tracks)).slice(0, 10), 8);
        return hydratedPlaylists.map((playlist) => this.toPlaylistOut(playlist));
    }
    async create(user, payload) {
        const playlist = await this.prisma.playlist.create({
            data: {
                id: (0, payloads_1.generateId)(),
                userId: user.id,
                name: payload.name.trim(),
                description: payload.description?.trim() ?? '',
                artworkUrl: payload.artwork_url ?? null,
            },
            include: { tracks: { orderBy: { position: 'asc' } } },
        });
        return this.toPlaylistOut(await this.hydratePlaylistVisuals(playlist));
    }
    async update(user, playlistId, payload) {
        const playlist = await this.prisma.playlist.findFirst({
            where: { id: playlistId, userId: user.id },
            include: { tracks: { orderBy: { position: 'asc' } } },
        });
        if (!playlist) {
            throw new common_1.NotFoundException('Playlist not found');
        }
        const data = {
            updatedAt: new Date(),
        };
        if (payload.name != null) {
            data.name = payload.name.trim();
        }
        if (payload.description != null) {
            data.description = payload.description.trim();
        }
        if (payload.artwork_url != null) {
            data.artworkUrl = payload.artwork_url.trim() || null;
        }
        const updated = await this.prisma.playlist.update({
            where: { id: playlist.id },
            data,
            include: { tracks: { orderBy: { position: 'asc' } } },
        });
        const hydrated = await this.hydratePlaylistVisuals(updated);
        void this.musicService.primeAudioAssets(this.trackPayloads(hydrated.tracks), 6);
        return this.toPlaylistOut(hydrated);
    }
    async addTrack(user, playlistId, payload) {
        const playlist = await this.prisma.playlist.findFirst({
            where: { id: playlistId, userId: user.id },
            include: { tracks: { orderBy: { position: 'asc' } } },
        });
        if (!playlist) {
            throw new common_1.NotFoundException('Playlist not found');
        }
        const existing = playlist.tracks.find((track) => track.trackKey === payload.track.track_key);
        if (!existing) {
            await this.prisma.playlistTrack.create({
                data: {
                    id: (0, payloads_1.generateId)(),
                    playlistId: playlist.id,
                    trackKey: payload.track.track_key,
                    position: playlist.tracks.length,
                    trackPayload: payload.track,
                },
            });
            await this.prisma.playlist.update({
                where: { id: playlist.id },
                data: {
                    updatedAt: new Date(),
                    artworkUrl: playlist.artworkUrl ?? payload.track.artwork_url ?? null,
                },
            });
        }
        const refreshed = await this.prisma.playlist.findUnique({
            where: { id: playlist.id },
            include: { tracks: { orderBy: { position: 'asc' } } },
        });
        if (refreshed) {
            const hydrated = await this.hydratePlaylistVisuals(refreshed);
            void this.musicService.primeAudioAssets(this.trackPayloads(hydrated.tracks), 6);
            return this.toPlaylistOut(hydrated);
        }
        return this.toPlaylistOut(refreshed);
    }
    async removeTrack(user, playlistId, trackKey) {
        const playlist = await this.prisma.playlist.findFirst({
            where: { id: playlistId, userId: user.id },
            include: { tracks: { orderBy: { position: 'asc' } } },
        });
        if (!playlist) {
            throw new common_1.NotFoundException('Playlist not found');
        }
        await this.prisma.playlistTrack.deleteMany({
            where: { playlistId: playlist.id, trackKey },
        });
        const refreshed = await this.prisma.playlist.findUnique({
            where: { id: playlist.id },
            include: { tracks: { orderBy: { position: 'asc' } } },
        });
        if (!refreshed) {
            throw new common_1.NotFoundException('Playlist not found');
        }
        await this.prisma.$transaction(refreshed.tracks.map((track, index) => this.prisma.playlistTrack.update({
            where: { id: track.id },
            data: { position: index },
        })));
        const artwork = refreshed.tracks.find((track) => track.trackPayload?.artwork_url)?.trackPayload;
        const updated = await this.prisma.playlist.update({
            where: { id: refreshed.id },
            data: {
                updatedAt: new Date(),
                artworkUrl: artwork?.artwork_url ?? null,
            },
            include: { tracks: { orderBy: { position: 'asc' } } },
        });
        const hydrated = await this.hydratePlaylistVisuals(updated);
        void this.musicService.primeAudioAssets(this.trackPayloads(hydrated.tracks), 6);
        return this.toPlaylistOut(hydrated);
    }
    async delete(user, playlistId) {
        const playlist = await this.prisma.playlist.findFirst({
            where: { id: playlistId, userId: user.id },
        });
        if (!playlist) {
            throw new common_1.NotFoundException('Playlist not found');
        }
        await this.prisma.playlist.delete({ where: { id: playlist.id } });
    }
    trackPayloads(tracks) {
        return tracks
            .map((track) => track.trackPayload)
            .filter((track) => track != null);
    }
    async hydratePlaylistVisuals(playlist) {
        const tracks = this.trackPayloads(playlist.tracks);
        if (tracks.length == 0) {
            return playlist;
        }
        const subset = tracks.slice(0, 4);
        const enrichedSubset = await Promise.all(subset.map((track) => this.enrichTrackVisualFallback(track)));
        const hydratedSubset = await this.musicService.attachManagedTrackVisuals(enrichedSubset);
        const hydratedByKey = new Map(hydratedSubset.map((track) => [track.track_key, track]));
        const updatedTracks = playlist.tracks.map((track) => {
            const hydrated = hydratedByKey.get(track.trackKey);
            if (!hydrated) {
                return track;
            }
            return {
                ...track,
                trackPayload: hydrated,
            };
        });
        return {
            ...playlist,
            artworkUrl: playlist.artworkUrl ?? this.bestPlaylistArtwork(updatedTracks),
            tracks: updatedTracks,
        };
    }
    bestPlaylistArtwork(tracks) {
        for (const track of this.trackPayloads(tracks)) {
            if (track.artwork_url && track.artwork_url.length > 0) {
                return track.artwork_url;
            }
            if (track.artist_image_url && track.artist_image_url.length > 0) {
                return track.artist_image_url;
            }
        }
        return null;
    }
    async enrichTrackVisualFallback(track) {
        if ((track.artwork_url && track.artwork_url.length > 0) ||
            (track.artist_image_url && track.artist_image_url.length > 0)) {
            return track;
        }
        const candidates = await this.musicService
            .searchTracks(`${track.artist} ${track.title}`, 4)
            .catch(() => []);
        if (candidates.length == 0) {
            return track;
        }
        for (const candidate of candidates) {
            if (this.normalizeForMatch(candidate.artist) == this.normalizeForMatch(track.artist) &&
                this.normalizeForMatch(candidate.title) == this.normalizeForMatch(track.title)) {
                return {
                    ...track,
                    artwork_url: candidate.artwork_url ?? track.artwork_url ?? null,
                    artist_image_url: candidate.artist_image_url ?? track.artist_image_url ?? null,
                };
            }
        }
        const candidate = candidates[0];
        return {
            ...track,
            artwork_url: candidate.artwork_url ?? track.artwork_url ?? null,
            artist_image_url: candidate.artist_image_url ?? track.artist_image_url ?? null,
        };
    }
    normalizeForMatch(value) {
        return `${value ?? ''}`.trim().toLowerCase();
    }
    toPlaylistOut(playlist) {
        return {
            id: playlist.id,
            name: playlist.name,
            description: playlist.description,
            artwork_url: playlist.artworkUrl ?? this.bestPlaylistArtwork(playlist.tracks),
            created_at: playlist.createdAt,
            updated_at: playlist.updatedAt,
            tracks: playlist.tracks.map((track) => ({
                id: track.id,
                track_key: track.trackKey,
                position: track.position,
                track_payload: track.trackPayload,
                created_at: track.createdAt,
            })),
        };
    }
};
exports.PlaylistsService = PlaylistsService;
exports.PlaylistsService = PlaylistsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        music_service_1.MusicService])
], PlaylistsService);
//# sourceMappingURL=playlists.service.js.map