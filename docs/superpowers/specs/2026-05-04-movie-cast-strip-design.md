# Movie Cast Strip — Design

**Date:** 2026-05-04
**Status:** Approved (pending user review of written spec)

## Problem

The movie detail modal shows hero, title, metadata, description, and play actions, but nothing about who is *in* the movie. TMDB already returns full cast data on every `/movie/{id}` fetch (the client appends `credits` to the response), but `Mapper.from_movie/1` only extracts the director and discards the entire `cast` array.

Users browsing their library want to see cast at a glance and click through to learn more about an actor.

## Scope

In scope:

- New JSON column on `library_movies` storing the cast list as fetched from TMDB.
- TMDB mapper extension to extract `cast` alongside the existing `director`.
- New `CastStrip` LiveView function component placed at the bottom of the movie detail modal (horizontal scrollable strip of poster-style cards).
- Click on a card opens TMDB's person page (`themoviedb.org/person/{id}`) in a new tab.
- One-shot maintenance action to backfill cast for already-imported movies via re-running the existing TMDB metadata refresh.
- Hotlinked profile photos (no local image-pipeline integration).

Out of scope (deliberate):

- TV-series cast (movies only for v1).
- Crew beyond director (already covered).
- A first-class `Person` entity, person pages, or per-actor filmography. No persons table, no credit join table — the user explicitly said this is not the goal.
- Local caching of profile photos. Hotlinking matches the existing pattern in `ReviewLive` and avoids 10× growth in the local image cache for content that rarely changes.
- Cast-membership-based search or filtering.
- Per-movie cast editing in the UI.

## Data model

Add an embedded JSON column to `MediaCentarr.Library.Movie`:

```elixir
field :cast, {:array, :map}, default: []
```

Each map entry has the shape:

```elixir
%{
  "name" => "Max Schreck",
  "character" => "Count Orlok",
  "tmdb_person_id" => 1234,
  "profile_path" => "/abc123.jpg",  # may be nil
  "order" => 0                       # TMDB importance ranking
}
```

Stored sorted by `order` ascending. Store all entries TMDB returns (typically 20–40 — JSON column is cheap; truncating loses information). The display layer caps at the visible cards; horizontal scroll exposes the rest.

String keys (not atoms) so the column round-trips through SQLite/JSON without atom conversion friction. The component normalizes on read.

## TMDB extraction

`MediaCentarr.TMDB.Mapper` already destructures `movie["credits"]` for `extract_director/1`. Add `extract_cast/1`:

```elixir
def extract_cast(%{"cast" => cast}) when is_list(cast) do
  cast
  |> Enum.sort_by(& &1["order"])
  |> Enum.map(fn person ->
    %{
      "name" => person["name"],
      "character" => person["character"],
      "tmdb_person_id" => person["id"],
      "profile_path" => person["profile_path"],
      "order" => person["order"]
    }
  end)
end

def extract_cast(_), do: []
```

Wire it into the existing `from_movie/1` so the field flows through the import pipeline as part of the normal mapping step. No new TMDB calls.

## Component

New module `MediaCentarrWeb.Components.Detail.CastStrip` in `lib/media_centarr_web/components/detail/cast_strip.ex`.

```elixir
attr :cast, :list, required: true,
  doc: "list of cast maps from Movie.cast — see Movie schema for shape"

def cast_strip(assigns)
```

- Renders nothing if `cast` is empty.
- Section label "Cast" matching the existing detail-panel label style.
- Horizontal flex container with `overflow-x-auto`, gap 12px, scrollbar styled subtly.
- Each card: 110px wide, 140px-tall photo (2:3 aspect ratio), name (12px bold), character (11px muted) below.
- Photo `src`: `https://image.tmdb.org/t/p/w185{profile_path}`. The w185 size is TMDB's standard "headshot" — sharp at 110px display width on retina without overfetching.
- Click target: anchor wrapping the whole card, `target="_blank" rel="noopener"`, `href="https://www.themoviedb.org/person/{tmdb_person_id}"`.
- Cards with no `profile_path` show an SVG silhouette placeholder using existing icon styling.
- Cards with no `tmdb_person_id` (defensive) render as non-interactive divs.

Slotted into `DetailPanel` as the last visible content, only when `entity.type` is `:movie`. Movies inside a `MovieSeries` (rendered via the content list) do not yet show cast — adding it there is a follow-up.

## Backfill

Existing movies have `cast: []` after the migration. To populate:

- Add a one-shot maintenance action in `MediaCentarr.Maintenance` (extend an existing "refresh metadata" action if one is already present — check before adding) that enqueues a TMDB re-fetch for every movie with empty `cast` and a non-nil `tmdb_id`.
- Surfaced as a "Refresh metadata for all movies" button on the maintenance/library admin page.
- Idempotent on subsequent runs: only acts on movies still missing cast. A user wanting to force-refresh a populated movie uses the existing per-entity rematch flow.

## Migration

Single migration adds the column. SQLite represents JSON via the `:map` Ecto type:

```elixir
def change do
  alter table(:library_movies) do
    add :cast, :map
  end
end
```

No DB-level default. The schema field declares `field :cast, {:array, :map}, default: []`; the changeset coerces `nil` (existing rows post-migration) to `[]` so the component never has to defend against `nil`. The plan should verify the exact null/empty handling against an existing JSON-array field elsewhere in `MediaCentarr.Library` before locking it in.

## Storybook

Add a `CastStrip` story with three variations:

- **Default** — 8 cast members, all with photos.
- **Mixed** — some with photos, some without (silhouette fallback).
- **Empty** — empty cast list (component renders nothing).

Use generic placeholder names (`Sample Actor One`, etc.) per the no-real-titles policy. Profile photos can use `placehold.co` or be left as silhouettes.

## Testing

- **Mapper test** (`test/media_centarr/tmdb/mapper_test.exs`): `extract_cast/1` orders by `:order`, drops nothing, returns `[]` for missing/malformed input.
- **Schema test**: round-trip `cast` through changeset and DB. Verify default `[]`.
- **Component test** (`test/media_centarr_web/components/detail/cast_strip_test.exs`):
  - renders nothing for empty cast,
  - renders one card per entry,
  - link href and `target="_blank"`,
  - silhouette fallback when `profile_path` is nil,
  - photo src uses `image.tmdb.org/t/p/w185`.
- **DetailPanel integration test**: movie with cast renders the strip; movie without cast does not.
- No Playwright E2E — the strip is passive content and offers no new user interactions beyond an external link.

## Observability

Cast extraction runs inside the existing TMDB metadata pipeline; failures and warnings flow through the existing `MediaCentarr.Log` calls. No new log component tag needed. If `extract_cast/1` ever returns malformed data, the changeset cast will surface it on import — the existing import-error reporting path handles surfacing.

## Open questions / non-decisions

None — all major decisions resolved during brainstorming:

- Hotlink vs cache: hotlink (matches `ReviewLive`).
- Person entity: not introduced (user explicitly opted out).
- Click destination: TMDB person page in new tab.
- TV scope: movies-only for v1.
