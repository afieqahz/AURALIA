import asyncio
import base64
import re
import os
import time
from datetime import datetime, timezone
from typing import Any

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()

app = FastAPI(title="AURALIA API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_spotify_access_token: str | None = None
_spotify_token_expires_at = 0.0
_spotify_search_cache: dict[str, tuple[float, dict[str, Any]]] = {}
_spotify_search_cache_ttl = 60 * 60 * 6
_spotify_rate_limit_cache_ttl = 60
_spotify_image_cache: dict[str, str] = {}
_spotify_search_limit = 50
_min_release_year = 2010
# Auto-tracks the current year instead of a hardcoded value, so new
# releases aren't silently filtered out once the calendar turns over.
_max_release_year = datetime.now(timezone.utc).year


@app.get("/health")
async def health() -> dict[str, str]:
    spotify_ready = bool(os.getenv("SPOTIFY_CLIENT_ID") and os.getenv("SPOTIFY_CLIENT_SECRET"))
    return {"status": "ok", "spotify": "configured" if spotify_ready else "missing"}


@app.post("/spotify/token")
async def spotify_token() -> dict[str, Any]:
    return await _spotify_token()


async def _spotify_token() -> dict[str, Any]:
    global _spotify_access_token, _spotify_token_expires_at

    now = time.time()
    if _spotify_access_token and now < _spotify_token_expires_at:
        return {
            "access_token": _spotify_access_token,
            "token_type": "Bearer",
            "expires_in": int(_spotify_token_expires_at - now),
        }

    client_id = os.getenv("SPOTIFY_CLIENT_ID")
    client_secret = os.getenv("SPOTIFY_CLIENT_SECRET")

    if not client_id or not client_secret:
        raise HTTPException(status_code=500, detail="Spotify credentials are not configured.")

    basic_token = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()

    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(
            "https://accounts.spotify.com/api/token",
            headers={"Authorization": f"Basic {basic_token}"},
            data={"grant_type": "client_credentials"},
        )

    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    token_response = response.json()
    token = token_response.get("access_token")
    expires_in = int(token_response.get("expires_in", 3600))

    if token:
        _spotify_access_token = token
        _spotify_token_expires_at = now + max(expires_in - 60, 60)

    return token_response


@app.get("/spotify/search")
async def spotify_search(
    q: str = Query(..., min_length=1),
    allow_fallback: bool = Query(True),
    mood: str = Query("neutral"),
    target_mood: str = Query(""),
) -> dict[str, Any]:
    mood = mood.strip().lower()
    target_mood = target_mood.strip().lower() or _default_target_mood(mood)
    cache_key = f"{q.strip().lower()}|fallback={allow_fallback}|mood={mood}|target={target_mood}"
    cached = _spotify_search_cache.get(cache_key)
    now = time.time()
    if cached and cached[0] > now:
        return cached[1]

    token_response = await _spotify_token()
    token = token_response.get("access_token")

    if not token:
        raise HTTPException(status_code=500, detail="Spotify token response did not include access_token.")

    data = await _spotify_track_search(
        token, q, allow_fallback=allow_fallback, mood=mood, target_mood=target_mood
    )

    if data.get("auralia_source") == "fallback":
        # The fallback catalog is a small, hand-picked set of well-known
        # songs used when Spotify is unavailable/rate limited. Running it
        # through _rank_mainstream_tracks used to wipe it out entirely:
        # fallback tracks never set album.release_date, so
        # _release_year_is_allowed rejected every single one, and a rate
        # limited request would silently come back with zero tracks
        # instead of the fallback catalog it was meant to show. The
        # fallback tracks/iso_sequence are already curated, so pass them
        # through as-is instead of re-filtering them.
        if data.get("auralia_error") == "rate_limited":
            _spotify_search_cache[cache_key] = (
                now + _spotify_rate_limit_cache_ttl,
                data,
            )
        return data

    items = data.get("tracks", {}).get("items", [])

    ranked_items = _rank_mainstream_tracks(items)
    ranked_items = _dedupe_tracks(ranked_items)

    # NOTE: this sort is only used for the flat "items" list returned to the
    # app (e.g. for a generic browse view). It must NOT be used to build the
    # Iso-Principle sequence below, because sorting everything by a single
    # mood score before slicing gave no guarantee that the tail of the list
    # trended toward the target mood - see _build_iso_playlist for the fix.
    ranked_items = sorted(
        ranked_items,
        key=lambda t: _mood_boost(t, mood),
        reverse=True
    )

    iso_playlist = _build_iso_playlist(ranked_items, mood, target_mood)

    data["tracks"] = {
    "href": data.get("tracks", {}).get("href", ""),
    "limit": 30,
    "total": len(ranked_items),
    "items": ranked_items[:30],
    "iso_sequence": iso_playlist,
    }
    
    if data.get("auralia_error") == "rate_limited":
        _spotify_search_cache[cache_key] = (
            now + _spotify_rate_limit_cache_ttl,
            data,
        )
    elif (
        data.get("auralia_source") == "spotify_api"
        and data.get("auralia_error") != "no_usable_spotify_tracks"
    ):
        _spotify_search_cache[cache_key] = (now + _spotify_search_cache_ttl, data)
    return data




@app.get("/spotify/tracks")
async def spotify_tracks(
    ids: str = Query(..., min_length=1),
) -> dict[str, Any]:
    track_ids = [
        track_id.strip()
        for track_id in ids.split(",")
        if track_id.strip()
    ][:50]

    if not track_ids:
        raise HTTPException(status_code=400, detail="No Spotify track ids were provided.")

    token_response = await _spotify_token()
    token = token_response.get("access_token")

    if not token:
        raise HTTPException(status_code=500, detail="Spotify token response did not include access_token.")

    data = await _spotify_tracks_lookup(token, track_ids)
    if data is not None:
        return data

    return await _fallback_tracks_by_id(track_ids)


async def _spotify_tracks_lookup(
    token: str,
    track_ids: list[str],
) -> dict[str, Any] | None:
    async with httpx.AsyncClient(timeout=15) as client:
        for params in (
            {"ids": ",".join(track_ids), "market": "MY"},
            {"ids": ",".join(track_ids)},
        ):
            response = await client.get(
                "https://api.spotify.com/v1/tracks",
                params=params,
                headers={"Authorization": f"Bearer {token}"},
            )

            if response.status_code < 400:
                return response.json()

            if response.status_code not in (403, 429):
                raise HTTPException(status_code=response.status_code, detail=response.text)

    return None


async def _spotify_track_search(
    token: str,
    query: str,
    allow_fallback: bool = True,
    mood: str = "neutral",
    target_mood: str = "happy",
) -> dict[str, Any]:
    clean_query = _simplify_search_query(query)
    constrained_query = _constrain_spotify_query(query)
    constrained_clean_query = _constrain_spotify_query(clean_query)
    search_queries = list(
        dict.fromkeys(
            query
            for query in (constrained_query, constrained_clean_query)
            if query.strip()
        )
    )[:2]
    offsets = (0,)

    first_response_body: dict[str, Any] | None = None

    async with httpx.AsyncClient(timeout=15) as client:
        for search_query in search_queries:
            response_body = await _spotify_search_with_params(
                client=client,
                token=token,
                original_query=query,
                search_query=search_query,
                offsets=offsets,
                market="MY",
                allow_fallback=allow_fallback,
                mood=mood,
                target_mood=target_mood,
            )
            if response_body.get("auralia_error") == "rate_limited":
                return response_body
            if first_response_body is None and response_body:
                first_response_body = response_body

            items = response_body.get("tracks", {}).get("items", [])
            if items:
                return response_body

            no_market_response = await _spotify_search_with_params(
                client=client,
                token=token,
                original_query=query,
                search_query=search_query,
                offsets=(0,),
                market=None,
                allow_fallback=allow_fallback,
                mood=mood,
                target_mood=target_mood,
            )
            if no_market_response.get("auralia_error") == "rate_limited":
                return no_market_response
            if first_response_body is None and no_market_response:
                first_response_body = no_market_response

            items = no_market_response.get("tracks", {}).get("items", [])
            if items:
                return no_market_response

    if not allow_fallback:
        return await _spotify_empty_search(query, "no_usable_spotify_tracks")

    return await _fallback_spotify_search(query, mood=mood, target_mood=target_mood)


async def _spotify_search_with_params(
    *,
    client: httpx.AsyncClient,
    token: str,
    original_query: str,
    search_query: str,
    offsets: tuple[int, ...],
    market: str | None,
    allow_fallback: bool,
    mood: str = "neutral",
    target_mood: str = "happy",
) -> dict[str, Any]:
    params: dict[str, Any] = {
        "q": search_query,
        "type": "track",
        "limit": _spotify_search_limit,
    }
    if market:
        params["market"] = market

    for offset in offsets:
        response = await client.get(
            "https://api.spotify.com/v1/search",
            params={**params, "offset": offset},
            headers={"Authorization": f"Bearer {token}"},
        )

        if response.status_code >= 400:
            if (
                response.status_code == 400
                and "Invalid limit" in response.text
                and "limit" in params
            ):
                retry_params = {
                    key: value
                    for key, value in params.items()
                    if key != "limit"
                }
                response = await client.get(
                    "https://api.spotify.com/v1/search",
                    params=retry_params,
                    headers={"Authorization": f"Bearer {token}"},
                )
                if response.status_code < 400:
                    body = response.json()
                    items = body.get("tracks", {}).get("items", [])
                    print(
                        "AURALIA Spotify search ok "
                        f"query={search_query} retry=default-limit "
                        f"market={market or 'none'} items={len(items)}"
                    )
                    if items:
                        return body

            print(
                "AURALIA Spotify search failed "
                f"status={response.status_code} query={search_query} "
                f"market={market or 'none'} body={response.text[:160]}"
            )
            if response.status_code == 429:
                retry_after = response.headers.get("Retry-After")
                if not allow_fallback:
                    return await _spotify_empty_search(
                        original_query,
                        "rate_limited",
                        retry_after=retry_after,
                    )
                fallback = await _fallback_spotify_search(
                    original_query, mood=mood, target_mood=target_mood
                )
                fallback["auralia_error"] = "rate_limited"
                if retry_after:
                    fallback["retry_after_seconds"] = retry_after
                return fallback
            return {}

        body = response.json()
        items = body.get("tracks", {}).get("items", [])
        print(
            "AURALIA Spotify search ok "
            f"query={search_query} offset={offset} "
            f"market={market or 'none'} items={len(items)}"
        )
        if items:
            return body

    return {}


async def _spotify_empty_search(
    query: str,
    reason: str,
    retry_after: str | None = None,
) -> dict[str, Any]:
    response = {
        "auralia_source": "spotify_api",
        "auralia_error": reason,
        "tracks": {
            "href": "",
            "limit": 0,
            "next": None,
            "offset": 0,
            "previous": None,
            "total": 0,
            "items": [],
        },
    }
    if retry_after:
        response["retry_after_seconds"] = retry_after
    return response


def _simplify_search_query(query: str) -> str:
    removable_words = {
        "popular",
        "mainstream",
        "viral",
        "hits",
        "songs",
        "song",
        "pop",
        "acoustic",
        "mood",
    }
    words = [
        word
        for word in query.lower().replace("-", " ").split()
        if word not in removable_words
    ]
    return " ".join(words) or query


async def _fallback_spotify_search(
    query: str,
    mood: str = "neutral",
    target_mood: str = "happy",
) -> dict[str, Any]:
    query_lower = query.lower()
    catalog = _fallback_catalog_for_query(query_lower)
    image_urls = await _spotify_oembed_images([track["id"] for track in catalog])

    tracks = [
        _fallback_track_json(
            {
                **track,
                "image_url": image_urls.get(track["id"]),
            },
            index,
        )
        for index, track in enumerate(catalog)
    ]

    # Previously called with no mood args, which silently defaulted to
    # mood="neutral", target_mood="happy" regardless of what the user
    # actually requested - so a "sad -> happy" request that hit the
    # fallback path (e.g. due to a Spotify rate limit) would ignore the
    # user's current mood entirely. Pass the real values through instead.
    iso_sequence = _build_iso_playlist(tracks, mood, target_mood)

    return {
        "auralia_source": "fallback",
        "tracks": {
            "href": "",
            "limit": len(tracks),
            "next": None,
            "offset": 0,
            "previous": None,
            "total": len(tracks),
            "items": tracks,
            "iso_sequence": iso_sequence
        }
    }

def _expand_fallback_catalog(catalog: list[dict[str, Any]]) -> list[dict[str, Any]]:
    expanded: list[dict[str, Any]] = []
    seen: set[str] = set()

    def add_tracks(tracks: list[dict[str, Any]]) -> None:
        for track in tracks:
            track_id = track.get("id")
            if not isinstance(track_id, str) or track_id in seen:
                continue
            seen.add(track_id)
            expanded.append(track)

    add_tracks(catalog)
    for query in (
        "sad",
        "hopeful",
        "uplifting",
        "calm",
        "happy",
        "motivated",
        "neutral",
    ):
        add_tracks(_fallback_catalog_for_query(query))
        if len(expanded) >= 40:
            break

    return expanded[:50]


def _fallback_catalog_for_query(query: str) -> list[dict[str, Any]]:
    if any(word in query for word in ["sad", "heartbreak", "healing"]):
        return [
            {"id": "5wANPM4fQCJwkGd4rN57mH", "title": "drivers license", "artist": "Olivia Rodrigo"},
            {"id": "4kflIGfjdZJW4ot2ioixTB", "title": "Someone Like You", "artist": "Adele"},
            {"id": "3nsfB1vus2qaloUdcBZvDu", "title": "All Too Well", "artist": "Taylor Swift"},
            {"id": "0nJW01T7XtvILxQgC5J7Wh", "title": "When I Was Your Man", "artist": "Bruno Mars"},
            {"id": "2jyjhRf6DVbMPU5zxagN2h", "title": "Let Her Go", "artist": "Passenger"},
            {"id": "6lanRgr6wXibZr8KgzXxBl", "title": "A Thousand Years", "artist": "Christina Perri"},
            {"id": "4l0Mvzj72xxOpRrp6h8nHi", "title": "Lose You To Love Me", "artist": "Selena Gomez"},
            {"id": "5CZ40GBx1sQ9agT82CLQCT", "title": "traitor", "artist": "Olivia Rodrigo"},
            {"id": "3hRV0jL3vUpRrcy398teAU", "title": "The Night We Met", "artist": "Lord Huron"},
            {"id": "0u2P5u6lvoDfwTYjAADbn4", "title": "Lovely", "artist": "Billie Eilish, Khalid"},
        ]

    if any(word in query for word in ["hopeful", "warm", "gentle", "light"]):
        return [
            {"id": "6lanRgr6wXibZr8KgzXxBl", "title": "A Thousand Years", "artist": "Christina Perri"},
            {"id": "5x5JM1BSB6vollcIzDocqT", "title": "The Climb", "artist": "Miley Cyrus"},
            {"id": "6lanRgr6wXibZr8KgzXxBl", "title": "A Thousand Years", "artist": "Christina Perri"},
            {"id": "7l1qvxWjxcKpB9PCtBuTbU", "title": "Count on Me", "artist": "Bruno Mars"},
            {"id": "5Hroj5K7vLpIG4FNCRIjbP", "title": "Keep Your Head Up", "artist": "Andy Grammer"},
            {"id": "79qxwHypONUt3AFq0WPpT9", "title": "Rainbow", "artist": "Kacey Musgraves"},
            {"id": "6OtCIsQZ64Vs1EbzztvAv4", "title": "Good Life", "artist": "OneRepublic"},
            {"id": "0tV8pOpiNsKqUys0ilUcXz", "title": "Rise Up", "artist": "Andra Day"},
            {"id": "1HNkqx9Ahdgi1Ixy2xkKkL", "title": "Photograph", "artist": "Ed Sheeran"},
            {"id": "6UelLqGlWMcVH1E5c4H7lY", "title": "Watermelon Sugar", "artist": "Harry Styles"},
        ]

    if any(word in query for word in ["uplifting", "feel good", "positive"]):
        return [
            {"id": "6OtCIsQZ64Vs1EbzztvAv4", "title": "Good Life", "artist": "OneRepublic"},
            {"id": "4lCv7b86sLynZbXhfScfm2", "title": "Firework", "artist": "Katy Perry"},
            {"id": "5Hroj5K7vLpIG4FNCRIjbP", "title": "Best Day Of My Life", "artist": "American Authors"},
            {"id": "213x4gsFDm04hSqIUkg88w", "title": "On Top Of The World", "artist": "Imagine Dragons"},
            {"id": "4lCv7b86sLynZbXhfScfm2", "title": "Firework", "artist": "Katy Perry"},
            {"id": "1rqqCSm0Qe4I9rUvWncaom", "title": "High Hopes", "artist": "Panic! At The Disco"},
            {"id": "1p80LdxRV74UKvL8gnD7ky", "title": "Shake It Off", "artist": "Taylor Swift"},
            {"id": "60nZcImufyMA1MKQY3dcCH", "title": "Happy", "artist": "Pharrell Williams"},
            {"id": "6JV2JOEocMgcZxYSZelKcc", "title": "Can't Stop the Feeling!", "artist": "Justin Timberlake"},
            {"id": "0t1kP63rueHleOhQkYSXFY", "title": "Dynamite", "artist": "BTS"},
        ]

    if any(word in query for word in ["calm", "chill", "relax", "peaceful", "soft"]):
        return [
            {"id": "6UelLqGlWMcVH1E5c4H7lY", "title": "Watermelon Sugar", "artist": "Harry Styles"},
            {"id": "1HNkqx9Ahdgi1Ixy2xkKkL", "title": "Photograph", "artist": "Ed Sheeran"},
            {"id": "0T5iIrXA4p5GsubkhuBIKV", "title": "Until I Found You", "artist": "Stephen Sanchez"},
            {"id": "6lanRgr6wXibZr8KgzXxBl", "title": "A Thousand Years", "artist": "Christina Perri"},
            {"id": "4aT6vP9y2eDjxmRGm5ZqSC", "title": "Location Unknown", "artist": "HONNE, BEKA"},
            {"id": "49mWEy5MgtNujgT7xU3emT", "title": "Breathe", "artist": "Taylor Swift, Colbie Caillat"},
            {"id": "1RMJOxR6GRPsBHL8qeC2ux", "title": "Best Part", "artist": "Daniel Caesar, H.E.R."},
            {"id": "57yL3161hUMuw06zzzUCHi", "title": "Like Real People Do", "artist": "Hozier"},
            {"id": "0yLdNVWF3Srea0uzk55zFn", "title": "Flowers", "artist": "Miley Cyrus"},
            {"id": "6OtCIsQZ64Vs1EbzztvAv4", "title": "Good Life", "artist": "OneRepublic"},
        ]

    if any(word in query for word in ["dance", "party", "viral", "happy", "good vibes"]):
        return [
            {"id": "0t1kP63rueHleOhQkYSXFY", "title": "Dynamite", "artist": "BTS"},
            {"id": "463CkQjx2Zk1yXoBuierM9", "title": "Levitating", "artist": "Dua Lipa"},
            {"id": "4LRPiXqCikLlN15c3yImP7", "title": "As It Was", "artist": "Harry Styles"},
            {"id": "0VjIjW4GlUZAMYd2vXMi3b", "title": "Blinding Lights", "artist": "The Weeknd"},
            {"id": "32OlwWuMpZ6b0aN2RZOeMS", "title": "Uptown Funk", "artist": "Mark Ronson, Bruno Mars"},
            {"id": "6JV2JOEocMgcZxYSZelKcc", "title": "Can't Stop the Feeling!", "artist": "Justin Timberlake"},
            {"id": "6UelLqGlWMcVH1E5c4H7lY", "title": "Watermelon Sugar", "artist": "Harry Styles"},
            {"id": "4ZtFanR9U6ndgddUvNcjcG", "title": "good 4 u", "artist": "Olivia Rodrigo"},
            {"id": "0yLdNVWF3Srea0uzk55zFn", "title": "Flowers", "artist": "Miley Cyrus"},
            {"id": "1p80LdxRV74UKvL8gnD7ky", "title": "Shake It Off", "artist": "Taylor Swift"},
        ]

    if any(word in query for word in ["motiv", "workout", "confidence", "power", "focus"]):
        return [
            {"id": "1rqqCSm0Qe4I9rUvWncaom", "title": "High Hopes", "artist": "Panic! At The Disco"},
            {"id": "0pqnGHJpmpxLKifKRmU6WP", "title": "Believer", "artist": "Imagine Dragons"},
            {"id": "1yvMUkIOTeUNtNWlWRgANS", "title": "Unstoppable", "artist": "Sia"},
            {"id": "2dOTkLZFbpNXrhc24CnTFd", "title": "Titanium", "artist": "David Guetta, Sia"},
            {"id": "3bidbhpOYeV4knp8AIu8Xn", "title": "Can't Hold Us", "artist": "Macklemore & Ryan Lewis"},
            {"id": "1X1DWw2pcNZ8zSub3uhlNz", "title": "Hall of Fame", "artist": "The Script, will.i.am"},
            {"id": "0pqnGHJpmpxLKifKRmU6WP", "title": "Believer", "artist": "Imagine Dragons"},
            {"id": "1uXbwHHfgsXcUKfSZw5ZJ0", "title": "Run the World (Girls)", "artist": "Beyonce"},
            {"id": "0ct6r3EGTcMLPtrXHDvVjc", "title": "The Nights", "artist": "Avicii"},
            {"id": "213x4gsFDm04hSqIUkg88w", "title": "On Top Of The World", "artist": "Imagine Dragons"},
        ]

    return [
        {"id": "0t1kP63rueHleOhQkYSXFY", "title": "Dynamite", "artist": "BTS"},
        {"id": "4LRPiXqCikLlN15c3yImP7", "title": "As It Was", "artist": "Harry Styles"},
        {"id": "0VjIjW4GlUZAMYd2vXMi3b", "title": "Blinding Lights", "artist": "The Weeknd"},
        {"id": "463CkQjx2Zk1yXoBuierM9", "title": "Levitating", "artist": "Dua Lipa"},
        {"id": "1p80LdxRV74UKvL8gnD7ky", "title": "Shake It Off", "artist": "Taylor Swift"},
        {"id": "4ZtFanR9U6ndgddUvNcjcG", "title": "good 4 u", "artist": "Olivia Rodrigo"},
        {"id": "32OlwWuMpZ6b0aN2RZOeMS", "title": "Uptown Funk", "artist": "Mark Ronson, Bruno Mars"},
        {"id": "6UelLqGlWMcVH1E5c4H7lY", "title": "Watermelon Sugar", "artist": "Harry Styles"},
        {"id": "7qiZfU4dY1lWllzX7mPBI3", "title": "Shape of You", "artist": "Ed Sheeran"},
        {"id": "0yLdNVWF3Srea0uzk55zFn", "title": "Flowers", "artist": "Miley Cyrus"},
    ]


async def _fallback_tracks_by_id(track_ids: list[str]) -> dict[str, Any]:
    image_urls = await _spotify_oembed_images(track_ids)
    return {
        "tracks": [
            _fallback_track_json(
                {
                    **_fallback_track_details(track_id),
                    "image_url": image_urls.get(track_id),
                },
                index,
            )
            for index, track_id in enumerate(track_ids)
        ]
    }


async def _spotify_oembed_images(track_ids: list[str]) -> dict[str, str]:
    unique_ids = list(dict.fromkeys(track_ids))
    image_urls: dict[str, str] = {
        track_id: _spotify_image_cache[track_id]
        for track_id in unique_ids
        if track_id in _spotify_image_cache
    }
    missing_ids = [
        track_id for track_id in unique_ids if track_id not in image_urls
    ]
    if not missing_ids:
        return image_urls

    semaphore = asyncio.Semaphore(20)

    async def limited_oembed(track_id: str) -> tuple[str, str] | None:
        async with semaphore:
            return await _spotify_oembed_image(client, track_id)

    async with httpx.AsyncClient(timeout=2, follow_redirects=True) as client:
        results = await asyncio.gather(
            *[limited_oembed(track_id) for track_id in missing_ids],
            return_exceptions=True,
        )

    for result in results:
        if isinstance(result, tuple):
            track_id, image_url = result
            _spotify_image_cache[track_id] = image_url
            image_urls[track_id] = image_url

    return image_urls


async def _spotify_oembed_image(
    client: httpx.AsyncClient,
    track_id: str,
) -> tuple[str, str] | None:
    try:
        response = await client.get(
            "https://open.spotify.com/oembed",
            params={"url": f"https://open.spotify.com/track/{track_id}"},
        )
    except httpx.HTTPError:
        return None

    if response.status_code >= 400:
        return None

    try:
        thumbnail_url = response.json().get("thumbnail_url")
    except ValueError:
        return None

    if isinstance(thumbnail_url, str) and thumbnail_url:
        return track_id, thumbnail_url

    return None


def _fallback_track_details(track_id: str) -> dict[str, Any]:
    fallback = _fallback_track_details_by_id().get(track_id)
    if fallback:
        return {"id": track_id, **fallback}

    return {
        "id": track_id,
        "title": "Spotify Track",
        "artist": "Spotify",
        "duration_ms": 240000,
    }


def _fallback_track_details_by_id() -> dict[str, dict[str, Any]]:
    return {
        "6UelLqGlWMcVH1E5c4H7lY": {"title": "Watermelon Sugar", "artist": "Harry Styles", "duration_ms": 174000},
        "3JvrhDOgAt6p7K8mDyZwRd": {"title": "Riptide", "artist": "Vance Joy", "duration_ms": 204000},
        "7l1qvxWjxcKpB9PCtBuTbU": {"title": "Count on Me", "artist": "Bruno Mars", "duration_ms": 197000},
        "7LVHVU3tWfcxj5aiPFEW4Q": {"title": "Fix You", "artist": "Coldplay", "duration_ms": 295000},
        "3AJwUDP919kvQ9QcozQPxg": {"title": "Yellow", "artist": "Coldplay", "duration_ms": 267000},
        "0yLdNVWF3Srea0uzk55zFn": {"title": "Flowers", "artist": "Miley Cyrus", "duration_ms": 200000},
        "6OtCIsQZ64Vs1EbzztvAv4": {"title": "Good Life", "artist": "OneRepublic", "duration_ms": 253000},
        "3hRV0jL3vUpRrcy398teAU": {"title": "The Night We Met", "artist": "Lord Huron", "duration_ms": 208000},
        "5wANPM4fQCJwkGd4rN57mH": {"title": "drivers license", "artist": "Olivia Rodrigo", "duration_ms": 242000},
        "4kflIGfjdZJW4ot2ioixTB": {"title": "Someone Like You", "artist": "Adele", "duration_ms": 285000},
        "6lanRgr6wXibZr8KgzXxBl": {"title": "A Thousand Years", "artist": "Christina Perri", "duration_ms": 285000},
        "5x5JM1BSB6vollcIzDocqT": {"title": "The Climb", "artist": "Miley Cyrus", "duration_ms": 235000},
        "60nZcImufyMA1MKQY3dcCH": {"title": "Happy", "artist": "Pharrell Williams", "duration_ms": 232000},
        "1p80LdxRV74UKvL8gnD7ky": {"title": "Shake It Off", "artist": "Taylor Swift", "duration_ms": 219000},
        "463CkQjx2Zk1yXoBuierM9": {"title": "Levitating", "artist": "Dua Lipa", "duration_ms": 203000},
        "4LRPiXqCikLlN15c3yImP7": {"title": "As It Was", "artist": "Harry Styles", "duration_ms": 167000},
        "0VjIjW4GlUZAMYd2vXMi3b": {"title": "Blinding Lights", "artist": "The Weeknd", "duration_ms": 200000},
        "32OlwWuMpZ6b0aN2RZOeMS": {"title": "Uptown Funk", "artist": "Mark Ronson, Bruno Mars", "duration_ms": 270000},
        "0t1kP63rueHleOhQkYSXFY": {"title": "Dynamite", "artist": "BTS", "duration_ms": 199000},
        "0pqnGHJpmpxLKifKRmU6WP": {"title": "Believer", "artist": "Imagine Dragons", "duration_ms": 204000},
        "1rqqCSm0Qe4I9rUvWncaom": {"title": "High Hopes", "artist": "Panic! At The Disco", "duration_ms": 190000},
        "213x4gsFDm04hSqIUkg88w": {"title": "On Top Of The World", "artist": "Imagine Dragons", "duration_ms": 192000},
        "0RiRZpuVRbi7oqRdSMwhQY": {"title": "Sunflower", "artist": "Post Malone, Swae Lee", "duration_ms": 158000},
        "02MWAaffLxlfxAUY7c5dvx": {"title": "Heat Waves", "artist": "Glass Animals", "duration_ms": 238000},
        "2b8fOow8UzyDFAE27YhOZM": {"title": "Memories", "artist": "Maroon 5", "duration_ms": 189000},
        "1HNkqx9Ahdgi1Ixy2xkKkL": {"title": "Photograph", "artist": "Ed Sheeran", "duration_ms": 259000},
        "4lCv7b86sLynZbXhfScfm2": {"title": "Firework", "artist": "Katy Perry", "duration_ms": 228000},
        "6JV2JOEocMgcZxYSZelKcc": {"title": "Can't Stop the Feeling!", "artist": "Justin Timberlake", "duration_ms": 236000},
        "7qiZfU4dY1lWllzX7mPBI3": {"title": "Shape of You", "artist": "Ed Sheeran", "duration_ms": 234000},
        "4ZtFanR9U6ndgddUvNcjcG": {"title": "good 4 u", "artist": "Olivia Rodrigo", "duration_ms": 178000},
    }


def _fallback_track_json(track: dict[str, Any], index: int) -> dict[str, Any]:
    track_id = track["id"]
    title = track["title"]
    artist = track["artist"]
    image_url = track.get("image_url")

    return {
        "id": track_id,
        "name": title,
        "artists": [{"name": artist}],
        "album": {"images": _album_images(image_url)},
        "external_urls": {"spotify": f"https://open.spotify.com/track/{track_id}"},
        "is_local": False,
        "is_playable": True,
        "popularity": 80 - index,
        "preview_url": None,
        "duration_ms": int(track.get("duration_ms", 240000)),
    }


def _album_images(image_url: Any) -> list[dict[str, Any]]:
    if not isinstance(image_url, str) or not image_url:
        return []

    return [
        {"url": image_url, "height": 640, "width": 640},
        {"url": image_url, "height": 300, "width": 300},
        {"url": image_url, "height": 64, "width": 64},
    ]

def _default_target_mood(mood: str) -> str:
    """
    Where the Iso-Principle sequence should end up if the app/client did not
    explicitly send a target_mood. This mirrors the "gentle lift" behaviour
    already described to users in the AURALIA chat (e.g. a neutral mood gets
    a light lift rather than staying flat, a sad mood is walked toward happy
    rather than jumping straight there).
    """
    progression = {
        "sad": "happy",
        "stressed": "motivated",
        "neutral": "happy",
        "happy": "happy",
        "motivated": "motivated",
    }
    return progression.get(mood, "happy")


# Moods that sit at opposite ends of the same axis. Used by _net_mood_score
# to penalise a track that scores well for the opposite mood, so a track
# that superficially matches a "happy" keyword but is really a heartbreak
# song (or vice versa) doesn't get placed in the wrong phase.
_OPPOSITE_MOOD = {
    "sad": "happy",
    "happy": "sad",
    "stressed": "motivated",
    "motivated": "stressed",
}


def _mood_boost(track: dict[str, Any], mood: str) -> float:
    text = (
        str(track.get("name", "")) + " " +
        " ".join(a.get("name", "") for a in track.get("artists", []))
    ).lower()

    def has_any(keywords: list[str]) -> bool:
        # Whole-word match only. Plain substring containment (the previous
        # behaviour) caused false positives such as "good" matching inside
        # "Goodbye" - which meant a clearly sad track ("Goodbye Stay") could
        # score as a happy-keyword match and get pulled into the elevation
        # phase. \b...\b anchors each keyword to real word boundaries.
        return any(re.search(rf"\b{re.escape(k)}\b", text) for k in keywords)

    if mood == "sad":
        keywords = ["love", "cry", "alone", "heart", "pain", "stay", "goodbye", "miss", "broken", "tears"]
        return 3.0 if has_any(keywords) else 1.0

    if mood == "stressed":
        keywords = ["calm", "breathe", "soft", "peace", "easy", "slow", "focus"]
        return 3.0 if has_any(keywords) else 1.0

    if mood == "motivated":
        keywords = ["fire", "run", "win", "power", "strong", "rise", "fight", "unstoppable", "believer"]
        return 3.0 if has_any(keywords) else 1.0

    if mood == "happy":
        # NOTE: "love" is deliberately NOT in this list - it also appears in
        # the "sad" list above (heartbreak songs say "love" constantly too),
        # so keeping it here made happy/sad scoring ambiguous for any track
        # with "love" in the title/artist, regardless of the track's actual
        # mood. Keywords should stay as mutually exclusive as possible
        # between opposite moods (see _OPPOSITE_MOOD / _net_mood_score).
        keywords = ["happy", "dance", "sun", "smile", "feeling", "shake", "joy"]
        return 3.0 if has_any(keywords) else 1.0

    if mood == "neutral":
        # Neutral has no strong keyword signal by design - it should not
        # outrank everything else, so it stays at the same baseline as an
        # unmatched track (1.0) rather than 0, which would otherwise make
        # neutral tracks always lose ties against a mismatched keyword hit.
        return 1.0

    return 1.0


def _net_mood_score(track: dict[str, Any], for_mood: str) -> float:
    """
    _mood_boost scores a track against ONE mood in isolation. That let a
    track like "Alone Again" (no keyword hit for "happy") tie with genuinely
    upbeat tracks whenever nothing scored higher, and get placed into the
    elevation phase purely on popularity. This adds a penalty when the track
    ALSO scores well for the opposite mood, so a track that's really a
    heartbreak/low-energy song is deprioritised for the elevation phase even
    if it happens to be popular, and vice versa for the validation phase.
    """
    score = _mood_boost(track, for_mood)
    opposite = _OPPOSITE_MOOD.get(for_mood)
    if opposite:
        score -= (_mood_boost(track, opposite) - 1.0)
    return score

def _rank_mainstream_tracks(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """
    Removes duplicate songs (album/single/deluxe versions),
    filters low-quality tracks,
    then ranks by popularity + recency.
    """

    def normalize(text: str) -> str:
        return re.sub(r'[^a-z0-9]', '', (text or "").lower())

    seen_tracks: set[tuple[str, str]] = set()
    unique_items: list[dict[str, Any]] = []

    for item in items:
        if not isinstance(item, dict):
            continue

        if not item.get("id"):
            continue

        title = item.get("name", "")
        artists = item.get("artists") or []

        artist = ""
        if isinstance(artists, list) and artists:
            artist = artists[0].get("name", "")

        key = (normalize(title), normalize(artist))

        if key in seen_tracks:
            continue

        seen_tracks.add(key)
        unique_items.append(item)

    playable = [
        item
        for item in unique_items
        if item.get("is_playable", True)
        and not item.get("is_local", False)
        and _release_year_is_allowed(item)
        and _looks_like_real_song(item)
    ]

    def score(track: dict[str, Any]) -> float:
        popularity = track.get("popularity") or 0

        try:
            year = int(track.get("album", {}).get("release_date", "")[:4])
        except Exception:
            year = 2023

        recent_bonus = max(0, (year - 2020) * 4)
        very_popular_bonus = 80 if popularity >= 80 else 0
        known_bonus = 30 if popularity >= 70 else 0
        return popularity * 12 + recent_bonus + very_popular_bonus + known_bonus

    return sorted(playable, key=score, reverse=True)

def _dedupe_tracks(tracks):
    seen = set()
    result = []

    for t in tracks:
        key = t.get("id")
        if key in seen:
            continue
        seen.add(key)
        result.append(t)

    return result

def _build_iso_playlist(tracks, mood="neutral", target_mood="happy"):
    """
    Builds the 3-phase Iso-Principle sequence: validation (matches the
    listener's current mood), transition (bridges the two), and elevation
    (matches the target mood).

    BUG THIS FIXES: the previous version received a list that was already
    sorted once by a single mood score and then just sliced it into three
    equal chunks by position. That meant:
      1. There was no target_mood at all - nothing pulled the back of the
         playlist toward a *different*, more positive mood.
      2. Because every track only ever competed on ONE score (the starting
         mood), most tracks tied at the same baseline value and effectively
         kept whatever order the popularity ranking gave them. A track that
         happened to rank high on popularity but still matched "sad" style
         keywords could land anywhere in the back two-thirds of the list -
         which is exactly why a sad-leaning track could resurface around
         track 7 after the playlist had already turned uplifting.

    THE FIX: each phase is now built by picking the best-scoring *remaining*
    tracks for that phase's target mood, and removing them from the pool
    before the next phase is built. A track can therefore only ever be
    picked for one phase, and the elevation phase is explicitly scored
    against target_mood instead of inheriting leftovers from the starting
    mood's sort order.
    """
    if not tracks:
        return {"validation": [], "transition": [], "elevation": []}

    pool = list(tracks)
    total = len(pool)
    first_cut = max(1, total // 3)
    last_cut = max(first_cut + 1, (total * 2) // 3)
    validation_size = first_cut
    elevation_size = total - last_cut

    def popularity(track: dict[str, Any]) -> float:
        return track.get("popularity") or 0

    def combined_score(track: dict[str, Any], for_mood: str) -> float:
        # Mood score alone used to decide phase placement outright, with
        # popularity only breaking exact ties - so an obscure track with a
        # lucky keyword hit (e.g. "sun" in the title) could outrank a
        # famous track with no keyword hit at all. Blending both into one
        # number means popularity now has continuous influence: a track
        # needs a *meaningfully* better mood match, not just any match, to
        # beat a much more popular/familiar one.
        return _net_mood_score(track, for_mood) * 2 + popularity(track) * 0.15

    def take_best(candidates: list[dict[str, Any]], for_mood: str, count: int):
        if count <= 0 or not candidates:
            return [], candidates
        ranked = sorted(
            candidates,
            key=lambda t: combined_score(t, for_mood),
            reverse=True,
        )
        chosen = ranked[:count]
        chosen_ids = {t.get("id") for t in chosen}
        remaining = [t for t in candidates if t.get("id") not in chosen_ids]
        return chosen, remaining

    # Phase 1: pick tracks that best match where the listener is RIGHT NOW.
    validation, pool = take_best(pool, mood, validation_size)

    # Phase 3: from what's left, pick tracks that best match where the
    # listener is heading. Doing this before transition (instead of after)
    # guarantees the elevation phase actually trends toward target_mood
    # rather than just receiving whatever validation didn't use.
    elevation, pool = take_best(pool, target_mood, elevation_size)

    # Phase 2: whatever remains bridges the two moods. Tracks that don't
    # strongly match either extreme are the most "transitional" by
    # definition, so prefer low |start_score - target_score| before falling
    # back to popularity.
    def transition_key(t: dict[str, Any]) -> tuple[float, float]:
        start_score = _mood_boost(t, mood)
        end_score = _mood_boost(t, target_mood)
        return (-abs(start_score - end_score), popularity(t))

    transition = sorted(pool, key=transition_key, reverse=True)

    return {
        "validation": validation,
        "transition": transition,
        "elevation": elevation,
    }

def _release_year_is_allowed(item: dict[str, Any]) -> bool:
    release_date = str(item.get("album", {}).get("release_date", ""))
    try:
        year = int(release_date[:4])
    except ValueError:
        return False
    return _min_release_year <= year <= _max_release_year


def _looks_like_real_song(item: dict[str, Any]) -> bool:
    duration_ms = item.get("duration_ms")

    if isinstance(duration_ms, (int, float)):
        if duration_ms < 90_000 or duration_ms > 8 * 60_000:
            return False

    artists = item.get("artists")
    if not isinstance(artists, list) or not artists:
        return False

    album = item.get("album", {})
    images = album.get("images", []) if isinstance(album, dict) else []
    if not images:
        return False

    text_parts = [
        str(item.get("name", "")),
        str(album.get("name", "")) if isinstance(album, dict) else "",
        " ".join(
            str(a.get("name", ""))
            for a in artists
            if isinstance(a, dict)
        ),
    ]

    searchable = " ".join(text_parts).lower()

    blocked_terms = {
        "karaoke", "tribute", "cover version", "instrumental",
        "piano version", "lofi", "lo-fi", "sped up", "slowed",
        "nightcore", "8d audio", "podcast", "episode",
        "meditation", "frequency", "white noise",
        "rain sounds", "sleep sounds", "tabata",
        "workout timer",
    }

    if any(term in searchable for term in blocked_terms):
        return False

    popularity = item.get("popularity")
    if isinstance(popularity, int) and popularity < 78:
        return False

    return True

def _constrain_spotify_query(query: str) -> str:
    return query.strip()
