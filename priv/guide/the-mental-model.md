---
title: The mental model
part: Operating it
slug: the-mental-model
order: 15
---
Everything so far has described what the app does. This chapter is about how it's put
together — enough of the shape that you can reason about it and predict how it behaves when
something looks off. Three ideas carry most of it: bounded contexts, the three-pillar state
model, and the deriver model.

## Bounded contexts

The backend is split into about a dozen isolated contexts — Library, Pipeline, Watcher,
Review, Playback, Acquisition, Release Tracking, Watch History, Settings, Console, Retention.
Each owns its own data and behaviour, and they don't call into each other's internals; they
communicate by broadcasting events. The split is enforced at compile time, so the isolation
is real, not just a convention. The core loop is small: the Watcher sees files, the Pipeline
identifies and enriches them, the Library stores them, and the UI shows them.

For you, the payoff is that pieces fail and recover independently. A stuck Pipeline can be
restarted without touching the Library; a wrong value in one context can be rebuilt without
risking another.

## The three-pillar state model

At any moment a piece of state lives in exactly one of three places:

- **The database** is the ground truth — your library, progress, settings, kept in SQLite.
  Writes go here synchronously; a crash and restart loses nothing.
- **In-memory projections** are fast, pre-shaped snapshots each page reads from, so rendering
  doesn't re-query the database every time. This is why the UI is quick.
- **PubSub** is the real-time glue. When the database changes, a projection rebuilds and
  broadcasts; the page hears it and re-reads. No polling — updates just arrive.

The pages read from projections, never the database directly. The practical consequence: an
update is *eventually* consistent on a roughly one-tenth-of-a-second horizon. If you change
something and the screen doesn't reflect it instantly, that window is why; if it never
catches up, a projection worker has likely crashed and a restart rebuilds it from the
database.

## The deriver model

Some of what the app stores is **identity** — which title a file is, its TMDB id — expensive
to work out and stable once known. The rest is **derived** — values computed from other data,
like an extra's name read from its filename or a show's release coverage. Identity is frozen
once established (a rescan never re-hits TMDB for a known file). Derived data is treated as
recomputable: it can always be rebuilt from its inputs.

That single decision is why destructive-looking maintenance is safe, and why the app
self-heals. A parser bug that mis-named 200 extras isn't a crisis and doesn't need hand-edited
SQL — once the rule is fixed, the names re-derive (on the next scan, or via a maintenance
button). Clearing the database and re-scanning rebuilds everything from the files themselves.
See [ADR-057](https://github.com/media-centaur/media-centaur/blob/main/decisions/architecture/2026-06-14-057-derived-data-is-recomputable.md).

> [!TIP]
> This is the mental shortcut for most "that looks wrong" moments: ask whether the value is
> *derived*. If it is — artwork, names, coverage, a projection — the fix is to recompute it,
> not to repair it by hand. The app is built so recomputing is always safe.

In short: isolated contexts that talk by broadcasting, a database-of-record fronted by fast
projections wired together with PubSub, and derived data that's always rebuildable — which is
what makes the app fast, self-healing, and safe to operate on. The full picture is in
[docs/architecture.md](https://github.com/media-centaur/media-centaur/blob/main/docs/architecture.md).
