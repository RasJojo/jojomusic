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

```mermaid
graph TB
    subgraph apps["📱 Applications"]
        mobile["Mobile App<br/>Flutter<br/><br/>iOS + Android<br/>+ macOS"]
        landing["Landing Page<br/>Web<br/><br/>APK Download<br/>+ Info"]
    end
    
    subgraph services["⚙️ Services (Backend)"]
        core["Core API<br/>NestJS v10<br/>Port 8000<br/><br/>• Auth (JWT)<br/>• Users<br/>• Library<br/>• Search<br/>• Recommendations<br/>• Streaming"]
        resolver["Resolver API<br/>FastAPI<br/>Port 5000<br/><br/>• Spotify<br/>• YouTube<br/>• yt-dlp<br/>• Metadata"]
    end
    
    subgraph data["💾 Data Layer"]
        postgres["PostgreSQL<br/><br/>• Users<br/>• Playlists<br/>• Library<br/>• History"]
        redis["Redis Cache<br/><br/>• Sessions<br/>• Resolved URLs<br/>• Metadata"]
    end
    
    mobile --> core
    landing --> core
    core --> resolver
    core --> postgres
    core --> redis
    resolver --> redis
    
    style apps fill:#e1f5ff
    style services fill:#f3e5f5
    style data fill:#fff3e0
```

---

## 🔍 Flux de Recherche Multi-Source

```mermaid
sequenceDiagram
    participant User as User (App)
    participant Core as Core API
    participant Redis as Redis Cache
    participant Resolver as Resolver API
    participant Spotify as Spotify API
    participant YouTube as YouTube API
    participant YTDLP as yt-dlp
    
    User->>Core: POST /api/search?q=Breaking+Bad
    Core->>Redis: Check cache
    alt Cached
        Redis-->>Core: Return results
        Core-->>User: ✅ Instant
    else Cache Miss
        Core->>Resolver: POST /resolver/search
        Resolver->>Spotify: Try Spotify API
        alt Spotify Match Found
            Spotify-->>Resolver: Track metadata
            Resolver-->>Core: Results
        else No Spotify Match
            Resolver->>YouTube: Try YouTube Music
            alt YouTube Match Found
                YouTube-->>Resolver: Results
            else No YouTube Match
                Resolver->>YTDLP: Generic search
                YTDLP-->>Resolver: Results
            end
        end
        Core->>Redis: Cache results
        Core-->>User: Search results
    end
```

### 2️⃣ Stream Resolution & Playback

```mermaid
graph LR
    A["🎵 User Selects Track"] -->|POST /streaming/resolve| B["Core API"]
    B --> C{Cache Hit?}
    C -->|YES| D["Return stream URL<br/>& metadata"]
    C -->|NO| E["Resolver:<br/>Determine source"]
    
    E --> E1{Spotify<br/>Available?}
    E1 -->|YES| F["Use Spotify<br/>API Preview<br/>or Premium"]
    E1 -->|NO| G["Try YouTube<br/>Music"]
    
    G --> G1{YT Found?}
    G1 -->|YES| H["Extract audio<br/>yt-dlp"]
    G1 -->|NO| I["Generic<br/>yt-dlp search"]
    
    H --> J["FFmpeg<br/>Convert if needed"]
    I --> J
    F --> J
    
    J --> K["Get stream URL<br/>+ codec info"]
    K --> L["Cache<br/>15 min TTL"]
    D --> L
    
    L --> M["📱 App<br/>Player"]
    M --> N["Load audio_service<br/>Play track"]
    N --> O["Sync progress<br/>every 5 sec"]
    O --> P["On end:<br/>Save history<br/>Next track"]
    
    style E fill:#f3e5f5
    style K fill:#fff3e0
    style N fill:#c8e6c9
```

### 3️⃣ Playlist Management

```mermaid
sequenceDiagram
    participant User as User (App)
    participant Core as Core API
    participant Resolver as Resolver API
    participant DB as PostgreSQL
    participant Cache as Redis
    
    User->>Core: POST /api/playlists<br/>{name, tracks}
    Core->>DB: Create playlist
    DB-->>Core: ID created
    Core->>Cache: Invalidate user library
    
    loop For each track
        Core->>Resolver: Resolve stream URL
        Resolver-->>Core: Stream URL
        Core->>DB: Add track to playlist
        Core->>Cache: Store resolved URL
    end
    
    Core-->>User: Playlist created ✅
    Note over User: Syncs across devices
```

### 4️⃣ Offline Downloads

```mermaid
graph TD
    A["User taps<br/>Download"] --> B["Resolver:<br/>Get stream URL"]
    B --> C["Download to<br/>Device Storage"]
    C --> D["Save metadata<br/>locally"]
    D --> E["Mark in DB:<br/>downloadedAt"]
    
    E --> F["Offline Mode<br/>Active"]
    F --> G{Internet?}
    G -->|NO| H["Check local<br/>storage"]
    H --> I["Play from<br/>disk ✅"]
    
    G -->|YES| J["Sync state"]
    J --> K["Update play<br/>counts"]
    K --> L["Cleanup<br/>expired"]
    
    style I fill:#c8e6c9
    style F fill:#fff3e0
```

---

## 🛠️ Composants clés

### Core API Services (NestJS)

```mermaid
graph TD
    subgraph auth["🔐 Authentication"]
        AuthService["AuthService<br/>JWT generation<br/>Token validation<br/>Sessions"]
        UserService["UserService<br/>Profiles<br/>Preferences"]
    end
    
    subgraph library["📚 Library Management"]
        LibService["LibraryService<br/>Likes<br/>Playlists<br/>Favorites"]
        HistoryService["HistoryService<br/>Listen history<br/>Play counts"]
    end
    
    subgraph search["🔍 Search & Streaming"]
        SearchService["SearchService<br/>Orchestrates<br/>Resolver API"]
        StreamService["StreamService<br/>URL resolution<br/>Caching"]
    end
    
    subgraph ml["🧠 Intelligence"]
        RecommendService["RecommendationService<br/>ML suggestions<br/>Likes + history"]
    end
    
    style auth fill:#e1f5ff
    style library fill:#f3e5f5
    style search fill:#fff3e0
    style ml fill:#c8e6c9
```

### Resolver Services (Python)

```mermaid
graph LR
    A["Query:<br/>Breaking Bad"] --> B["Resolver<br/>Orchestrator"]
    
    B --> C["SpotifySource<br/>Web API"]
    B --> D["YouTubeSource<br/>Parsing"]
    B --> E["FallbackSource<br/>yt-dlp"]
    
    C --> F["🔗 Match?"]
    D --> F
    E --> F
    
    F --> G["Metadata<br/>Enrichment<br/>• Artwork<br/>• Duration<br/>• Codec"]
    
    G --> H["Cache<br/>Redis<br/>TTL: 15min"]
    
    H --> I["Return URL<br/>+ Metadata"]
    
    style B fill:#f3e5f5
    style G fill:#fff3e0
    style I fill:#c8e6c9
```

### App Components (Flutter)

```mermaid
graph TB
    subgraph screens["📱 Screens"]
        HomeScreen["HomeScreen<br/>Recommendations<br/>Recently played"]
        SearchScreen["SearchScreen<br/>Track/Album/Artist<br/>search"]
        PlaylistScreen["PlaylistScreen<br/>Browse<br/>Edit<br/>Manage"]
        PlayerScreen["PlayerScreen<br/>Full-screen<br/>Lyrics<br/>Controls"]
        MiniPlayer["MiniPlayerBar<br/>Bottom persistent<br/>quick controls"]
        LibraryScreen["LibraryScreen<br/>Favorites<br/>Downloads"]
    end
    
    subgraph state["🔄 State (Riverpod)"]
        AuthProvider["authProvider<br/>Token<br/>User"]
        PlaybackProvider["playbackProvider<br/>Current track<br/>Position"]
        LibraryProvider["libraryProvider<br/>Favorites<br/>Playlists"]
    end
    
    subgraph audio["🔊 Audio"]
        AudioHandler["AudioHandler<br/>Background<br/>Notifications"]
        JustAudio["just_audio<br/>Codec support<br/>Streaming"]
    end
    
    HomeScreen --> AuthProvider
    SearchScreen --> AuthProvider
    PlaylistScreen --> LibraryProvider
    PlayerScreen --> PlaybackProvider
    MiniPlayer --> PlaybackProvider
    
    PlayerScreen --> AudioHandler
    AudioHandler --> JustAudio
    
    style screens fill:#e1f5ff
    style state fill:#f3e5f5
    style audio fill:#fff3e0
```

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

### Système de recommandations

```mermaid
graph LR
    A["User Behavior"] --> B["Likes Count"]
    A --> C["Listen History"]
    A --> D["Playlists"]
    
    B --> E["🧮 Recommendation<br/>Algorithm"]
    C --> E
    D --> E
    
    E --> F["Score = <br/>likes×0.4 +<br/>listen×0.3 +<br/>genre×0.2 +<br/>artist×0.1"]
    
    F --> G{Score > 7?}
    G -->|YES| H["✅ Show on Home<br/>Rank by score"]
    G -->|NO| I["Hidden<br/>Fallback"]
    
    H --> J["Personalized<br/>Feed"]
    I --> J
    
    style E fill:#f3e5f5
    style J fill:#c8e6c9
```

### Audio Playback Stack

```mermaid
graph TD
    A["Flutter App"] --> B["audio_service<br/>Background playback<br/>Media notifications<br/>Lock screen controls"]
    B --> C["just_audio<br/>Codec support<br/>Streaming handling<br/>Position sync"]
    C --> D["Native Audio<br/>iOS: AirPlay<br/>Android: Cast<br/>Headphone controls"]
    
    style B fill:#f3e5f5
    style C fill:#fff3e0
    style D fill:#c8e6c9
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
