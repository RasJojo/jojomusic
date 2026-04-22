# 🎵 JojoMusic

Plateforme musicale self-hosted avec recherche multi-source, lecteur audio natif, et synchronisation cross-device. Clone Spotify personnalisé optimisé pour la découverte et les playlists privées.

## 🎯 Vue d'ensemble

JojoMusic est une suite complète pour découvrir, chercher et écouter de la musique en streaming:

- **Monorepo moderne**: NestJS backend + Python resolver + Flutter app
- **Recherche intelligente**: Fallback multi-source (Spotify → YouTube → Local)
- **Lecteur natif**: Audio_service + just_audio, support offline
- **Personnalisation**: Favoris, playlists, historique, recommandations
- **Cross-platform**: Mobile (iOS/Android), Web, Desktop

---

## 🏗️ Architecture Monorepo

```
JojoMusic/
│
├─ apps/
│  │
│  ├─ mobile/
│  │  │  Flutter app (iOS, Android, macOS)
│  │  │  State: Riverpod
│  │  │  Audio: audio_service + just_audio
│  │  │  Player: Full-screen + mini-player
│  │  └─ lib/src/
│  │     ├─ ui/          (screens & widgets)
│  │     ├─ state/       (controllers Riverpod)
│  │     ├─ data/        (API client, models)
│  │     └─ audio/       (playback, notifications)
│  │
│  └─ landing/
│     Landing page web + APK download
│
├─ services/
│  │
│  ├─ core_api_nest/
│  │  │  NestJS API stateful
│  │  │  Port: 8000
│  │  │  Framework: NestJS v10 + Prisma + PostgreSQL
│  │  └─ src/
│  │     ├─ auth/        (JWT, sessions)
│  │     ├─ user/        (profiles, preferences)
│  │     ├─ library/     (likes, playlists)
│  │     ├─ search/      (search multi-source)
│  │     ├─ recommendations/  (algo recommandations)
│  │     └─ streaming/   (lyrics, metadata)
│  │
│  └─ resolver_api/
│     │  Python API stateless
│     │  Port: 5000
│     │  Framework: FastAPI + yt-dlp
│     │  Rôle: Résoudre "chanson" → URL stream audio
│     │
│     └─ app/
│        ├─ sources/     (Spotify, YouTube, fallback)
│        ├─ resolver.py  (orchestration)
│        ├─ metadata.py  (enrichissement)
│        └─ cache.py     (Redis)
│
└─ docker-compose.yml   (orchestration complète)
```

---

## 🎼 Flux d'architecture

```
┌──────────────────────────────┐
│   User App (Mobile/Web)      │
│  • Search input              │
│  • Play track                │
│  • Create playlist           │
└──────────────┬───────────────┘
               │ HTTP/JSON
               │
    ┌──────────▼────────────┐
    │  NGINX/Load Balancer  │
    │  (reverse proxy)       │
    └──┬─────────────────┬───┘
       │                 │
   ┌───▼────────┐   ┌────▼─────────┐
   │ Core API   │   │ Resolver API │
   │ (NestJS)   │   │ (FastAPI)    │
   │ :8000      │   │ :5000        │
   └───┬────────┘   └────┬─────────┘
       │                 │
       │                 ├─→ YouTube Music API
       │                 │
       │                 ├─→ Spotify API
       │                 │
       │                 ├─→ yt-dlp (fallback)
       │                 │
       │                 └─→ FFmpeg (audio extract)
       │
   ┌───▼────────────────┐
   │  PostgreSQL        │
   │  Database          │
   │                    │
   │ • Users            │
   │ • Playlists        │
   │ • Library (likes)  │
   │ • History          │
   │ • Favorites        │
   └────────────────────┘
       │
   ┌───▼────────────┐
   │  Redis Cache   │
   │                │
   │ • Sessions     │
   │ • Resolved URLs│
   │ • Metadata     │
   └────────────────┘
```

---

## 🔍 Flux de recherche & résolution de stream

### 1️⃣ User Search
```
User types: "Breaking Bad intro"
    │
    ▼
App POST /api/search?q=Breaking+Bad+intro
    │ + Bearer Token
    │
    ▼
Core API Backend
    │
    ├─ Check Redis cache (1 hour TTL)
    │  if (cached) return cached_results
    │
    ├─ Query /resolver/search
    │  POST http://resolver_api:5000/search
    │  {query: "Breaking Bad intro"}
    │
    ▼
Resolver API (Stateless)
    │
    ├─ Try Spotify Search API
    │  GET https://api.spotify.com/v1/search
    │  {q: "Breaking Bad intro", type: "track"}
    │
    │  If match found: {title, artist, album, spotify_uri}
    │
    ├─ If no Spotify match → Try YouTube Music
    │  • Parse search results
    │  • Extract official track metadata
    │
    ├─ If still no match → Fallback yt-dlp
    │  yt-dlp -j "ytsearch:{query}"
    │
    ▼
Return: [
  {
    id: "spotify:abc123",
    title: "Breaking Bad Theme",
    artist: "Dave Porter",
    album: "Breaking Bad Soundtrack",
    source: "spotify",
    duration: 45,
    artwork: "https://..."
  },
  {
    id: "youtube:def456",
    title: "Breaking Bad Opening",
    artist: "Dave Porter",
    source: "youtube",
    ...
  }
]
    │
    ├─ Cache in Redis
    │
    ▼
Core API returns to App ✅
    │
    ▼
App displays results + artwork ✅
```

### 2️⃣ User Selects & Plays Track
```
User taps "Breaking Bad Theme" (Spotify version)
    │
    ▼
App POST /api/streaming/resolve
    {trackId: "spotify:abc123"}
    │
    ▼
Core API
    │
    ├─ Check Redis: already resolved?
    │  if (cached && ttl_ok) return stream_url
    │
    ├─ POST /resolver/resolve
    │  {spotify_uri: "spotify:abc123"}
    │
    ▼
Resolver API
    │
    ├─ Has Spotify token? Use Spotify API
    │  GET /v1/tracks/{id}
    │  → Récupère audio preview URL (30 sec)
    │  OR utilise Web Playback SDK (si premium)
    │
    ├─ If Spotify fails → Try YouTube
    │  yt-dlp "Breaking Bad Theme Dave Porter"
    │  → Extract audio URL (opus/m4a codec)
    │
    ├─ Extract with FFmpeg if needed
    │  ffmpeg -i [video] -q:a 0 -map a audio.mp3
    │
    ▼
Return: {
  streamUrl: "https://audio-cdn.../track.m4a",
  codec: "aac",
  bitrate: 256,
  source: "spotify",
  expiresAt: "2026-04-25T10:00:00Z",
  metadata: {
    title: "Breaking Bad Theme",
    artist: "Dave Porter",
    duration: 45
  }
}
    │
    ├─ Cache in Redis (15 min expiry)
    │
    ▼
Core API returns to App ✅
    │
    ▼
App initializes audio_service
    │
    ├─ Load stream URL in media player
    ├─ Set notification with artwork
    ├─ Start playback
    │
    ▼
Track plays ✅
    │
    ├─ Every 5 sec: sync position
    │  POST /api/library/history
    │  {trackId, position, duration}
    │
    ├─ Optional: Fetch lyrics via LRCLIB
    │  GET https://lrclib.net/api/get
    │  {artist_name, track_name}
    │
    │  Display synchronized lyrics on screen
    │
    ▼
On track end
    │
    ├─ Save in listen history
    ├─ Update recommendations
    ├─ Play next track (auto-queue)
    │
    ▼
Complete ✅
```

### 3️⃣ Playlist Management
```
User creates playlist "Running Mix"
    │
    ▼
App POST /api/playlists
    {
      name: "Running Mix",
      isPrivate: true,
      tracks: [{id: "spotify:abc123"}, ...]
    }
    │
    ▼
Core API
    │
    ├─ Create playlist in DB
    ├─ Add tracks with order
    ├─ Invalidate user library cache
    │
    ▼
On each track addition
    │
    ├─ Resolver resolves → cache stream URL
    ├─ Add to history
    │
    ▼
Playlist syncs across devices ✅
```

### 4️⃣ Offline Downloads
```
User taps "Download" on track
    │
    ▼
App calls Resolver for stream URL
    │
    ├─ Downloads audio file to device storage
    ├─ Saves metadata locally
    ├─ Marks in DB: downloadedAt
    │
    ▼
When offline (no internet)
    │
    ├─ Player checks local storage first
    ├─ If exists → play from disk
    ├─ Else → fail gracefully (show "offline")
    │
    ▼
When online again
    │
    ├─ Sync library state
    ├─ Update play counts
    ├─ Delete expired downloads
    │
    ▼
Complete ✅
```

---

## 🛠️ Composants clés

### Core API Services (NestJS)

| Service | Rôle |
|---------|------|
| `AuthService` | JWT generation, token validation, sessions |
| `UserService` | User profiles, preferences, auth |
| `LibraryService` | Likes, playlists, favorites management |
| `HistoryService` | Listen history, play counts, analytics |
| `SearchService` | Orchestrates Resolver API queries |
| `RecommendationService` | ML-based suggestions (likes + history) |
| `StreamService` | Resolves tracks → audio URLs |

### Resolver Services (Python)

| Module | Rôle |
|--------|------|
| `SpotifySource` | Spotify Web API integration |
| `YouTubeSource` | YouTube Music parsing, yt-dlp |
| `FallbackSource` | Generic yt-dlp scraper |
| `Cache` | Redis URL caching with TTL |
| `Metadata` | Artwork, duration, codec detection |
| `Resolver` | Orchestrates source selection |

### App Components (Flutter)

| Screen/Widget | Rôle |
|---------------|------|
| `HomeScreen` | Recommendations, recently played |
| `SearchScreen` | Track/album/artist search |
| `PlaylistScreen` | Browse, edit, manage playlists |
| `PlayerScreen` | Full-screen player with lyrics |
| `MiniPlayerBar` | Persistent bottom player |
| `LibraryScreen` | Liked tracks, downloads |
| `AudioHandler` | background audio + notifications |

---

## 🚀 Installation & Démarrage

### Prerequis
```bash
node -v          # v18+
python -v        # 3.10+
docker -v        # latest
flutter -v       # 3.22+
```

### 1️⃣ Backend Setup (Monorepo)

```bash
# Installer dépendances globales
npm install

# Setup services
cd services/core_api_nest
npm install

cd ../resolver_api
pip install -r requirements.txt

# Retour à la racine
cd ../..
```

### 2️⃣ Configuration `.env`

```bash
# Copier template
cp .env.example .env

# Remplir valeurs:
# - Database credentials (PostgreSQL)
# - Spotify API keys (optionnel)
# - JWT secret
# - Redis host/port
```

### 3️⃣ Lancer Stack Docker

```bash
# Depuis racine
docker compose up --build -d

# Vérifier services
docker compose logs -f

# Services disponibles:
# - Core API: http://localhost:8000
# - Resolver API: http://localhost:5000
# - PostgreSQL: localhost:5432
# - Redis: localhost:6379
```

### 4️⃣ Lancer App Flutter

```bash
cd apps/mobile

# Sur Android Emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# Sur iOS Simulator
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000

# Sur device physique
flutter run --dart-define=API_BASE_URL=https://api.jojomusic.com
```

---

## 🔑 Variables d'environnement

**Core API** (`services/core_api_nest/.env`):
```bash
NODE_ENV=production
DATABASE_URL=postgresql://user:pwd@postgres:5432/jojomusic
REDIS_URL=redis://redis:6379

JWT_SECRET=super-secret-key
JWT_EXPIRY=7d

# Spotify (optionnel, pour meilleure recherche)
SPOTIFY_CLIENT_ID=your_client_id
SPOTIFY_CLIENT_SECRET=your_client_secret

# LRCLIB (lyrics)
LRCLIB_API=https://lrclib.net/api
```

**Resolver API** (`services/resolver_api/.env`):
```bash
REDIS_URL=redis://redis:6379
CORE_API_URL=http://core_api:8000

# yt-dlp options
YT_DLP_COOKIE_FILE=/config/youtube.txt  (optional)
```

**App** (build-time):
```bash
--dart-define=API_BASE_URL=https://api.jojomusic.com
```

---

## 📊 Fonctionnalités détaillées

### Recherche Multi-Source

```
User query: "Dua Lipa Levitating"

┌─────────────────────┐
│ 1. Try Spotify API  │
│    Results: [✓ Found]
└─────────────────────┘
    ↓
Return Spotify + preview

Si Spotify indisponible:
┌─────────────────────┐
│ 2. Try YouTube API  │
│    Results: [✓ Found]
└─────────────────────┘
    ↓
Extract audio via yt-dlp

Si tout échoue:
┌─────────────────────┐
│ 3. Generic Search   │
│    yt-dlp fallback  │
└─────────────────────┘
```

### Système de recommandations

```
Recommendation Score = (
  likes_weight * 0.4 +
  listen_count * 0.3 +
  genre_similarity * 0.2 +
  artist_connection * 0.1
)

Exemple:
User likes: "Breaking Bad" (score: 8/10)
User listened: 5 times
Similar genre: Drama soundtrack
→ Recommended score: 7.5 → Show on Home
```

### Lecteur Audio Natif

```
Audio Playback Stack:
┌───────────────────────────┐
│  Flutter App              │
└────────┬──────────────────┘
         │
┌────────▼──────────────────┐
│  audio_service (plugin)   │
│  • Background playback    │
│  • Media notifications    │
│  • Lock screen controls   │
└────────┬──────────────────┘
         │
┌────────▼──────────────────┐
│  just_audio (plugin)      │
│  • Codec support          │
│  • Streaming handling     │
│  • Position sync          │
└────────┬──────────────────┘
         │
┌────────▼──────────────────┐
│  Native Audio (iOS/Android)
│  • AirPlay (iOS)          │
│  • Cast (Android)         │
│  • Headphone controls     │
└───────────────────────────┘
```

---

## 📱 Build & Deploy

### Build APK Android

```bash
cd apps/mobile

flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.jojomusic.com

# Output: build/app/outputs/flutter-app.apk
# Upload to apps/landing/downloads/
```

### Deploy Backend

```bash
# Sur serveur
docker compose -f docker-compose.server.yml up -d --build

# Health check
curl https://api.jojomusic.com/health
# {"status":"ok"}
```

---

## 🧪 Tests

```bash
# Backend
cd services/core_api_nest
npm run test
npm run test:e2e

# Resolver
cd services/resolver_api
pytest tests/

# App
cd apps/mobile
flutter test
flutter test --coverage
```

---

## 🐛 Troubleshooting

| Problème | Solution |
|----------|----------|
| **App can't connect to API** | Vérifier API_BASE_URL, firewall, backend running |
| **No search results** | Vérifier Spotify API keys, Resolver API logs |
| **Audio doesn't play** | Vérifier stream URL expiry, codec support |
| **Offline mode broken** | Ensure disk permissions, verify cached files exist |
| **Slow search** | Check Redis cache, Resolver performance |

---

## 🎯 Roadmap

- [ ] Playlist collaboration
- [ ] Social features (follow users, share)
- [ ] Advanced recommendations (ML model)
- [ ] Apple Music integration
- [ ] Podcast support
- [ ] Lyrics synchronization (karaoke)
- [ ] Web player (Vue.js)

---

## 📚 Références

- **NestJS**: [Official Docs](https://docs.nestjs.com/)
- **FastAPI**: [Official Docs](https://fastapi.tiangolo.com/)
- **Flutter**: [Official Docs](https://flutter.dev/)
- **Audio**: [audio_service](https://pub.dev/packages/audio_service), [just_audio](https://pub.dev/packages/just_audio)
- **APIs**: [Spotify](https://developer.spotify.com/), [YouTube](https://developers.google.com/youtube), [yt-dlp](https://github.com/yt-dlp/yt-dlp)

---

**Made with ❤️ • Your personal music streaming platform**
