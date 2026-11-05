---
status: accepted
date: 2026-11-05
---
# Review → Identity is a bulk list matched by selection

## Context and Problem Statement

Review → Identity grouped waiting files by their top-level folder and judged each group as one decision. A download client lands most releases in a folder of their own, so six episodes of one show arrived as six groups, and matching them meant six searches. The grouping could not be made reliable by a better key either: a release named with a year, a broadcaster's tag ("Signed"), a country code or a typo splits any automatic key, and every split costs the reader another search.

Choosing a search result also only staged the match; approving it was a second step on a different button.

## Decision Outcome

Chosen option: "a flat list the reader ticks, with an action bar for what is ticked", because the reader's selection cannot split the way a computed group does. The owner chose this layout from three mockups (list/detail regrouped by parsed title, one card per question, and the bulk list).

1. **One list, no groups.** Every open item, sorted by parsed title, year, season and episode, with a divider where the parsed title changes. A divider ticks the rows beneath it and decides nothing; a bad parse only puts two blocks next to each other.
2. **The selection is the unit of decision.** Ticking a row, a divider, or every row the filter shows (the header tick) gathers what the parser split. The filter matches the parsed title and the file name.
3. **The action bar acts on the ticked rows.** It appears while something is ticked. Its search starts from the first ticked row's parsed title and runs at once; pressing a result matches and imports every ticked row in one step. Accept best guess approves each ticked row under its own guess when every one has one. Dismiss and Delete take the arm gesture.
4. **A reader's answer is remembered.** Matching by hand records the title for the name the files were read as; later files with that name never reach Review. Settings → Media Import lists the answers with Forget.
5. **Statuses are a view, not sections.** Waiting, Importing and Dismissed are a segmented control; a not-added item waits with its reason.
6. **Keyboard and gamepad.** The rows are a tree zone: SELECT ticks, and DOWN off the last row or RIGHT from any row reaches the bar, so acting never means walking the list. BACK from the bar returns to the rows.

### Consequences

* Good, because one show's episodes are one decision however they were downloaded.
* Good, because a repeat download of an unfindable name never waits for a person again.
* Bad, because a dense table is harder to drive on the TV than one card per question; the zone layout (rule 6) is what keeps it workable there.
