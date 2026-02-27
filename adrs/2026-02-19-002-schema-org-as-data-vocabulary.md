---
status: accepted
date: 2026-02-19
---
# Use Schema.org as data vocabulary

## Context and Problem Statement

The media manager handles movies, TV series, video games, and other media types. Each needs a consistent field vocabulary for serialization over Phoenix Channels and storage in the database. Inventing a custom schema risks ambiguity, gaps, and perpetual bikeshedding over field names.

## Considered Options

* Schema.org vocabulary with JSON-LD serialization
* Custom field names designed for this application
* Dublin Core metadata terms

## Decision Outcome

Chosen option: "Schema.org vocabulary with JSON-LD serialization", because schema.org provides a large, well-maintained vocabulary for media (`Movie`, `TVSeries`, `VideoGame`, `VideoObject`, `ImageObject`) with established field semantics. External metadata sources (TMDB, Steam, IGDB) map cleanly onto it. The format is human-readable, git-diffable, and works with standard JSON tooling.

### Consequences

* Good, because field names (`name`, `datePublished`, `contentUrl`, `genre`, `director`, `duration`, `containsSeason`, `episodeNumber`) are immediately recognizable
* Good, because new media types can be added by looking up the corresponding schema.org class
* Good, because the UI and backend share the same vocabulary without a translation layer
* Bad, because some schema.org conventions feel heavyweight for a single-user media library (e.g., wrapping ratings in `AggregateRating` objects)
* Bad, because schema.org does not cover every field we need — app-specific extensions require explicit documentation in `DATA-FORMAT.md`
