---
title: The review queue
part: Your library
slug: the-review-queue
order: 6
---
Most files identify themselves. The ones that can't end up in the Review queue, where you
make the call instead of letting the app guess. Understanding what lands here — and why —
turns the queue from a chore into a useful signal.

## What lands here, and why

A file is sent to Review whenever identification can't reach the confidence bar on its own:

- **A low-confidence match** — the best TMDB candidate scored below the auto-approve
  threshold (see [How identification works](/guide/how-identification-works)).
- **No results** — TMDB returned nothing for the parsed title.
- **An unresolved tie** — several candidates scored equally and the parsed year didn't pick
  a clear winner.

In every case the file is held, not guessed at. Nothing low-confidence enters your library
behind your back.

## Resolving an item

Each item shows what the parser read — the title, year, and any season/episode — alongside
the TMDB candidates it found, with their scores. From there you can:

- **Accept** one of the suggested matches, which sends the file on to be imported exactly as
  an auto-matched file would.
- **Search TMDB yourself** when none of the suggestions are right, and pick the correct
  title by hand.
- **Dismiss** the item if it shouldn't be in your library at all.

## Fixing a title that was matched wrong

The queue is for files that *haven't* been imported yet. For a title already in your library
that got identified incorrectly, re-match it from its detail page: that removes the entry
and sends its files back through Review, where you can match them correctly.

> [!TIP]
> An empty Review queue isn't the only good state — a *small, occasional* one is healthy
> too. It's where oddly-named files surface. If the same kind of name keeps landing here,
> that's worth an [issue](https://github.com/media-centaur/media-centaur/issues/new) so the
> parser can learn it, rather than matching it by hand every time.

In short: Review is the safety valve for anything identification isn't sure about — accept,
search, or dismiss; and re-match from the library for anything already imported wrong.
