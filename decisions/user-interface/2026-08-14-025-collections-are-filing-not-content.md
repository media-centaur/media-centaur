---
status: accepted
date: 2026-08-14
---
# Collections are filing, not content — activity surfaces speak in movies

## Context and Problem Statement

A movie collection keeps related movies together on one shelf card; a TV series is different in kind, because its episodes are continuations. The home feed contradicted that: Continue Watching showed the collection as one in-progress thing with a blended saga percentage, Recently Added surfaced the collection when a member arrived.

## Decision Outcome

Collections manifest in exactly two places, the library shelf card and the collection modal's poster rail; every activity surface presents member movies as movies. A collection has no completion fraction anywhere.

1. **Continue Watching**: one card per member movie with incomplete progress, carrying that movie's art and bar. Finishing a member removes the collection's presence entirely; a shelf earns no "up next" nudge.
2. **Recently Added and the hero**: member movies appear individually; the collection entity never does. Hero eligibility is evaluated per movie.
3. **Click contract**: any surface presenting a member opens the collection modal pre-selected on that movie; the UIDR-023 resume-target ladder applies only when the modal is entered without a selection.
4. **ADR-050's possession-count resolver** stays the single authority for movie-vs-collection, but its scope narrows to filing surfaces and click routing.
5. **One component family per idiom**: the strip keeps one card anatomy for all title kinds; the collection modal remains the parameterised movie panel of UIDR-023.

### Consequences

* A bulk-imported large collection floods Recently Added with one poster per member. A "collapse same-batch siblings" rollup is rejected: it reintroduces collection-as-content through the side door.
