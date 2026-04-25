# 🏗️ JojoMusic Build Guide

## Builds Complétés (24 Avril 2026)

✅ **Web**: `apps/mobile/build/web/` (38 MB)  
✅ **macOS**: `apps/mobile/build/macos/Build/Products/Release/JojoMusique.app` (54.6 MB)  
⏳ **Android APK**: Nécessite configuration Android SDK

---

## 🤖 Configurer Android SDK (pour APK Android)

### Option 1: Script Automatisé (Recommandé)
```bash
bash scripts/setup-android-sdk.sh
```

Puis ajoute à ton `~/.zshrc`:
```bash
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
```

Reload: `source ~/.zshrc`

### Option 2: Configuration Manuelle
1. Télécharge [Android SDK Command-line Tools](https://developer.android.com/studio#command-line-tools-only)
2. Extrais dans `~/Library/Android/sdk/cmdline-tools/latest/`
3. Configure `ANDROID_HOME`:
   ```bash
   export ANDROID_HOME=$HOME/Library/Android/sdk
   export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
   ```

### Vérification
```bash
flutter doctor
```

Tout doit être ✓ vert.

---

## 📱 Builder l'APK Android

Une fois Android SDK configuré:

```bash
cd apps/mobile
flutter build apk --release
```

Le fichier APK sera généré à:
```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 🚀 Déployer les Builds

### Web (Landing Page)
```bash
# Construit automatiquement pour Vercel
# URL: https://jojomusique.vercel.app
```

### macOS (Local)
```bash
# Disponible à:
# apps/mobile/build/macos/Build/Products/Release/JojoMusique.app

# Pour créer un DMG:
cd apps/mobile/build/macos/Build/Products/Release
hdiutil create -volname JojoMusique -srcfolder . -ov -format UDZO JojoMusique.dmg
```

### APK Android
```bash
# Copier vers landing page downloads
cp apps/mobile/build/app/outputs/flutter-apk/app-release.apk \
   apps/landing/downloads/JojoMusique-android.apk

# Mettre à jour metadata.json avec la taille et date
```

---

## 🔧 Bugs Fixes Inclus (24 Avril)

Les builds incluent les 4 corrections critiques:
1. ✅ ResolvedStream missing `source` field
2. ✅ UserProfile schema mismatch  
3. ✅ Dio headers null configuration
4. ✅ Autoplay infinite retry loop

---

## 📊 Build Stats

| Platform | Status | Size | Date |
|----------|--------|------|------|
| Web | ✅ | 38 MB | 24 Apr 2026 |
| macOS | ✅ | 54.6 MB | 24 Apr 2026 |
| Android APK | ⏳ | - | Waiting SDK |

---

## ⚠️ Prochaines Étapes

1. Configure Android SDK
2. Builder l'APK
3. Copier vers `apps/landing/downloads/`
4. Push vers `main` et Vercel

