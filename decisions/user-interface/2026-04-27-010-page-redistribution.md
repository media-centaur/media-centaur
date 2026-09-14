---
status: accepted
date: 2026-04-27
---
# Page redistribution: Watch / System sidebar groups + dedicated Home, Library, Upcoming, History

## Context and Problem Statement

The original `/` did three jobs behind a `?zone=` param: a Continue Watching strip, the catalog grid, and an upcoming-releases zone. Those are three mental modes (resume, browse, anticipate) on one page. Watch History existed at `/history` but was hidden, and the sidebar mixed viewing surfaces with operator surfaces in one flat list.

## Decision Outcome

1. **Each mental mode is its own page.** `/` is Home, the one assembled cinematic page (hero, Continue Watching, shelves). `/library` is the catalog browser alone. `/history` is Watch History. Upcoming became its own page and was later merged with Downloads into Incoming ([UIDR-015](2026-07-11-015-incoming-page.md)).
2. **The sidebar has two groups.** **Watch** carries the viewing pages at full weight (Home, Library, Discovery, Incoming, Apps today); **System** (Status, Review, Settings) is demoted with `.sidebar-link-system`, smaller and dimmer.
3. **Old zone URLs redirect.** `HomeLive.handle_params/3` sends `?zone=library` to `/library` and `?zone=upcoming` to `/incoming`, forwarding any other params; other zone values stay on Home.

### Consequences

* Home assembles data from several contexts and is the only page that does; every other page is single-purpose.
* Two sidebar link weights to maintain.
