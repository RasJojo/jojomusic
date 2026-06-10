#!/usr/bin/env bash
# JojoMusique — release script
# Usage:
#   ./scripts/release.sh android          # Build + deploy APK on landing
#   ./scripts/release.sh web              # Build + deploy web (Vercel)
#   ./scripts/release.sh ios              # Build + upload IPA to App Store Connect
#   ./scripts/release.sh all              # Everything above

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE="$ROOT/apps/mobile"
LANDING="$ROOT/apps/landing"
CREDENTIALS_FILE="$ROOT/.asc_credentials"

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "▶ $*"; }
ok()   { echo "✓ $*"; }
fail() { echo "✗ $*" >&2; exit 1; }

current_version() {
  grep '^version:' "$MOBILE/pubspec.yaml" | sed 's/version: //' | cut -d'+' -f1
}

current_build() {
  grep '^version:' "$MOBILE/pubspec.yaml" | sed 's/.*+//'
}

bump_version() {
  local v="$1" b="$2"
  sed -i '' "s/^version: .*/version: ${v}+${b}/" "$MOBILE/pubspec.yaml"
}

next_patch() {
  local v="$1"
  local patch=$(echo "$v" | cut -d. -f3)
  echo "$(echo "$v" | cut -d. -f1-2).$((patch + 1))"
}

# ── ASC credentials ───────────────────────────────────────────────────────────
# Stored in .asc_credentials (git-ignored):
#   ASC_KEY_ID=XXXXXXXXXX
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   ASC_KEY_PATH=/Users/jojo/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8

load_asc_credentials() {
  if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    fail "No .asc_credentials file found. Run: ./scripts/setup-asc.sh"
  fi
  # shellcheck source=/dev/null
  source "$CREDENTIALS_FILE"
  if [[ -z "${ASC_KEY_ID:-}" ]];    then fail "ASC_KEY_ID missing in .asc_credentials"; fi
  if [[ -z "${ASC_ISSUER_ID:-}" ]]; then fail "ASC_ISSUER_ID missing in .asc_credentials"; fi
  if [[ -z "${ASC_KEY_PATH:-}" ]];  then fail "ASC_KEY_PATH missing in .asc_credentials"; fi
  if [[ ! -f "$ASC_KEY_PATH" ]];    then fail "p8 key not found at $ASC_KEY_PATH"; fi
}

# ── Android ──────────────────────────────────────────────────────────────────

release_android() {
  local version="$1" build="$2"

  log "Building Android APK v${version}+${build}…"
  (cd "$MOBILE" && flutter build apk --release \
    --target-platform android-arm64 \
    --split-per-abi)

  local apk_src="$MOBILE/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
  local apk_name="JojoMusique-v${version}-android.apk"
  local apk_dst="$LANDING/downloads/$apk_name"

  cp "$apk_src" "$apk_dst"
  local sha256
  sha256=$(shasum -a 256 "$apk_dst" | cut -d' ' -f1)
  ok "APK → $apk_name (sha256: ${sha256:0:16}…)"

  # Update metadata.json
  local today
  today=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local meta="$LANDING/metadata.json"
  # Use python for reliable JSON editing
  python3 - "$meta" "$version" "$build" "$apk_name" "$sha256" "$today" <<'PY'
import json, sys
path, ver, build, apk, sha, date = sys.argv[1:]
with open(path) as f: d = json.load(f)
d["app"]["version"] = ver
d["app"]["build"] = int(build)
d["app"]["releaseDate"] = date
d["builds"]["android"]["url"] = f"/downloads/{apk}"
d["builds"]["android"]["sha256"] = sha
d["builds"]["android"]["releaseDate"] = date[:10]
with open(path, "w") as f: json.dump(d, f, indent=2, ensure_ascii=False)
print(f"  metadata.json updated")
PY

  # Update index.html (replace any previous version pattern)
  sed -i '' \
    -E "s|JojoMusique-v[0-9]+\.[0-9]+\.[0-9]+-android\.apk|${apk_name}|g" \
    "$LANDING/index.html"
  sed -i '' \
    -E "s|v[0-9]+\.[0-9]+\.[0-9]+|v${version}|g" \
    "$LANDING/index.html"

  log "Deploying landing page…"
  (cd "$LANDING" && vercel --prod --yes 2>&1 | grep -E "Aliased:|error" || true)
  ok "Landing deployed → https://jojomusique-zeta.vercel.app"
}

# ── Web ───────────────────────────────────────────────────────────────────────

release_web() {
  log "Building Flutter web…"
  (cd "$MOBILE" && flutter build web --release --base-href /)

  log "Deploying web…"
  (cd "$MOBILE/build/web" && vercel --prod --yes 2>&1 | grep -E "Aliased:|Production:|error" || true)
  ok "Web deployed"
}

# ── iOS ───────────────────────────────────────────────────────────────────────

release_ios() {
  load_asc_credentials

  log "Building iOS IPA…"
  (cd "$MOBILE" && flutter build ipa --release)

  local ipa
  ipa=$(find "$MOBILE/build/ios/ipa" -name "*.ipa" | head -1)
  [[ -z "$ipa" ]] && fail "IPA not found after build"
  ok "IPA built → $ipa"

  log "Uploading to App Store Connect…"
  xcrun altool --upload-app \
    --type ios \
    --file "$ipa" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    --apiPrivateKey "$ASC_KEY_PATH" \
    2>&1

  ok "Uploaded to App Store Connect ✓"
}

# ── Main ──────────────────────────────────────────────────────────────────────

TARGET="${1:-all}"

# Bump version once for this release
VERSION=$(current_version)
BUILD=$(current_build)
NEW_VERSION=$(next_patch "$VERSION")
NEW_BUILD=$((BUILD + 1))

log "Release: v${VERSION}+${BUILD} → v${NEW_VERSION}+${NEW_BUILD}"
bump_version "$NEW_VERSION" "$NEW_BUILD"

case "$TARGET" in
  android) release_android "$NEW_VERSION" "$NEW_BUILD" ;;
  web)     release_web ;;
  ios)     release_ios ;;
  all)
    release_android "$NEW_VERSION" "$NEW_BUILD"
    release_web
    release_ios
    ;;
  *) fail "Unknown target: $TARGET. Use: android | web | ios | all" ;;
esac

ok "Release v${NEW_VERSION}+${NEW_BUILD} done."
