# JojoMusic

Monorepo de départ pour un clone Spotify sur-mesure:

- `apps/mobile`: app Flutter iOS/Android
- `services/core_api`: API FastAPI stateful (auth, likes, playlists, historique, recommandations, paroles)
- `services/resolver_api`: API FastAPI stateless basée sur `yt-dlp` pour résoudre les URLs audio directes

## Démarrage

1. Lancer les services backend:

```bash
docker compose up --build
```

2. Lancer l'app Flutter:

```bash
cd apps/mobile
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Sur iOS Simulator, utiliser:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## Fonctionnalités présentes

- Auth email/mot de passe avec JWT
- Recherche de morceaux
- Résolution de stream audio via `yt-dlp`
- Lecture audio avec `audio_service + just_audio`
- Mini-player et player plein écran
- Favoris
- Historique d'écoute
- Playlists
- Téléchargement hors-ligne local
- Paroles via `LRCLIB`
- Recommandations de base alimentées par likes + historique

## Vérifications effectuées

- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
- `flutter build ios --simulator --no-codesign`
- Health checks backend
- Inscription / connexion
- Recherche
- Résolution audio
- Likes / playlists / historique / home feed
- Paroles

## Variables d'environnement

Voir `.env.example`.

## APK Android et landing

L'APK Android n'est plus versionnée dans Git. Avant de redéployer `apps/landing`, copier l'APK locale vers `apps/landing/downloads/JojoMusique-android.apk`, puis lancer le déploiement Vercel depuis ce dossier.
