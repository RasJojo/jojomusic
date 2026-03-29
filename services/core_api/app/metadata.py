from __future__ import annotations

import asyncio
import re
import unicodedata
from collections import OrderedDict
from datetime import datetime
from difflib import SequenceMatcher
from email.utils import parsedate_to_datetime
from html import unescape
from urllib.parse import quote, unquote, urljoin, urlparse
import xml.etree.ElementTree as ET

import httpx

try:
    import lyricsgenius
except ImportError:  # pragma: no cover
    lyricsgenius = None

from app.config import settings
from app.schemas import (
    AlbumPayload,
    ArtistPayload,
    LyricsResponse,
    PodcastEpisodePayload,
    PodcastPayload,
    TrackPayload,
)


def normalize_value(value: str) -> str:
    normalized = value.lower().strip()
    normalized = re.sub(r"[^a-z0-9]+", "-", normalized)
    return normalized.strip("-")


def build_track_key(artist: str, title: str) -> str:
    return normalize_value(f"{artist}-{title}")


def build_artist_key(name: str) -> str:
    return normalize_value(name)


def build_album_key(artist: str, title: str) -> str:
    return normalize_value(f"{artist}-{title}")


def upscale_artwork(url: str | None) -> str | None:
    if not url:
        return None
    return re.sub(r"/\d+x\d+bb\.jpg", "/1200x1200bb.jpg", url)


def choose_lastfm_image(images: list[dict] | None) -> str | None:
    if not images:
        return None

    for preferred in ("mega", "extralarge", "large", "medium", "small"):
        for image in images:
            if image.get("size") == preferred and image.get("#text"):
                url = image["#text"]
                if not _is_placeholder_image(url):
                    return url

    for image in images:
        if image.get("#text"):
            url = image["#text"]
            if not _is_placeholder_image(url):
                return url
    return None


def strip_lastfm_summary(summary: str | None) -> str | None:
    if not summary:
        return None
    text = re.sub(r"<[^>]+>", "", unescape(summary)).strip()
    text = re.sub(
        r"(?:Read more on Last\.fm\.?|User-contributed text is available under the Creative Commons By-SA License; additional terms may apply\.)\s*$",
        "",
        text,
        flags=re.IGNORECASE,
    ).strip()
    return text or None


def strip_description(value: str | None) -> str | None:
    if not value:
        return None
    text = re.sub(r"<[^>]+>", "", unescape(value)).strip()
    return text or None


def parse_partial_date(value: str | None) -> datetime | None:
    if not value:
        return None
    for pattern in ("%Y-%m-%d", "%Y-%m", "%Y"):
        try:
            return datetime.strptime(value, pattern)
        except ValueError:
            continue
    return None


def _is_placeholder_image(url: str | None) -> bool:
    if not url:
        return True
    return "2a96cbd8b46e442fc41c2b86b821562f" in url


def _ensure_list(value: list | dict | None) -> list[dict]:
    if value is None:
        return []
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, dict):
        return [value]
    return []


def normalize_lyrics_value(value: str) -> str:
    normalized = unescape(value).lower().strip()
    normalized = (
        unicodedata.normalize("NFKD", normalized)
        .encode("ascii", "ignore")
        .decode("ascii")
    )
    normalized = re.sub(r"\(feat[^)]*\)", "", normalized, flags=re.IGNORECASE)
    normalized = re.sub(r"\b(?:feat\.?|ft\.?|featuring|avec)\b.*$", "", normalized, flags=re.IGNORECASE)
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized)
    return normalized.strip()


def lyrics_query_variants(artist: str, title: str) -> list[tuple[str, str]]:
    artists = _dedupe_non_empty(
        [
            artist,
            *re.split(r"\s*(?:,|&| x | feat\.?| ft\.?| featuring )\s*", artist, flags=re.IGNORECASE),
        ]
    )
    titles = _dedupe_non_empty(
        [
            title,
            re.sub(r"\s*\([^)]*\)", "", title).strip(),
            re.sub(r"\s*-\s*(?:live|remix|edit|version).*$", "", title, flags=re.IGNORECASE).strip(),
            re.sub(r"\s*(?:feat\.?|ft\.?|featuring)\s+.*$", "", title, flags=re.IGNORECASE).strip(),
        ]
    )
    variants: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for artist_variant in artists:
        for title_variant in titles:
            key = (
                normalize_lyrics_value(artist_variant),
                normalize_lyrics_value(title_variant),
            )
            if not key[0] or not key[1] or key in seen:
                continue
            seen.add(key)
            variants.append((artist_variant.strip(), title_variant.strip()))
    return variants or [(artist, title)]


def sanitize_genius_lyrics(value: str | None) -> str | None:
    if not value:
        return None
    text = value.replace("\r", "").strip()
    text = re.sub(r"^\s*\d+\s+Contributors.*?Lyrics", "", text, count=1, flags=re.DOTALL)
    text = re.sub(r"^\s*.*?Lyrics", "", text, count=1, flags=re.DOTALL)
    text = re.sub(r"You might also like", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\d*Embed\s*$", "", text).strip()
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text or None


def sanitize_tononkira_lyrics(value: str | None) -> str | None:
    if not value:
        return None
    lines = [line.rstrip() for line in value.replace("\r", "").splitlines()]
    if len(lines) >= 2 and re.fullmatch(r"-{4,}", lines[1].strip() or ""):
        lines = lines[2:]
    text = "\n".join(lines).strip()
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text or None


def html_to_text_with_breaks(value: str) -> str:
    text = re.sub(r"<br\s*/?>", "\n", value, flags=re.IGNORECASE)
    text = re.sub(r"</p\s*>", "\n\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    return unescape(text)


def tononkira_slug(value: str) -> str:
    normalized = unescape(value).lower().strip()
    normalized = re.sub(r"\(feat[^)]*\)", "", normalized, flags=re.IGNORECASE)
    normalized = re.sub(r"\b(?:feat\.?|ft\.?|featuring|avec)\b.*$", "", normalized, flags=re.IGNORECASE)
    ascii_value = (
        unicodedata.normalize("NFKD", normalized)
        .encode("ascii", "ignore")
        .decode("ascii")
    )
    ascii_value = re.sub(r"[^a-z0-9]+", "-", ascii_value)
    return ascii_value.strip("-")


def _dedupe_non_empty(values: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for value in values:
        normalized = value.strip()
        if not normalized:
            continue
        key = normalize_lyrics_value(normalized)
        if not key or key in seen:
            continue
        seen.add(key)
        deduped.append(normalized)
    return deduped


def _lyrics_similarity(left: str, right: str) -> int:
    return int(SequenceMatcher(None, normalize_lyrics_value(left), normalize_lyrics_value(right)).ratio() * 1000)


class ITunesProvider:
    base_url = "https://itunes.apple.com"

    async def search(self, query: str, limit: int = 25) -> list[TrackPayload]:
        return await self.search_tracks(query, limit=limit)

    async def search_tracks(self, query: str, limit: int = 25) -> list[TrackPayload]:
        data = await self._search({"term": query, "entity": "song", "limit": limit})
        tracks: "OrderedDict[str, TrackPayload]" = OrderedDict()
        for item in data.get("results", []):
            artist = item.get("artistName")
            title = item.get("trackName")
            if not artist or not title:
                continue
            track_key = build_track_key(artist, title)
            if track_key in tracks:
                continue
            tracks[track_key] = TrackPayload(
                track_key=track_key,
                title=title,
                artist=artist,
                album=item.get("collectionName"),
                artwork_url=upscale_artwork(item.get("artworkUrl100")),
                duration_ms=item.get("trackTimeMillis"),
                provider="itunes",
                external_id=str(item.get("trackId")) if item.get("trackId") else None,
                preview_url=item.get("previewUrl"),
            )
        return list(tracks.values())

    async def search_artists(self, query: str, limit: int = 10) -> list[ArtistPayload]:
        data = await self._search(
            {
                "term": query,
                "entity": "musicArtist",
                "attribute": "artistTerm",
                "limit": limit,
            }
        )
        artists: "OrderedDict[str, ArtistPayload]" = OrderedDict()
        for item in data.get("results", []):
            name = item.get("artistName")
            if not name:
                continue
            artist_key = build_artist_key(name)
            if artist_key in artists:
                continue
            artists[artist_key] = ArtistPayload(
                artist_key=artist_key,
                name=name,
                provider="itunes",
                external_id=str(item.get("artistId")) if item.get("artistId") else None,
                url=item.get("artistLinkUrl"),
            )
        return list(artists.values())

    async def search_albums(self, query: str, limit: int = 10) -> list[AlbumPayload]:
        data = await self._search({"term": query, "entity": "album", "limit": limit})
        albums: "OrderedDict[str, AlbumPayload]" = OrderedDict()
        for item in data.get("results", []):
            artist = item.get("artistName")
            title = item.get("collectionName")
            if not artist or not title:
                continue
            album_key = build_album_key(artist, title)
            if album_key in albums:
                continue
            albums[album_key] = AlbumPayload(
                album_key=album_key,
                title=title,
                artist=artist,
                artwork_url=upscale_artwork(item.get("artworkUrl100")),
                provider="itunes",
                external_id=str(item.get("collectionId")) if item.get("collectionId") else None,
                release_date=self._parse_datetime(item.get("releaseDate")),
                track_count=item.get("trackCount"),
            )
        return list(albums.values())

    async def search_podcasts(self, query: str, limit: int = 10) -> list[PodcastPayload]:
        data = await self._search({"term": query, "entity": "podcast", "limit": limit})
        podcasts: "OrderedDict[str, PodcastPayload]" = OrderedDict()
        for item in data.get("results", []):
            if item.get("kind") != "podcast":
                continue
            podcast_id = item.get("collectionId") or item.get("trackId")
            title = item.get("collectionName") or item.get("trackName")
            publisher = item.get("artistName")
            if not podcast_id or not title or not publisher:
                continue
            podcast_key = str(podcast_id)
            if podcast_key in podcasts:
                continue
            podcasts[podcast_key] = PodcastPayload(
                podcast_key=podcast_key,
                title=title,
                publisher=publisher,
                description=strip_description(item.get("description")),
                artwork_url=upscale_artwork(item.get("artworkUrl600") or item.get("artworkUrl100")),
                feed_url=item.get("feedUrl"),
                external_url=item.get("collectionViewUrl") or item.get("trackViewUrl"),
                episode_count=item.get("trackCount"),
                release_date=self._parse_datetime(item.get("releaseDate")),
            )
        return list(podcasts.values())

    async def podcast_episodes(self, podcast: PodcastPayload, limit: int = 12) -> list[PodcastEpisodePayload]:
        if not podcast.feed_url:
            return []

        try:
            async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
                response = await client.get(podcast.feed_url)
                response.raise_for_status()
                root = ET.fromstring(response.text)
        except Exception:
            return []

        channel = root.find("channel")
        if channel is None:
            return []

        episodes: list[PodcastEpisodePayload] = []
        for item in channel.findall("item")[:limit]:
            enclosure = item.find("enclosure")
            image_href = None
            duration_seconds = None
            description = strip_description(item.findtext("description"))
            for child in item:
                if child.tag.endswith("image"):
                    image_href = child.attrib.get("href") or image_href
                elif child.tag.endswith("duration") and child.text:
                    duration_seconds = self._parse_duration(child.text)
                elif child.tag.endswith("summary") and not description:
                    description = strip_description(child.text)

            title = item.findtext("title")
            audio_url = enclosure.attrib.get("url") if enclosure is not None else None
            if not title or not audio_url:
                continue
            guid = item.findtext("guid") or audio_url
            episodes.append(
                PodcastEpisodePayload(
                    episode_key=guid,
                    podcast_title=podcast.title,
                    title=title,
                    publisher=podcast.publisher,
                    description=description,
                    artwork_url=image_href or podcast.artwork_url,
                    audio_url=audio_url,
                    external_url=item.findtext("link") or podcast.external_url,
                    duration_seconds=duration_seconds,
                    published_at=self._parse_datetime(item.findtext("pubDate")),
                )
            )
        return episodes

    async def lookup_podcast(self, podcast_key: str) -> PodcastPayload | None:
        data = await self._lookup({"id": podcast_key, "entity": "podcast"})
        for item in data.get("results", []):
            if item.get("kind") != "podcast":
                continue
            podcast_id = item.get("collectionId") or item.get("trackId")
            title = item.get("collectionName") or item.get("trackName")
            publisher = item.get("artistName")
            if not podcast_id or not title or not publisher:
                continue
            return PodcastPayload(
                podcast_key=str(podcast_id),
                title=title,
                publisher=publisher,
                description=strip_description(item.get("description")),
                artwork_url=upscale_artwork(item.get("artworkUrl600") or item.get("artworkUrl100")),
                feed_url=item.get("feedUrl"),
                external_url=item.get("collectionViewUrl") or item.get("trackViewUrl"),
                episode_count=item.get("trackCount"),
                release_date=self._parse_datetime(item.get("releaseDate")),
            )
        return None

    async def album_details(
        self,
        *,
        artist: str,
        title: str,
        external_id: str | None = None,
    ) -> tuple[AlbumPayload | None, list[TrackPayload]]:
        album: AlbumPayload | None = None
        tracks: list[TrackPayload] = []

        if external_id:
            data = await self._lookup({"id": external_id, "entity": "song"})
            album, tracks = self._parse_album_lookup(data)

        if album is None:
            candidates = await self.search_albums(f"{artist} {title}", limit=8)
            album = next(
                (
                    item
                    for item in candidates
                    if normalize_value(item.artist) == normalize_value(artist)
                    and normalize_value(item.title) == normalize_value(title)
                ),
                None,
            )
            if album is not None and album.external_id:
                data = await self._lookup({"id": album.external_id, "entity": "song"})
                parsed_album, parsed_tracks = self._parse_album_lookup(data)
                album = parsed_album or album
                tracks = parsed_tracks

        if album is None:
            return None, []

        if not tracks:
            candidates = await self.search_tracks(f"{artist} {title}", limit=40)
            tracks = [
                track
                for track in candidates
                if normalize_value(track.artist) == normalize_value(album.artist)
                and normalize_value(track.album or "") == normalize_value(album.title)
            ]
        return album, tracks[:20]

    async def top_for_artist(self, artist: str, limit: int = 10) -> list[TrackPayload]:
        tracks = await self.search_tracks(artist, limit=limit * 3)
        exact_matches = [
            track
            for track in tracks
            if normalize_value(track.artist) == normalize_value(artist)
        ]
        return exact_matches[:limit]

    async def albums_for_artist(self, artist: str, limit: int = 10) -> list[AlbumPayload]:
        albums = await self.search_albums(artist, limit=limit * 3)
        exact_matches = [
            album
            for album in albums
            if normalize_value(album.artist) == normalize_value(artist)
        ]
        exact_matches.sort(
            key=lambda album: album.release_date or datetime.min,
            reverse=True,
        )
        return exact_matches[:limit]

    async def lyrics(self, artist: str, title: str) -> LyricsResponse | None:
        genius = await self._lyrics_from_genius(artist=artist, title=title)
        if genius is not None:
            return genius

        tononkira = await self._lyrics_from_tononkira(artist=artist, title=title)
        if tononkira is not None:
            return tononkira

        return await self._lyrics_from_lrclib(artist=artist, title=title)

    async def _lyrics_from_genius(
        self,
        *,
        artist: str,
        title: str,
    ) -> LyricsResponse | None:
        if not settings.genius_access_token or lyricsgenius is None:
            return None

        def lookup() -> LyricsResponse | None:
            client = lyricsgenius.Genius(
                settings.genius_access_token,
                timeout=12,
                retries=1,
                sleep_time=0.1,
                remove_section_headers=True,
                skip_non_songs=True,
                excluded_terms=["(Remix)", "(Live)"],
                verbose=False,
            )
            for artist_variant, title_variant in lyrics_query_variants(artist, title):
                try:
                    song = client.search_song(title_variant, artist_variant)
                except Exception:
                    continue
                if song is None:
                    continue
                song_title = getattr(song, "title", "") or title_variant
                song_artist = getattr(song, "artist", "") or artist_variant
                title_score = _lyrics_similarity(title_variant, song_title)
                artist_score = _lyrics_similarity(artist_variant, song_artist)
                normalized_candidate_artist = normalize_lyrics_value(song_artist)
                normalized_requested_artist = normalize_lyrics_value(artist_variant)
                artist_contains = (
                    normalized_requested_artist in normalized_candidate_artist
                    or normalized_candidate_artist in normalized_requested_artist
                )
                if title_score < 850:
                    continue
                if artist_score < 700 and not artist_contains:
                    continue
                lyrics = sanitize_genius_lyrics(song.lyrics)
                if not lyrics:
                    continue
                return LyricsResponse(
                    artist=artist,
                    title=title,
                    plain_lyrics=lyrics,
                    synced_lyrics=None,
                    provider="genius",
                )
            return None

        try:
            return await asyncio.to_thread(lookup)
        except Exception:
            return None

    async def _lyrics_from_tononkira(
        self,
        *,
        artist: str,
        title: str,
    ) -> LyricsResponse | None:
        try:
            async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
                best_payload: tuple[tuple[int, int, int], LyricsResponse] | None = None

                for url in self._tononkira_candidate_urls(artist=artist, title=title):
                    response = await client.get(url)
                    if response.status_code >= 400:
                        continue
                    payload = self._tononkira_payload_from_html(
                        html=response.text,
                        artist=artist,
                        title=title,
                    )
                    if payload is None:
                        continue
                    if best_payload is None or payload[0] > best_payload[0]:
                        best_payload = payload
                    if payload[0][0] == 1 and payload[0][1] >= 950 and payload[0][2] >= 950:
                        return payload[1]

                song_urls: list[str] = []
                seen_urls: set[str] = set()
                for artist_variant, title_variant in lyrics_query_variants(artist, title):
                    search_params = [
                        {"lohateny": title_variant, "mpihira": artist_variant},
                        {"lohateny": title_variant},
                        {"lohateny": f"{title_variant} {artist_variant}"},
                        {"lohateny": f"{artist_variant} {title_variant}"},
                        {"mpihira": artist_variant},
                    ]
                    for params in search_params:
                        normalized_params = {
                            key: value.strip()
                            for key, value in params.items()
                            if value.strip()
                        }
                        if not normalized_params:
                            continue
                        response = await client.get(
                            "https://tononkira.serasera.org/tononkira",
                            params=normalized_params,
                        )
                        if response.status_code >= 400:
                            continue
                        for url in re.findall(
                            r'href=["\'](?P<url>(?:https://tononkira\.serasera\.org)?/(?:mg/)?hira/[^"\'<\s?#]+)',
                            response.text,
                            flags=re.IGNORECASE,
                        ):
                            cleaned = urljoin(
                                "https://tononkira.serasera.org",
                                unquote(url),
                            )
                            if cleaned in seen_urls:
                                continue
                            seen_urls.add(cleaned)
                            song_urls.append(cleaned)
                if not song_urls:
                    queries = _dedupe_non_empty(
                        [
                            title,
                            f"{title} {artist}",
                            f"{artist} {title}",
                            f"{artist} - {title}",
                            artist,
                        ]
                    )
                    for query in queries:
                        response = await client.get(
                            "https://tononkira.serasera.org/tononkira",
                            params={"lohateny": query},
                        )
                        if response.status_code >= 400:
                            continue
                        for url in re.findall(
                            r'href=["\'](?P<url>(?:https://tononkira\.serasera\.org)?/(?:mg/)?hira/[^"\'<\s?#]+)',
                            response.text,
                            flags=re.IGNORECASE,
                        ):
                            cleaned = urljoin(
                                "https://tononkira.serasera.org",
                                unquote(url),
                            )
                            if cleaned in seen_urls:
                                continue
                            seen_urls.add(cleaned)
                            song_urls.append(cleaned)
                if not song_urls:
                    return best_payload[1] if best_payload is not None else None

                for url in song_urls[:12]:
                    response = await client.get(url)
                    if response.status_code >= 400:
                        continue
                    payload = self._tononkira_payload_from_html(
                        html=response.text,
                        artist=artist,
                        title=title,
                    )
                    if payload is None:
                        continue
                    if best_payload is None or payload[0] > best_payload[0]:
                        best_payload = payload

                return best_payload[1] if best_payload is not None else None
        except Exception:
            return None

    def _tononkira_candidate_urls(self, *, artist: str, title: str) -> list[str]:
        urls: list[str] = []
        seen: set[str] = set()
        base_paths = (
            "https://tononkira.serasera.org/hira",
            "https://tononkira.serasera.org/mg/hira",
        )

        for artist_variant, title_variant in lyrics_query_variants(artist, title):
            artist_slug = tononkira_slug(artist_variant)
            title_slug = tononkira_slug(title_variant)
            if not artist_slug or not title_slug:
                continue

            artist_slugs = [artist_slug]
            title_slugs = [title_slug]
            if not re.search(r"-\d+$", artist_slug):
                artist_slugs.append(f"{artist_slug}-1")
            if not re.search(r"-\d+$", title_slug):
                title_slugs.append(f"{title_slug}-1")

            for base_path in base_paths:
                for artist_slug_variant in artist_slugs:
                    for title_slug_variant in title_slugs:
                        url = f"{base_path}/{artist_slug_variant}/{title_slug_variant}"
                        if url in seen:
                            continue
                        seen.add(url)
                        urls.append(url)

        return urls

    def _tononkira_payload_from_html(
        self,
        *,
        html: str,
        artist: str,
        title: str,
    ) -> tuple[tuple[int, int, int], LyricsResponse] | None:
        title_tag = re.search(r"<title>\s*(.+?)\s*</title>", html, flags=re.IGNORECASE | re.DOTALL)
        if title_tag and "Lisitry ny hira" in unescape(title_tag.group(1)):
            return None

        title_match = re.search(
            r'property="og:title"\s+content="(.+?)\s*-\s*(.+?)\s*-\s*Tononkira',
            html,
            flags=re.IGNORECASE | re.DOTALL,
        )
        candidate_title = title
        candidate_artist = artist
        if title_match:
            candidate_title = unescape(title_match.group(1)).strip()
            candidate_artist = unescape(title_match.group(2)).strip()

        lyrics_match = re.search(
            r"\(Nalaina tao amin'ny tononkira\.serasera\.org\)\s*</div>\s*(?P<lyrics>.*?)\s*<br\s*/?>\s*--------\s*<br\s*/?>",
            html,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if not lyrics_match:
            return None

        lyrics = sanitize_tononkira_lyrics(
            html_to_text_with_breaks(lyrics_match.group("lyrics"))
        )
        if not lyrics:
            return None

        normalized_artist = normalize_lyrics_value(artist)
        normalized_title = normalize_lyrics_value(title)
        title_score = _lyrics_similarity(normalized_title, candidate_title)
        artist_score = _lyrics_similarity(normalized_artist, candidate_artist)
        exact_bonus = int(
            normalize_lyrics_value(candidate_title) == normalized_title
            and normalize_lyrics_value(candidate_artist) == normalized_artist
        )
        if title_score < 580 and artist_score < 580:
            return None

        return (
            (exact_bonus, title_score, artist_score),
            LyricsResponse(
                artist=artist,
                title=title,
                plain_lyrics=lyrics,
                synced_lyrics=None,
                provider="tononkira",
            ),
        )

    async def _lyrics_from_lrclib(
        self,
        *,
        artist: str,
        title: str,
    ) -> LyricsResponse | None:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(
                    f"{settings.lrclib_base_url}/api/search",
                    params={"artist_name": artist, "track_name": title},
                )
                if response.status_code >= 400:
                    return None
                items = response.json()
        except Exception:
            return None

        if not items:
            return None

        first = items[0]
        return LyricsResponse(
            artist=artist,
            title=title,
            plain_lyrics=first.get("plainLyrics"),
            synced_lyrics=first.get("syncedLyrics"),
            provider="lrclib",
        )

    async def _search(self, params: dict[str, str | int]) -> dict:
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                response = await client.get(f"{self.base_url}/search", params=params)
                response.raise_for_status()
                return response.json()
        except Exception:
            return {"results": []}

    async def _lookup(self, params: dict[str, str | int]) -> dict:
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                response = await client.get(f"{self.base_url}/lookup", params=params)
                response.raise_for_status()
                return response.json()
        except Exception:
            return {"results": []}

    def _parse_album_lookup(self, data: dict) -> tuple[AlbumPayload | None, list[TrackPayload]]:
        album: AlbumPayload | None = None
        tracks: list[TrackPayload] = []

        for item in data.get("results", []):
            wrapper_type = item.get("wrapperType")
            kind = item.get("kind")
            if album is None and (
                wrapper_type == "collection"
                or item.get("collectionType") == "Album"
            ):
                artist = item.get("artistName")
                title = item.get("collectionName")
                if artist and title:
                    album = AlbumPayload(
                        album_key=build_album_key(artist, title),
                        title=title,
                        artist=artist,
                        artwork_url=upscale_artwork(
                            item.get("artworkUrl100") or item.get("artworkUrl60")
                        ),
                        provider="itunes",
                        external_id=str(item.get("collectionId"))
                        if item.get("collectionId")
                        else None,
                        release_date=self._parse_datetime(item.get("releaseDate")),
                        track_count=item.get("trackCount"),
                    )
            if wrapper_type == "track" or kind == "song":
                artist = item.get("artistName")
                title = item.get("trackName")
                album_title = item.get("collectionName")
                if not artist or not title:
                    continue
                tracks.append(
                    TrackPayload(
                        track_key=build_track_key(artist, title),
                        title=title,
                        artist=artist,
                        album=album_title,
                        artwork_url=upscale_artwork(
                            item.get("artworkUrl100") or item.get("artworkUrl60")
                        ),
                        duration_ms=item.get("trackTimeMillis"),
                        provider="itunes",
                        external_id=str(item.get("trackId"))
                        if item.get("trackId")
                        else None,
                        preview_url=item.get("previewUrl"),
                    )
                )
        return album, tracks

    def _parse_datetime(self, value: str | None) -> datetime | None:
        if not value:
            return None
        try:
            if "T" in value:
                return datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsedate_to_datetime(value)
        except Exception:
            return None

    def _parse_duration(self, value: str) -> int | None:
        parts = [part for part in value.split(":") if part.isdigit()]
        if not parts:
            return None
        total = 0
        for part in parts:
            total = (total * 60) + int(part)
        return total


class MusicBrainzProvider:
    base_url = "https://musicbrainz.org/ws/2"
    cover_art_base_url = "https://coverartarchive.org"
    wikidata_api_url = "https://www.wikidata.org/w/api.php"
    wikipedia_summary_url = "https://en.wikipedia.org/api/rest_v1/page/summary"

    async def search_artists(self, query: str, limit: int = 10) -> list[ArtistPayload]:
        data = await self._call(
            "/artist",
            {
                "query": f'artist:"{query}"',
                "fmt": "json",
                "limit": limit,
            },
        )
        artists: "OrderedDict[str, ArtistPayload]" = OrderedDict()
        for item in data.get("artists", []):
            name = item.get("name")
            mbid = item.get("id")
            if not name or not mbid:
                continue
            artist_key = build_artist_key(name)
            if artist_key in artists:
                continue
            artists[artist_key] = ArtistPayload(
                artist_key=artist_key,
                name=name,
                provider="musicbrainz",
                external_id=mbid,
                summary=item.get("disambiguation") or None,
            )
        return list(artists.values())

    async def artist_info(self, artist: str) -> ArtistPayload | None:
        candidates = await self.search_artists(artist, limit=5)
        if not candidates:
            return None
        selected = next(
            (item for item in candidates if normalize_value(item.name) == normalize_value(artist)),
            candidates[0],
        )
        if not selected.external_id:
            return selected

        data = await self._call(
            f"/artist/{selected.external_id}",
            {"inc": "url-rels", "fmt": "json"},
        )
        image_url, summary = await self._resolve_wikipedia_enrichment(
            data.get("relations", []),
        )
        return ArtistPayload(
            artist_key=selected.artist_key,
            name=data.get("name") or selected.name,
            image_url=image_url,
            provider="musicbrainz",
            external_id=selected.external_id,
            summary=summary or selected.summary,
        )

    async def search_albums(self, query: str, limit: int = 10) -> list[AlbumPayload]:
        data = await self._call(
            "/release-group",
            {
                "query": query,
                "fmt": "json",
                "limit": limit,
            },
        )
        items = [
            item
            for item in data.get("release-groups", [])
            if item.get("primary-type") in {"Album", "EP", "Single"}
        ][:limit]
        return await self._map_release_groups(items)

    async def albums_for_artist(self, artist: str, limit: int = 10) -> list[AlbumPayload]:
        artist_info = await self.artist_info(artist)
        if artist_info is None or not artist_info.external_id:
            return []

        data = await self._call(
            "/release-group",
            {
                "artist": artist_info.external_id,
                "fmt": "json",
                "limit": max(limit * 2, 12),
            },
        )
        items = [
            item
            for item in data.get("release-groups", [])
            if item.get("primary-type") in {"Album", "EP", "Single"}
        ]
        items.sort(
            key=lambda item: parse_partial_date(item.get("first-release-date"))
            or datetime.min,
            reverse=True,
        )
        return await self._map_release_groups(items[:limit])

    async def album_details(self, artist: str, title: str) -> AlbumPayload | None:
        data = await self._call(
            "/release-group",
            {
                "query": f'artist:"{artist}" AND releasegroup:"{title}"',
                "fmt": "json",
                "limit": 5,
            },
        )
        items = data.get("release-groups", [])
        selected = next(
            (
                item
                for item in items
                if normalize_value(item.get("title", "")) == normalize_value(title)
                and normalize_value(self._artist_name_from_credit(item)) == normalize_value(artist)
            ),
            items[0] if items else None,
        )
        if selected is None:
            return None
        mapped = await self._map_release_groups([selected])
        return mapped[0] if mapped else None

    async def _map_release_groups(self, items: list[dict]) -> list[AlbumPayload]:
        if not items:
            return []

        artworks = await asyncio.gather(
            *[
                self._cover_art_for_release_group(item.get("id"))
                for item in items
            ]
        )
        albums: list[AlbumPayload] = []
        for item, artwork_url in zip(items, artworks, strict=False):
            title = item.get("title")
            mbid = item.get("id")
            artist = self._artist_name_from_credit(item)
            if not title or not artist or not mbid:
                continue
            albums.append(
                AlbumPayload(
                    album_key=build_album_key(artist, title),
                    title=title,
                    artist=artist,
                    artwork_url=artwork_url,
                    provider="musicbrainz",
                    external_id=mbid,
                    release_date=parse_partial_date(item.get("first-release-date")),
                )
            )
        return albums

    def _artist_name_from_credit(self, item: dict) -> str | None:
        credits = item.get("artist-credit") or []
        if not credits:
            return None
        first = credits[0]
        if isinstance(first, dict):
            if isinstance(first.get("artist"), dict):
                return first["artist"].get("name")
            return first.get("name")
        return None

    async def _cover_art_for_release_group(self, release_group_id: str | None) -> str | None:
        if not release_group_id:
            return None
        try:
            async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
                response = await client.get(
                    f"{self.cover_art_base_url}/release-group/{release_group_id}",
                    headers={"User-Agent": settings.musicbrainz_user_agent},
                )
                if response.status_code >= 400:
                    return None
                data = response.json()
        except Exception:
            return None

        for image in data.get("images", []):
            if image.get("front"):
                thumbnails = image.get("thumbnails") or {}
                return (
                    thumbnails.get("1200")
                    or thumbnails.get("large")
                    or thumbnails.get("small")
                    or image.get("image")
                )
        return None

    async def _resolve_wikipedia_enrichment(
        self,
        relations: list[dict],
    ) -> tuple[str | None, str | None]:
        page_title = self._wikipedia_title_from_relations(relations)
        if page_title is None:
            return None, None
        return await self._wikipedia_summary(page_title)

    def _wikipedia_title_from_relations(self, relations: list[dict]) -> str | None:
        wikipedia_url = None
        wikidata_id = None
        for relation in relations:
            resource = relation.get("url", {}).get("resource")
            if not resource:
                continue
            relation_type = relation.get("type")
            if relation_type == "wikipedia":
                wikipedia_url = resource
            elif relation_type == "wikidata":
                wikidata_id = resource.rsplit("/", 1)[-1]

        if wikipedia_url:
            parsed = urlparse(wikipedia_url)
            return unquote(parsed.path.split("/wiki/")[-1]).replace("_", " ")
        if wikidata_id:
            return self._wikidata_title(wikidata_id)
        return None

    def _wikidata_title(self, wikidata_id: str) -> str | None:
        try:
            with httpx.Client(timeout=8.0, follow_redirects=True) as client:
                response = client.get(
                    self.wikidata_api_url,
                    params={
                        "action": "wbgetentities",
                        "ids": wikidata_id,
                        "props": "sitelinks",
                        "format": "json",
                    },
                    headers={"User-Agent": settings.musicbrainz_user_agent},
                )
                response.raise_for_status()
                data = response.json()
        except Exception:
            return None

        entity = (data.get("entities") or {}).get(wikidata_id) or {}
        sitelinks = entity.get("sitelinks") or {}
        if "enwiki" in sitelinks:
            return sitelinks["enwiki"].get("title")
        return None

    async def _wikipedia_summary(self, title: str) -> tuple[str | None, str | None]:
        try:
            async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
                response = await client.get(
                    f"{self.wikipedia_summary_url}/{quote(title)}",
                    headers={"User-Agent": settings.musicbrainz_user_agent},
                )
                if response.status_code >= 400:
                    return None, None
                data = response.json()
        except Exception:
            return None, None

        if data.get("type") == "disambiguation":
            return None, None
        thumbnail = data.get("thumbnail") or {}
        image_url = thumbnail.get("source")
        summary = strip_description(data.get("extract"))
        return image_url, summary

    async def _call(self, path: str, params: dict[str, str | int]) -> dict:
        for attempt in range(3):
            try:
                async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
                    response = await client.get(
                        f"{self.base_url}{path}",
                        params=params,
                        headers={
                            "User-Agent": settings.musicbrainz_user_agent,
                            "Accept": "application/json",
                        },
                    )
                    response.raise_for_status()
                    return response.json()
            except Exception:
                if attempt == 2:
                    return {}
                await asyncio.sleep(0.35 * (attempt + 1))
        return {}


class LastFmProvider:
    base_url = "https://ws.audioscrobbler.com/2.0/"

    @property
    def enabled(self) -> bool:
        return bool(settings.lastfm_api_key)

    async def search_artists(self, query: str, limit: int = 10) -> list[ArtistPayload]:
        if not self.enabled:
            return []

        data = await self._call_api(
            {
                "method": "artist.search",
                "artist": query,
                "limit": limit,
            }
        )
        items = _ensure_list(data.get("results", {}).get("artistmatches", {}).get("artist"))
        artists: "OrderedDict[str, ArtistPayload]" = OrderedDict()
        for item in items:
            name = item.get("name")
            if not name:
                continue
            artist_key = build_artist_key(name)
            if artist_key in artists:
                continue
            listeners = item.get("listeners")
            artists[artist_key] = ArtistPayload(
                artist_key=artist_key,
                name=name,
                image_url=choose_lastfm_image(item.get("image")),
                provider="lastfm",
                external_id=item.get("mbid") or item.get("url"),
                url=item.get("url"),
                listeners=int(listeners) if listeners not in (None, "") else None,
            )
        return list(artists.values())

    async def artist_info(self, artist: str) -> ArtistPayload | None:
        if not self.enabled:
            return None

        data = await self._call_api(
            {
                "method": "artist.getinfo",
                "artist": artist,
            }
        )
        item = data.get("artist")
        if not isinstance(item, dict) or not item.get("name"):
            return None

        stats = item.get("stats") or {}
        return ArtistPayload(
            artist_key=build_artist_key(item["name"]),
            name=item["name"],
            image_url=choose_lastfm_image(item.get("image")),
            provider="lastfm",
            external_id=item.get("mbid") or item.get("url"),
            url=item.get("url"),
            listeners=int(stats["listeners"]) if stats.get("listeners") not in (None, "") else None,
            summary=strip_lastfm_summary(item.get("bio", {}).get("summary")),
        )

    async def similar_tracks(self, artist: str, title: str, limit: int = 10) -> list[TrackPayload]:
        if not self.enabled:
            return []

        data = await self._call_api(
            {
                "method": "track.getsimilar",
                "artist": artist,
                "track": title,
                "limit": limit,
            }
        )
        items = _ensure_list(data.get("similartracks", {}).get("track"))
        return [self._map_track(item) for item in items if self._is_track_item(item)]

    async def top_tracks_for_artist(self, artist: str, limit: int = 10) -> list[TrackPayload]:
        if not self.enabled:
            return []

        data = await self._call_api(
            {
                "method": "artist.gettoptracks",
                "artist": artist,
                "limit": limit,
            }
        )
        items = _ensure_list(data.get("toptracks", {}).get("track"))
        return [self._map_track(item) for item in items if self._is_track_item(item)]

    async def top_albums_for_artist(self, artist: str, limit: int = 10) -> list[AlbumPayload]:
        if not self.enabled:
            return []

        data = await self._call_api(
            {
                "method": "artist.gettopalbums",
                "artist": artist,
                "limit": limit,
            }
        )
        items = _ensure_list(data.get("topalbums", {}).get("album"))
        albums: list[AlbumPayload] = []
        for item in items:
            title = item.get("name")
            artist_name = item.get("artist", {}).get("name") if isinstance(item.get("artist"), dict) else item.get("artist")
            if not title or not artist_name:
                continue
            albums.append(
                AlbumPayload(
                    album_key=build_album_key(artist_name, title),
                    title=title,
                    artist=artist_name,
                    artwork_url=choose_lastfm_image(item.get("image")),
                    provider="lastfm",
                    external_id=item.get("mbid") or item.get("url"),
                )
            )
        return albums

    async def album_details(
        self,
        artist: str,
        title: str,
    ) -> tuple[AlbumPayload | None, list[TrackPayload]]:
        if not self.enabled:
            return None, []

        data = await self._call_api(
            {
                "method": "album.getinfo",
                "artist": artist,
                "album": title,
            }
        )
        item = data.get("album")
        if not isinstance(item, dict) or not item.get("name"):
            return None, []

        album_artist = item.get("artist") or artist
        album = AlbumPayload(
            album_key=build_album_key(album_artist, item["name"]),
            title=item["name"],
            artist=album_artist,
            artwork_url=choose_lastfm_image(item.get("image")),
            provider="lastfm",
            external_id=item.get("mbid") or item.get("url"),
            summary=strip_lastfm_summary(item.get("wiki", {}).get("summary")),
        )

        tracks: list[TrackPayload] = []
        for track in _ensure_list(item.get("tracks", {}).get("track")):
            track_artist = track.get("artist", {}).get("name") if isinstance(track.get("artist"), dict) else album_artist
            track_title = track.get("name")
            if not track_artist or not track_title:
                continue
            duration_value = track.get("duration")
            duration_ms = None
            if duration_value not in (None, "", "0"):
                duration_ms = int(float(duration_value)) * 1000
            tracks.append(
                TrackPayload(
                    track_key=build_track_key(track_artist, track_title),
                    title=track_title,
                    artist=track_artist,
                    album=item["name"],
                    artwork_url=album.artwork_url,
                    duration_ms=duration_ms,
                    provider="lastfm",
                    external_id=track.get("url"),
                )
            )
        return album, tracks

    async def similar_artists(self, artist: str, limit: int = 10) -> list[ArtistPayload]:
        if not self.enabled:
            return []

        data = await self._call_api(
            {
                "method": "artist.getsimilar",
                "artist": artist,
                "limit": limit,
            }
        )
        items = _ensure_list(data.get("similarartists", {}).get("artist"))
        artists: list[ArtistPayload] = []
        for item in items:
            name = item.get("name")
            if not name:
                continue
            match = item.get("match")
            artists.append(
                ArtistPayload(
                    artist_key=build_artist_key(name),
                    name=name,
                    image_url=choose_lastfm_image(item.get("image")),
                    provider="lastfm",
                    external_id=item.get("mbid") or item.get("url"),
                    url=item.get("url"),
                    listeners=int(float(match) * 100) if match not in (None, "") else None,
                )
            )
        return artists

    async def top_tracks_for_query(self, query: str, limit: int = 10) -> list[TrackPayload]:
        artists = await self.search_artists(query, limit=5)
        exact_match = next(
            (artist for artist in artists if normalize_value(artist.name) == normalize_value(query)),
            None,
        )
        if exact_match is None:
            return []
        return await self.top_tracks_for_artist(exact_match.name, limit=limit)

    async def _call_api(self, params: dict[str, str | int]) -> dict:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(
                    self.base_url,
                    params={
                        **params,
                        "api_key": settings.lastfm_api_key,
                        "format": "json",
                    },
                )
                response.raise_for_status()
                data = response.json()
                if "error" in data:
                    return {}
                return data
        except Exception:
            return {}

    def _is_track_item(self, item: dict) -> bool:
        artist_data = item.get("artist")
        artist_name = artist_data.get("name") if isinstance(artist_data, dict) else artist_data
        return bool(item.get("name") and artist_name)

    def _map_track(self, item: dict) -> TrackPayload:
        artist_data = item.get("artist")
        artist_name = artist_data.get("name") if isinstance(artist_data, dict) else artist_data
        duration_value = item.get("duration")
        duration_ms = None
        if duration_value not in (None, "", "0"):
            duration_ms = int(float(duration_value)) * 1000

        return TrackPayload(
            track_key=build_track_key(artist_name, item["name"]),
            title=item["name"],
            artist=artist_name,
            artwork_url=choose_lastfm_image(item.get("image")),
            duration_ms=duration_ms,
            provider="lastfm",
            external_id=item.get("mbid") or item.get("url"),
        )
