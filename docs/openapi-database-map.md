# OpenAPI to PostgreSQL Function Map

| HTTP endpoint | Database function |
|---|---|
| `GET /episodes` | `api.get_episodes(...)` |
| `GET /episodes/{episodeNumber}` | `api.get_episode(episodeNumber)` |
| `GET /episodes/{episodeNumber}/cast` | cast projection from `api.get_episode(...)` |
| `GET /episodes/{episodeNumber}/writers` | writer projection from `api.get_episode(...)` |
| `GET /cast` | `api.get_cast(...)` |
| `GET /cast/{castId}` | `api.get_person(castId)` |
| `GET /cast/{castId}/episodes` | `api.get_cast_episodes(...)` |
| `GET /writers` | `api.get_writers(...)` |
| `GET /writers/{writerId}` | `api.get_person(writerId)` |
| `GET /writers/{writerId}/episodes` | `api.get_writer_episodes(...)` |
| `GET /genres` | `api.get_genres()` |
| `GET /genres/{genreId}/episodes` | `api.get_genre_episodes(...)` |
| `GET /search` | `api.search_catalog(...)` |

`episode_number` is the stable public identifier. Pagination is 1-based `page`/`limit`, default `limit=5`, maximum `100`.

Episode thumbnails are derived as `/public/assets/episodes/{episode_number}.png` and are not stored. Audio is optional metadata/stream URLs in `catalog.episode_media`; PostgreSQL never stores or serves audio bytes.
