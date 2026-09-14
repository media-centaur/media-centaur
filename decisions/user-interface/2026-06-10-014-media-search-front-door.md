---
status: accepted
date: 2026-06-10
---
# Media-search front door — omnibox, coverage language, and imagery discipline

## Context and Problem Statement

Media search is the primary acquisition path, but the downloads page grew around the release-name search, with the search box at the bottom and no UI for the targeting → draft plan → planner → commit backend.

## Decision Outcome

1. **The omnibox is the page.** A hero field searches TMDB as you type; the raw release search is a mode flip of the same box, not a tab and not a modal. Both modes answer flat in the page.
2. **The plan flow is one URL-driven modal** (`?plan=…`): targeting picker → live coverage board → approval footer, no wizard steps. The durable draft plus the URL make every stage refresh-safe; closing mid-plan leaves a resumable draft. Movies skip the picker for a one-card confirm. Picker presets ("Everything aired", "Continue from my library", "Latest season") write into tri-state season checkboxes, and checkbox state is the only source of truth; in-library episodes render greyed with an "In library" chip, unaired seasons inert. Verbs name the goal, not the step: a search row and the movie confirm say *Download*; only the board's footer, where a proposal exists to accept, says *Approve plan*.
3. **One coverage language.** Unit cells in season rows carry every state (`CellVocabulary`: searching, claimed, a fused capsule where one pack covers a run, below preference, gap, in library), and the same cells appear as the segmented progress row on composite pursuit cards and in the pursuit modal's unit board, so approving a plan reads as the board carrying over into the pursuit. The board body is now the diagnosis layout of [UIDR-029](2026-08-31-029-plan-board-diagnosis.md).
4. **Imagery is identity.** Title-doored cards (draft plans, TMDB-door pursuits) carry a desaturated, scrimmed backdrop banner at banner height, never hero height; query-door pursuits stay plain rows with a "release search" chip. Semantic status colours remain the brightest accents on every card. Artwork sourcing follows [UIDR-021](2026-08-11-021-cinematic-frame-artwork-ladder.md).

### Consequences

* The omnibox's dual mode is one learnable control; release mode is exactly the old UI.
* Synthetic banners for titles without artwork vary with the title's name.
