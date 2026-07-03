import asyncio
import base64
import os
import time
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
_min_release_year = 2021
_max_release_year = 2026


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
) -> dict[str, Any]:
    cache_key = f"{q.strip().lower()}|fallback={allow_fallback}"
    cached = _spotify_search_cache.get(cache_key)
    now = time.time()
    if cached and cached[0] > now:
        return cached[1]

    token_response = await _spotify_token()
    token = token_response.get("access_token")

    if not token:
        raise HTTPException(status_code=500, detail="Spotify token response did not include access_token.")

    data = await _spotify_track_search(token, q, allow_fallback=allow_fallback)
    items = data.get("tracks", {}).get("items", [])

    ranked_items = _rank_mainstream_tracks(items)
    data.setdefault("tracks", {})["items"] = ranked_items[:80]
    data["tracks"]["limit"] = min(80, len(ranked_items))
    data["tracks"]["total"] = len(ranked_items)
    data["auralia_source"] = data.get("auralia_source", "spotify_api")
    print(f"AURALIA Spotify search source={data['auralia_source']} query={q}")

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
    offsets = (0, _spotify_search_limit)[:2]

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

    return await _fallback_spotify_search(query)


async def _spotify_search_with_params(
    *,
    client: httpx.AsyncClient,
    token: str,
    original_query: str,
    search_query: str,
    offsets: tuple[int, ...],
    market: str | None,
    allow_fallback: bool,
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
                fallback = await _fallback_spotify_search(original_query)
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


async def _fallback_spotify_search(query: str) -> dict[str, Any]:
    query_lower = query.lower()
    catalog = _fallback_catalog_for_query(query_lower)
    image_urls = await _spotify_oembed_images([track["id"] for track in catalog])

    return {
        "auralia_source": "fallback",
        "tracks": {
            "href": "",
            "limit": len(catalog),
            "next": None,
            "offset": 0,
            "previous": None,
            "total": len(catalog),
            "items": [
                _fallback_track_json(
                    {
                        **track,
                        "image_url": image_urls.get(track["id"]),
                    },
                    index,
                )
                for index, track in enumerate(catalog)
            ],
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
            {"id": "7nUlyv5E5Pz8dsbUd9Y0Ec", "title": "The Climb", "artist": "Miley Cyrus"},
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
            {"id": "7jLQrCCYdK8A0YcYwHFeQ3", "title": "Location Unknown", "artist": "HONNE, BEKA"},
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
        "7nUlyv5E5Pz8dsbUd9Y0Ec": {"title": "The Climb", "artist": "Miley Cyrus", "duration_ms": 235000},
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


def _rank_mainstream_tracks(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    unique_items: list[dict[str, Any]] = []

    for item in items:
        track_id = str(item.get("id", ""))
        if not track_id or track_id in seen:
            continue
        seen.add(track_id)
        unique_items.append(item)

    playable = [
        item
        for item in unique_items
        if item.get("is_playable", True)
        and not item.get("is_local", False)
        and _release_year_is_allowed(item)
        and _looks_like_real_song(item)
    ]

    ranked = sorted(
        playable,
        key=lambda item: (
            int(item.get("popularity") or 0),
            int(item.get("album", {}).get("release_date", "0")[:4] or 0),
        ),
        reverse=True,
    )

    return ranked


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

    popularity = item.get("popularity")
    if isinstance(popularity, int) and popularity < 35:
        return False

    text_parts = [
        str(item.get("name", "")),
        str(album.get("name", "")) if isinstance(album, dict) else "",
        " ".join(
            str(artist.get("name", ""))
            for artist in artists
            if isinstance(artist, dict)
        ),
    ]
    searchable = " ".join(text_parts).lower()
    blocked_terms = {
        "karaoke",
        "tribute",
        "cover version",
        "instrumental",
        "piano version",
        "lofi",
        "lo-fi",
        "sped up",
        "slowed",
        "nightcore",
        "8d audio",
        "podcast",
        "episode",
        "meditation",
        "frequency",
        "white noise",
        "rain sounds",
        "sleep sounds",
        "tabata",
        "workout timer",
    }
    return not any(term in searchable for term in blocked_terms)


def _constrain_spotify_query(query: str) -> str:
    query = query.strip()
    if not query:
        return query

    lowered = query.lower()
    if "english" not in lowered:
        query = f"english {query}"
    return query
