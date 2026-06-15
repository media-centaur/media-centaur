---
title: Pursuits
part: Acquisition
slug: pursuits
order: 13
---
A pursuit is a download tracked from grab to landed-in-library. It's not a single torrent —
it's a durable goal ("get these episodes at this quality") that persists across attempts,
keeps an event timeline, and only finishes when the files actually arrive. Understanding
pursuits is how you diagnose anything that grabbed but never showed up.

## States

A pursuit moves through a small set of states:

- **active** — at least one piece is still being sought or downloaded.
- **satisfied** — everything landed.
- **partial** — some pieces landed, the rest gave up (a terminal, partial success).
- **exhausted** — nothing acceptable was found and attempts ran out.
- **cancelled** — you stopped it.

The pursuit's state is always a summary of its pieces, which matters most for the next part.

## One pursuit, many units

A season pack or a multi-episode plan is **one** pursuit with a per-unit board — one unit per
episode. A single release can cover many units (a pack covers a whole season), and as files
land, each one checks off exactly its unit. The pursuit stays active until every unit is
satisfied. Units land in whatever order the files arrive — an out-of-order pack that lands
S03E07 before S02E01 satisfies each unit by its TMDB identity, not by guessing from the
filename, so a composite pursuit is never wrongly cancelled by an early landing.

## How a download is paired and lands

To connect your pursuit to the actual download (and then to the file on disk), the app
matches on the strongest signal it has, in order: the torrent's **infohash**, then the
**content path** on disk, then the **TMDB identity** (season and episode), and finally the
**release name**. This ladder is why a tracker-prefixed torrent name (`www.x.org - …`) or a
usenet grab with no hash still pairs correctly.

When a file finishes and the pipeline imports it into your library, the pursuit is satisfied
by a fast notification path — and, as a safety net, a reconciler re-checks every tick, so
even if that notification is missed the file is found on the next pass by its content path or
TMDB identity.

## What you can do mid-pursuit

From a pursuit's modal you can **cancel** it (which also removes its in-flight downloads from
the client), **change the target** to pivot to a different release, or **request a decision**
to pick from fresh alternatives. The app also acts on its own: a download with zero seeders
is auto-cancelled, and a stalled one can be flagged for your decision.

> [!TIP]
> To diagnose a pursuit that grabbed but never landed: open it and read the **timeline** —
> it logs every grab, stall, and decision. For a composite, expand the **unit board** to see
> which episode is stuck and on what release. If it's `active` but nothing is downloading,
> it's **awaiting your decision** — pick an alternative from the decision card. And if the
> file clearly landed but the pursuit is still active, the reconciler will catch it on the
> next tick, by content path even when the torrent name never matched.

In short: a pursuit is a durable, per-unit download goal that pairs to your client by the
strongest identity available and lands files into the library on a fast path with a
reconciler behind it — and its timeline and unit board are where you look when one is stuck.
