---
title: The library model
nav_label: Library model
part: Your library
slug: the-library-model
order: 5
---
Once a file is identified, Media Centaur records it as a small set of related things rather
than a single row. Knowing the shape helps when you're deleting, moving, or wondering why
something appears the way it does.

> [!NOTE]
> Three words worth keeping straight: an **entry** is anything in your library — a movie,
> show, season, episode, or extra. (The code and the Console call the same thing an
> *entity*.) A **release** is something different: a specific downloadable version of a
> title, which lives in [Search & download](/guide/search-and-download), not here.

## What the library holds

At the top are the containers you browse:

- **Movies**, optionally grouped into a **movie series** (a saga or collection).
- **TV series**, which own **seasons**, which own **episodes**.
- **Video objects** — standalone videos (a concert, a documentary) that aren't a movie or
  an episode.
- **Extras** — featurettes, deleted scenes, and bonus features, attached to a movie, a
  series, a movie series, or a season.

These containers hold metadata: titles, descriptions, cast, ratings, artwork. They don't
hold a file path directly. Instead, a movie/episode/video object has one or more **playable
items**, and each playable item points at a **watched file** — the actual video on disk.
That indirection is what lets a single episode have more than one cut (a theatrical and a
director's cut), each tracked separately.

**Watch progress attaches to the playable item**, not the title — so two cuts of the same
film remember their positions independently.

## Files and presence

The link between a playable item and a real file is the watched file; whether that file is
currently on disk is tracked separately as its **presence**. This separation is deliberate:
when a drive unmounts, the file's presence goes stale but the library entry stays. Your
metadata, artwork, and progress survive a disconnected drive — see
[Moving & relinking media](/guide/moving-and-relinking-media).

When a file is genuinely gone, deletion cascades in order — progress, extras, episodes,
seasons, the title, its artwork, its identifiers — so nothing is left orphaned. A title
with no remaining files is removed; a title whose drive is merely offline is not.

## Artwork and identifiers

Artwork is stored per role — poster, backdrop, logo, thumbnail — one of each per title,
downloaded from TMDB and cached to disk. External identifiers (the TMDB id, and others)
are kept as their own records rather than columns on the title, which is what lets the same
TMDB number mean different things for a movie and a series without colliding.

> [!TIP]
> Extras are first-class, not decoration. A featurette in an `Extras` or `Featurettes`
> folder is tracked with its own presence and ordering and tied to its parent title — so it
> survives a move and re-links like anything else, rather than being re-scanned from scratch
> every boot.

In short: titles are containers of metadata; playable items and watched files connect them
to real files; presence is tracked apart from the entry so an offline drive never costs you
your library.
