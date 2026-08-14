# Collections Are Filing, Not Content — Home-Feed Design Plan

> Design plan for [UIDR-025](../../decisions/user-interface/2026-08-14-025-collections-are-filing-not-content.md).
> Describes WHAT the surfaces should be, not how to build them.

## Problem Statement

The home feed treats a movie collection as a watchable thing: Continue
Watching shows one collection card with a blended saga percentage and
keeps it there until every member is watched; Recently Added and the hero
banner surface the collection entity with franchise-level filler art and
description. Under the declared semantics — TV series are one long work,
movies are self-contained, collections are shelves that keep related
movies together — all three surfaces are asserting semantics collections
don't have. UIDR-023 already made members first-class destinations inside
the modal; the feed contradicts it.

## Design Objectives

* Every activity surface speaks in the true unit of activity: the movie.
* The collection manifests only where filing is the job: the library
  shelf card and the modal's poster rail.
* Delete progression vocabulary for collections (blended bar, "N / M
  movies") rather than restyling it.
* Preserve one component family per idiom — one strip card anatomy, one
  cinematic modal panel family (UIDR-023). These surfaces are under
  continuous improvement; kind-specific forks drift.

## User-Facing Behavior

* **Continue Watching**: pausing mid-movie in a collection puts *that
  movie's* card on the strip — its backdrop, its logo, its within-movie
  progress bar — indistinguishable in anatomy from any other movie card.
  No collection marker; the rail provides context after the click.
  Finishing a member with the next unstarted leaves nothing on the
  strip. Two paused members produce two cards.
* **Recently Added**: a newly imported member movie appears as itself
  (own poster); the collection entity never appears here.
* **Hero banner**: member movies are hero candidates on their own art
  and synopsis; the collection entity is not a candidate.
* **Clicking**: any card presenting a member movie opens the collection
  modal pre-selected on exactly that movie. The resume-target ladder
  applies only when entering without a selection (library shelf card).
* **Library view and modal rail**: unchanged. The shelf card, the
  poster rail, its watched checkmarks and per-member progress underline
  all stay as shipped in UIDR-023.

## Acceptance Criteria

- [ ] A collection appears on Continue Watching only via member movies
      with incomplete partial progress; the between-movies state yields
      no card.
- [ ] Strip card art and progress bar are the member movie's own; no
      blended saga percentage renders anywhere.
- [ ] Clicking a member-movie card (strip, recently added, hero) opens
      the collection modal pre-selected on that movie — including when
      two members are in progress simultaneously.
- [ ] Recently Added and the hero banner never present the collection
      entity; member movies appear individually with their own art and
      metadata.
- [ ] Missing member art falls back per the UIDR-021 ladder (collection
      art → text title).
- [ ] TV series presentation is unchanged on all three surfaces;
      singleton-collection movies continue presenting as movies.
- [ ] Cards still leave the strip live on completion and drive-availability
      events (existing refresh triggers).

## Anti-patterns

- **Progression creep**: no "Part N of M", no "N / M movies", no up-next
  nudge on any activity surface. The dormant collection label is
  deleted, not surfaced.
- **Card-type fork**: no collection-flavored strip card component; one
  card anatomy for the whole strip.
- **Modal fork**: the collection modal stays the parameterized
  standalone-movie panel; pre-selection extends its entry contract, it
  does not spawn a variant panel.
- **Batch rollup**: no "collapse same-batch siblings" in Recently Added;
  it reintroduces collection-as-content.
- **Policy re-inference**: no surface re-derives movie-vs-collection;
  routing goes through the single resolver (ADR-050).

## Deferred

* "Up next in the saga" as a recommendation, if ever wanted, is a
  different surface with different semantics — not Continue Watching.
* Any other surface showing collection-aggregate progress (audit
  separately; none known on the home feed after this change).
* Recently Added flood from bulk-imported large collections — accepted
  as truthful; revisit only if real usage hurts.

## Decisions

* [UIDR-025](../../decisions/user-interface/2026-08-14-025-collections-are-filing-not-content.md)
  — collections are filing, not content.
* [UIDR-023](../../decisions/user-interface/2026-08-13-023-movie-first-collection-modal.md)
  — movie-first collection modal; this plan extends its click contract
  with explicit pre-selection.
* [ADR-050](../../decisions/architecture/2026-05-23-050-presentable-resolver.md)
  — the resolver keeps sole authority over movie-vs-collection; UIDR-025
  narrows its consumers to filing surfaces and click routing.

## Implementation Directive

Run the `unify_design` pass before writing code: design the affected
slice greenfield, diff against the existing seams (the resolver, the
UIDR-023 panel parameterization, the home-feed fetchers), and converge —
no parallel representations. The modal componentization is the critical
axis: these modals are continuously improved, and any drift between the
kinds is a defect of the implementation, not a follow-up.
