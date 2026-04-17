# Data Format Specification

Canonical reference for all JSON data formats in the Media Centarr system.

---

## Foundation: Schema.org + JSON-LD

All media entities use vocabulary from [schema.org](https://schema.org), serialised as [JSON-LD](https://json-ld.org/). This is the most important design constraint in the system.

- **Field names are schema.org property names.** `name`, `description`, `datePublished`, `contentUrl`, `genre`, `director`, `duration`, `containsSeason`, `episodeNumber`, and all others are schema.org properties. Do not rename them or invent alternatives.
- **`@type` is the schema.org class.** `"Movie"`, `"TVSeries"`, `"MovieSeries"`, `"VideoObject"`, `"ImageObject"`, `"PropertyValue"` are schema.org types. Use exact canonical capitalisation.
- **`@id` is a JSON-LD node identifier.** In this system it is a plain UUID (e.g. `"550e8400-e29b-41d4-a716-446655440004"`), not a full URI. It is the app-level stable key used for image directory names and cross-references.
- **The outer wrapper is app-specific.** The `{ "@id": ..., "entity": {...} }` envelope is not schema.org — it is a thin app container. The inner `entity` object is a valid schema.org node.
- **Before adding a field:** check [schema.org](https://schema.org) for an existing property and use it if one fits. Only introduce a non-schema.org field if there is no reasonable match, and document why.

**Why schema.org?** It provides a large, well-maintained vocabulary for media (Movie, TVSeries, MovieSeries, VideoObject, etc.) with established field semantics. External metadata sources (TMDB, Steam, IGDB, TVDB) map cleanly onto it. The format is human-readable, git-diffable, and works with standard JSON tooling without a specialised parser.

---

## Entity Data Schema

### Top-Level Structure

The library is represented as a JSON array of wrapped entities:

```json
[
  { "@id": "...", "entity": { "@type": "...", ... } },
  { "@id": "...", "entity": { "@type": "...", ... } }
]
```

### Wrapper Object

| Field | Type | Description |
|-------|------|-------------|
| `@id` | `string` (UUID v4) | App-level unique identifier; stable across updates |
| `entity` | `object` | A schema.org entity (see entity types below) |
| `progress` | `object` or `null` | Aggregated watch progress summary (see Entity Progress Summary in API.md) |
| `resumeTarget` | `object` or `null` | Display hint for what will play when the user hits "play" (see Resume Target below) |
| `childTargets` | `object` or `null` | Per-child display hints keyed by child UUID (see Child Targets below); `null` for single items |
| `lastActivityAt` | `string` (ISO 8601) or `null` | Most recent activity timestamp — newest of date added or last watched, across the entity and all its children (movies, episodes, extras) |

The `@id` UUID is the stable key used for image directory names and cross-references. It must not change once assigned.

---

### Entity Object

All entities have `@type` as their first field. Remaining fields follow the schema.org type definition.

#### Common Fields (all entity types)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `@type` | `string` | Yes | Schema.org type name (see supported types below) |
| `name` | `string` | Yes | Display title |
| `description` | `string` | No | Long-form text description |
| `datePublished` | `string` | No | Year or ISO date (`"2017"`, `"2017-10-06"`) |
| `genre` | `string[]` | No | Genre labels |
| `image` | `ImageObject[]` | No | Artwork references (see ImageObject below) |
| `aggregateRating` | `AggregateRating` | No | Numeric score |
| `identifier` | `PropertyValue[]` | No | External storefront IDs |
| `contentUrl` | `string` | No | Local file path used for playback actions |
| `url` | `string` | No | Remote info page URL (TMDB, etc.) |

---

### Supported Entity Types

#### Movie — `schema.org/Movie`

Additional fields:

| Field | Type | Description |
|-------|------|-------------|
| `director` | `string` | Director name |
| `duration` | `string` | ISO 8601 duration (`"PT2H44M"`) |
| `contentRating` | `string` | MPAA rating: `"G"`, `"PG"`, `"PG-13"`, `"R"`, `"NC-17"` |
| `hasPart` | `VideoObject[]` | Bonus features (extras, featurettes, behind-the-scenes) |

**Movie with Extras:**

```json
{
  "@id": "550e8400-e29b-41d4-a716-446655440030",
  "entity": {
    "@type": "Movie",
    "name": "Sample Movie One",
    "datePublished": "1967",
    "director": "Jacques Tati",
    "duration": "PT2H4M",
    "contentUrl": "/media/movies/Sample Movie One.1967.Criterion.1080p/Sample Movie One.mkv",
    "hasPart": [
      {
        "@type": "VideoObject",
        "name": "Like Home",
        "contentUrl": "/media/movies/Sample Movie One.1967.Criterion.1080p/Extras/Like Home.mkv"
      },
      {
        "@type": "VideoObject",
        "name": "Making Of",
        "contentUrl": "/media/movies/Sample Movie One.1967.Criterion.1080p/Extras/Making Of.mkv"
      }
    ]
  }
}
```

#### MovieSeries — `schema.org/MovieSeries`

A collection of related movies (e.g. "The Lord of the Rings", "John Wick"). Standalone movies remain top-level `Movie` entities; movies that belong to a series are always nested inside a `MovieSeries` entity via the `hasPart` property.

Additional fields:

| Field | Type | Description |
|-------|------|-------------|
| `director` | `string` | Series-level director (optional; individual movies may differ) |
| `hasPart` | `(Movie \| VideoObject)[]` | Child movies and series-level bonus features, discriminated by `@type`. Movies are sorted by position then `datePublished`; VideoObject extras follow after movies. |

Child `Movie` objects inside `hasPart` include an `@id` (UUID) field for unique identification (used as key in `childTargets`), plus the same fields as standalone `Movie` entities. They are sorted by position then `datePublished`.

`VideoObject` items in `hasPart` are series-level bonus features (extras, featurettes, behind-the-scenes). They use the same format as `Movie.hasPart` extras (see VideoObject below). The backend appends them after all child movies.

**MovieSeries with Extras:**

```json
{
  "@id": "550e8400-e29b-41d4-a716-446655440025",
  "entity": {
    "@type": "MovieSeries",
    "name": "Project B-ko",
    "datePublished": "1986",
    "genre": ["Animation", "Sci-Fi", "Comedy"],
    "hasPart": [
      {
        "@type": "Movie",
        "@id": "550e8400-e29b-41d4-a716-446655440026",
        "name": "Project B-ko",
        "datePublished": "1986",
        "duration": "PT1H24M",
        "contentUrl": "/media/movies/Project B-ko/Project B-ko.mkv"
      },
      {
        "@type": "VideoObject",
        "@id": "550e8400-e29b-41d4-a716-446655440027",
        "name": "The Found CD-ROM Video Disc",
        "contentUrl": "/media/movies/Project B-ko/Featurettes/The Found CD-ROM Video Disc.mkv"
      },
      {
        "@type": "VideoObject",
        "@id": "550e8400-e29b-41d4-a716-446655440028",
        "name": "Music of Project B-ko",
        "contentUrl": "/media/movies/Project B-ko/Featurettes/Music of Project B-ko.mkv"
      }
    ]
  }
}
```

Example (without extras):

```json
{
  "@id": "550e8400-e29b-41d4-a716-446655440020",
  "entity": {
    "@type": "MovieSeries",
    "name": "The Lord of the Rings",
    "description": "Peter Jackson's epic fantasy trilogy.",
    "datePublished": "2001",
    "genre": ["Fantasy", "Adventure"],
    "director": "Peter Jackson",
    "image": [
      {
        "@type": "ImageObject",
        "name": "poster",
        "url": "https://image.tmdb.org/t/p/original/...",
        "contentUrl": "/mnt/media/.media-centarr/images/550e8400-e29b-41d4-a716-446655440020/poster.jpg"
      }
    ],
    "aggregateRating": { "ratingValue": 8.9 },
    "url": "https://www.themoviedb.org/collection/119",
    "hasPart": [
      {
        "@type": "Movie",
        "name": "The Fellowship of the Ring",
        "datePublished": "2001",
        "director": "Peter Jackson",
        "duration": "PT2H58M",
        "contentRating": "PG-13",
        "description": "A meek Hobbit sets out on a journey...",
        "image": [
          {
            "@type": "ImageObject",
            "name": "poster",
            "contentUrl": "/mnt/media/.media-centarr/images/550e8400-e29b-41d4-a716-446655440020/fellowship-poster.jpg"
          }
        ],
        "aggregateRating": { "ratingValue": 8.8 },
        "contentUrl": "/media/movies/LOTR/fellowship.mkv"
      }
    ]
  }
}
```

#### TVSeries — `schema.org/TVSeries`

Additional fields:

| Field | Type | Description |
|-------|------|-------------|
| `numberOfSeasons` | `integer` | Total season count (from TMDB; may exceed the number of seasons with scanned files) |
| `containsSeason` | `TVSeason[]` | Embedded ordered list of seasons — **only includes seasons/episodes with scanned video files**, not all seasons from TMDB |

**TVSeason** (embedded; not a top-level wrapper entity):

| Field | Type | Description |
|-------|------|-------------|
| `@id` | `string` (UUID v4) | Unique identifier for this season |
| `seasonNumber` | `integer` | Season index, 1-based |
| `numberOfEpisodes` | `integer` | Episode count |
| `name` | `string` | Optional season title |
| `episode` | `TVEpisode[]` | Embedded ordered list of episodes |
| `hasPart` | `VideoObject[]` | Bonus features for this season (extras, featurettes) |

**TVEpisode** (embedded inside `episode[]`):

| Field | Type | Description |
|-------|------|-------------|
| `@id` | `string` (UUID v4) | Unique identifier for this episode; used as key in `childTargets` |
| `episodeNumber` | `integer` | Episode index, 1-based |
| `name` | `string` | Episode title |
| `duration` | `string` | ISO 8601 duration |
| `description` | `string` | Episode synopsis |
| `image` | `ImageObject[]` | Thumbnail images |
| `contentUrl` | `string` | Local file path for playback |

#### VideoObject — `schema.org/VideoObject`

No additional fields beyond the common set. Used for standalone entities (conference talks, clips, recordings) and as bonus features nested inside a Movie's `hasPart` array.

#### Unknown Types

Any `@type` not listed above is parsed generically. The UI renders all top-level string and number fields as metadata rows. No data is lost or rejected.

---

### Common Sub-types

#### ImageObject

Used in `image` arrays on all entity types and in TVEpisode.

```json
{
  "@type": "ImageObject",
  "name": "poster",
  "url": "https://image.tmdb.org/t/p/original/1E5baAaEse26fej7uHcjOgEE2t2.jpg",
  "contentUrl": "/mnt/media/.media-centarr/images/550e8400-e29b-41d4-a716-446655440004/poster.jpg"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `@type` | `"ImageObject"` | Always `"ImageObject"` |
| `name` | `string` | Image role: `"poster"`, `"backdrop"`, `"logo"`, `"thumb"` |
| `url` | `string` | Remote source URL — written by manager app, not read by UI |
| `contentUrl` | `string` or `null` | Absolute filesystem path to the cached image — read by UI. `null` while the image download is pending. Resolved from the relative database path by the serializer at push time. |

See [`IMAGE-CACHING.md`](IMAGE-CACHING.md) for directory conventions and role definitions.

#### AggregateRating

```json
{ "ratingValue": 8.0 }
```

| Field | Type | Description |
|-------|------|-------------|
| `ratingValue` | `number` | Score value (TMDB: 0–10, Metacritic: 0–100) |

#### PropertyValue (Identifiers)

Used in `identifier` arrays for external storefronts.

```json
[
  { "@type": "PropertyValue", "propertyID": "steam", "value": "1245620" },
  { "@type": "PropertyValue", "propertyID": "tmdb",  "value": "335984" }
]
```

| Field | Type | Description |
|-------|------|-------------|
| `@type` | `"PropertyValue"` | Always `"PropertyValue"` |
| `propertyID` | `string` | Storefront key: `"steam"`, `"tmdb"`, `"gog"`, `"igdb"`, `"tvdb"` |
| `value` | `string` | The external ID |

Identifiers are flattened for action template substitution as `identifier.{propertyID}` — e.g. `identifier.steam` resolves to `"1245620"`.

---

### Complete Entity Examples

**Movie:**

```json
{
  "@id": "550e8400-e29b-41d4-a716-446655440001",
  "entity": {
    "@type": "Movie",
    "name": "Sample Movie",
    "description": "A young blade runner's discovery of a long-buried secret.",
    "datePublished": "2017",
    "genre": ["Sci-Fi", "Drama"],
    "director": "Denis Villeneuve",
    "duration": "PT2H44M",
    "contentRating": "R",
    "image": [
      {
        "@type": "ImageObject",
        "name": "poster",
        "url": "https://image.tmdb.org/t/p/original/gajva2L0rPYkEWjzgFlBXCAVBE5.jpg",
        "contentUrl": "/mnt/media/.media-centarr/images/550e8400-e29b-41d4-a716-446655440001/poster.jpg"
      }
    ],
    "identifier": [
      { "@type": "PropertyValue", "propertyID": "tmdb", "value": "335984" }
    ],
    "aggregateRating": { "ratingValue": 8.0 },
    "contentUrl": "/media/movies/Sample Movie/movie.mkv",
    "url": "https://www.themoviedb.org/movie/335984"
  },
  "lastActivityAt": "2026-03-01T20:00:00Z"
}
```

---

### Resume Target

The `resumeTarget` field on the wrapper object tells the UI what will play when the user hits "play" on this entity. It enables display of hints like "Resume S2E3" or "Begin The Shadowy Sentinel" on entity cards without issuing a play command.

| Field | Type | Present when | Description |
|-------|------|-------------|-------------|
| `action` | `string` | Always | `"begin"` (start from beginning) or `"resume"` (continue from position) |
| `name` | `string` | Always | Display name of the target (episode name, movie name, or entity name) |
| `targetId` | `string` (UUID) | Series only | UUID of the child entity (episode or movie) that will play |
| `seasonNumber` | `integer` | TV Series only | Season number of the target episode |
| `episodeNumber` | `integer` | TV Series only | Episode number of the target episode |
| `ordinal` | `integer` | MovieSeries only | 1-based position of the target movie in the series |
| `total` | `integer` | MovieSeries only | Total number of playable movies in the series |
| `positionSeconds` | `float` | `action: "resume"` only | Position to resume from |
| `durationSeconds` | `float` | `action: "resume"` only | Total duration of the target |

`resumeTarget` is `null` when:
- The entity is fully completed (all episodes/movies watched)
- The entity would restart from the beginning (implies re-watch, not a natural "next" action)
- The entity has no playable content

**Examples:**

Movie, never watched:
```json
{ "action": "begin", "name": "Sample Movie" }
```

Movie, partial progress:
```json
{ "action": "resume", "name": "Sample Movie", "positionSeconds": 4500.0, "durationSeconds": 9840.0 }
```

TV Series, mid-watch:
```json
{ "action": "resume", "targetId": "ep-uuid", "name": "Who Is Alive?", "seasonNumber": 2, "episodeNumber": 3, "positionSeconds": 1200.5, "durationSeconds": 3600.0 }
```

MovieSeries, completed first movie:
```json
{ "action": "begin", "targetId": "movie-uuid", "name": "The Shadowy Sentinel", "ordinal": 2, "total": 3 }
```

---

### Child Targets

The `childTargets` field provides per-child resume hints so the UI can display watch state on individual episodes or movies within a series. It is a map keyed by child UUID.

Each value is either:
- `null` — the child is completed
- `{"action": "begin"}` — the child has no progress
- `{"action": "resume", "positionSeconds": X, "durationSeconds": Y}` — the child has partial progress

`childTargets` is `null` for single items (Movie, VideoObject) that have no children.

**Example (TV Series):**

```json
{
  "ep-uuid-1": null,
  "ep-uuid-2": { "action": "resume", "positionSeconds": 1200, "durationSeconds": 3600 },
  "ep-uuid-3": { "action": "begin" }
}
```

**Example (MovieSeries):**

```json
{
  "movie-uuid-1": null,
  "movie-uuid-2": { "action": "resume", "positionSeconds": 4500, "durationSeconds": 9000 },
  "movie-uuid-3": { "action": "begin" }
}
```

