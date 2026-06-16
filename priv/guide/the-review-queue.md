---
title: The review queue
nav_label: Review queue
part: Your library
slug: the-review-queue
order: 6
---
Most files identify themselves. The ones that can't land in the Review queue, where you make
the call instead of letting the app guess. Nothing low-confidence enters your library behind
your back.

## What lands here

| Reason | What happened |
|---|---|
| Low-confidence match | The best TMDB candidate scored below the auto-approve threshold (see [How identification works](/guide/how-identification-works)) |
| No results | TMDB returned nothing for the parsed title |
| Unresolved tie | Several candidates scored equally and the parsed year didn't break the tie |

Each item shows what the parser read — title, year, any season/episode — alongside the TMDB
candidates it found and their scores.

## What you can do

| Action | Result |
|---|---|
| Accept a match | Imports the file under that title, exactly as an auto-matched file would |
| Search TMDB | Search by hand and pick the correct title when none of the suggestions fit |
| Dismiss | Removes the item — for files that shouldn't be in your library at all |

## Fixing a title matched wrong

The queue holds files that *haven't* been imported. For a title already in your library that
was identified incorrectly, re-match it from its detail page: that removes the entry and sends
its files back through Review to be matched correctly.

> [!TIP]
> A small, occasional queue is healthy — it's where oddly-named files surface. If the same
> kind of name keeps landing here, that's worth an
> [issue](https://github.com/media-centaur/media-centaur/issues/new) so the parser can learn
> it, rather than matching it by hand every time.
