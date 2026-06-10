#!/usr/bin/env bash
# One-time setup for App Store Connect API credentials
# Run once, then ./scripts/release.sh ios will work automatically.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CREDENTIALS_FILE="$ROOT/.asc_credentials"
KEYS_DIR="$HOME/.appstoreconnect/private_keys"

echo "═══════════════════════════════════════════════════"
echo "  App Store Connect API — one-time credential setup"
echo "═══════════════════════════════════════════════════"
echo ""

# ── Step 1: p8 key file ───────────────────────────────────────────────────────

echo "Step 1/3 — API Key file (.p8)"
echo ""
echo "  In App Store Connect → Users and Access → Integrations → App Store Connect API"
echo "  Create (or reuse) a key with 'App Manager' role, then download AuthKey_XXXXXX.p8"
echo ""
echo "  The key will be placed in: $KEYS_DIR"
echo ""

mkdir -p "$KEYS_DIR"

# Check if a key already exists there
existing_keys=( "$KEYS_DIR"/AuthKey_*.p8 )
if [[ -f "${existing_keys[0]:-}" ]]; then
  echo "  Found existing key(s):"
  for k in "${existing_keys[@]}"; do
    echo "    $k"
  done
  echo ""
  read -r -p "  Use an existing key above? (y/n): " USE_EXISTING
  if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
    if [[ ${#existing_keys[@]} -eq 1 ]]; then
      P8_PATH="${existing_keys[0]}"
    else
      read -r -p "  Enter full path to the .p8 file: " P8_PATH
    fi
  else
    read -r -p "  Drag-and-drop your .p8 file here (or type full path): " P8_INPUT
    P8_INPUT="${P8_INPUT//\\ / }"   # de-escape spaces from drag-and-drop
    P8_INPUT="${P8_INPUT/#\~/$HOME}"
    if [[ ! -f "$P8_INPUT" ]]; then
      echo "  ✗ File not found: $P8_INPUT" >&2; exit 1
    fi
    P8_FILENAME="$(basename "$P8_INPUT")"
    cp "$P8_INPUT" "$KEYS_DIR/$P8_FILENAME"
    P8_PATH="$KEYS_DIR/$P8_FILENAME"
    echo "  ✓ Copied → $P8_PATH"
  fi
else
  read -r -p "  Drag-and-drop your .p8 file here (or type full path): " P8_INPUT
  P8_INPUT="${P8_INPUT//\\ / }"
  P8_INPUT="${P8_INPUT/#\~/$HOME}"
  if [[ ! -f "$P8_INPUT" ]]; then
    echo "  ✗ File not found: $P8_INPUT" >&2; exit 1
  fi
  P8_FILENAME="$(basename "$P8_INPUT")"
  cp "$P8_INPUT" "$KEYS_DIR/$P8_FILENAME"
  P8_PATH="$KEYS_DIR/$P8_FILENAME"
  echo "  ✓ Copied → $P8_PATH"
fi
echo ""

# ── Step 2: Key ID ────────────────────────────────────────────────────────────

echo "Step 2/3 — Key ID"
echo ""
echo "  The Key ID is the 10-character alphanumeric code shown next to the key"
echo "  in App Store Connect, and also embedded in the filename: AuthKey_<KEY_ID>.p8"
echo ""

# Try to extract from filename
FILENAME_KEY_ID="$(basename "$P8_PATH" .p8 | sed 's/AuthKey_//')"
if [[ "$FILENAME_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  read -r -p "  Key ID [$FILENAME_KEY_ID]: " INPUT_KEY_ID
  ASC_KEY_ID="${INPUT_KEY_ID:-$FILENAME_KEY_ID}"
else
  read -r -p "  Key ID: " ASC_KEY_ID
fi

if [[ -z "$ASC_KEY_ID" ]]; then
  echo "  ✗ Key ID cannot be empty" >&2; exit 1
fi
echo "  ✓ Key ID: $ASC_KEY_ID"
echo ""

# ── Step 3: Issuer ID ─────────────────────────────────────────────────────────

echo "Step 3/3 — Issuer ID"
echo ""
echo "  The Issuer ID is a UUID shown at the top of the"
echo "  App Store Connect API page (same page as the keys)."
echo "  Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
echo ""
read -r -p "  Issuer ID: " ASC_ISSUER_ID

if [[ -z "$ASC_ISSUER_ID" ]]; then
  echo "  ✗ Issuer ID cannot be empty" >&2; exit 1
fi
echo "  ✓ Issuer ID: $ASC_ISSUER_ID"
echo ""

# ── Write .asc_credentials ────────────────────────────────────────────────────

cat > "$CREDENTIALS_FILE" <<EOF
ASC_KEY_ID=$ASC_KEY_ID
ASC_ISSUER_ID=$ASC_ISSUER_ID
ASC_KEY_PATH=$P8_PATH
EOF

chmod 600 "$CREDENTIALS_FILE"
echo "  ✓ Written → $CREDENTIALS_FILE (mode 600)"

# ── Ensure .gitignore ─────────────────────────────────────────────────────────

GITIGNORE="$ROOT/.gitignore"
if ! grep -qF '.asc_credentials' "$GITIGNORE" 2>/dev/null; then
  echo "" >> "$GITIGNORE"
  echo "# App Store Connect API credentials (never commit)" >> "$GITIGNORE"
  echo ".asc_credentials" >> "$GITIGNORE"
  echo "  ✓ Added .asc_credentials to .gitignore"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Setup complete. You can now run:"
echo "    ./scripts/release.sh ios"
echo "    ./scripts/release.sh all"
echo "═══════════════════════════════════════════════════"
