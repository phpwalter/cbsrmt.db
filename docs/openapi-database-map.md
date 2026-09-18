# OpenAPI to PostgreSQL Function Map

The uploaded OpenAPI 3.0.3 contract is the authoritative HTTP resource contract. PostgreSQL functions return JSON using the same field names and collection envelopes so the HTTP service does not need to rename database fields.

| HTTP endpoint | PostgreSQL function |
|---|---|
| `GET /ping` | `api.ping()` |
| `GET /episodes` | `api.get_episodes(page, limit, search, year, genre, cast, writer, sort, order)` |
| `GET /episodes/{episodeNumber}` | `api.get_episode(episodeNumber)` |
| `GET /episodes/{episodeNumber}/cast` | `api.get_episode_cast(episodeNumber)` |
| `GET /episodes/{episodeNumber}/writers` | `api.get_episode_writers(episodeNumber)` |
| `GET /cast` | `api.get_cast(page, limit, search)` |
| `GET /cast/{castId}` | `api.get_cast_member(castId)` |
| `GET /cast/{castId}/episodes` | `api.get_cast_episodes(castId, page, limit, sort, order)` |
| `GET /writers` | `api.get_writers(page, limit, search)` |
| `GET /writers/{writerId}` | `api.get_writer(writerId)` |
| `GET /writers/{writerId}/episodes` | `api.get_writer_episodes(writerId, page, limit, sort, order)` |
| `GET /genres` | `api.get_genres()` |
| `GET /genres/{genreId}/episodes` | `api.get_genre_episodes(genreId, page, limit, sort, order)` |
| `GET /search` | `api.search_catalog(q, page, limit)` |
| `GET /users` | `api.get_users(page, limit)` |
| `GET /users/{userId}` | `api.get_user(userId)` |
| `PATCH /users/{userId}` | `admin.update_user(userId, merge_patch_jsonb)` |
| `DELETE /users/{userId}` | `admin.delete_user(userId)` |

## Contract details

- `episode_number` is the stable public episode identifier.
- Pagination is one-based `page` / `limit`, default limit 5, maximum 100.
- Episode filters `genre`, `cast`, and `writer` accept names as defined by OpenAPI.
- Episode sort values are exactly `episode_number`, `episode_name`, and `broadcast_date`.
- Episode responses use `broadcast_date` and `thumbnail`; the physical catalog column remains `original_air_date`.
- Episode thumbnails are derived as `/public/assets/episodes/{episode_number}.png`.
- Audio responses always contain an `available` boolean and use OpenAPI's `media_type` property.
- Cast and writer resources expose `id`, `first_name`, `last_name`, and `display_name`.
- Genre resources expose `id` and `name`; legacy source genre 0 is intentionally not emitted because OpenAPI requires IDs >= 1.
- Search returns the OpenAPI grouped shape: `data.episodes`, `data.cast`, and `data.writers`.
- User PATCH accepts JSON Merge Patch content as `jsonb`.
- PostgreSQL does not issue or validate OAuth tokens; the HTTP/auth layer enforces the OpenAPI security scopes before calling protected functions.
- Rate-limit headers, HTTP status mapping, RFC 7807 error serialization, and the real server URL remain HTTP-service responsibilities.
