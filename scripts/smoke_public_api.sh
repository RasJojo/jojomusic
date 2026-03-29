#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-https://jojomusicapi.jojoserv.com}"
EMAIL="${2:-jojo@example.com}"
PASSWORD="${3:-jojotest}"

echo "== health =="
curl -fsS "$BASE_URL/health" | jq .

echo "== login =="
TOKEN=$(
  curl -fsS -X POST "$BASE_URL/api/v1/auth/login" \
    -H 'content-type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
    | jq -r '.access_token'
)
test -n "$TOKEN" && test "$TOKEN" != "null"
echo "token_ok"

echo "== me =="
curl -fsS "$BASE_URL/api/v1/auth/me" \
  -H "authorization: Bearer $TOKEN" \
  | jq '{id,name,email}'

echo "== search =="
TIMEFORMAT=$'%3R'
time curl -fsS "$BASE_URL/api/v1/search?query=gangstabab" \
  | jq '{artists:(.artists|length),tracks:(.tracks|length),albums:(.albums|length),podcasts:(.podcasts|length)}'

echo "== resolve =="
curl -fsS -X POST "$BASE_URL/api/v1/tracks/resolve" \
  -H 'content-type: application/json' \
  -d '{"artist":"Daft Punk","title":"One More Time"}' \
  | jq '{source,has_stream:(.stream_url|startswith("http")),duration_ms}'

echo "== likes/playlists/home =="
curl -fsS "$BASE_URL/api/v1/me/likes" \
  -H "authorization: Bearer $TOKEN" \
  | jq 'length'
curl -fsS "$BASE_URL/api/v1/playlists" \
  -H "authorization: Bearer $TOKEN" \
  | jq 'length'
curl -fsS "$BASE_URL/api/v1/me/home" \
  -H "authorization: Bearer $TOKEN" \
  | jq '{recommendations:(.recommendations|length),recently_played:(.recently_played|length),generated_playlists:(.generated_playlists|length),browse_categories:(.browse_categories|length),featured_podcasts:(.featured_podcasts|length)}'
