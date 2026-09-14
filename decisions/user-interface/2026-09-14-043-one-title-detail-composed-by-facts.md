---
status: accepted
date: 2026-09-14
---
# One title detail, composed by facts

Supersedes UIDR-035 rules 1 and 2 (two surfaces split by whether the title has files) and the page-membership clause of its 2026-09-14 amendment; keeps its rules 3–6. Amends UIDR-019 (one overlay) and UIDR-023 (the member is the subject). Design: `docs/superpowers/specs/2026-09-14-title-detail-unification-design.md`.

## Context and Problem Statement

UIDR-035 put a title with files in the library modal and a title without files in the title modal, as a step. The deep-links work then made the TMDB identity the title modal's subject, and the split survived only in code: an owned title opened one way from Home and another from Discovery with an "In library" link as the bridge; the same seven fact loads were written in both hosts; two addresses, two view-models, two renderers, two nav overlays, two stories. The library modal is the more refined of the two, and its quality is the constraint.

## Decision Outcome

Chosen option: "one modal for one TMDB identity on every page, its sections present by facts", because files are one more fact about a title — like a rung, a calendar, a friend's review or a plan in flight — not a different surface.

1. **The subject is the TMDB identity.** The address is `?title=<media_type>-<tmdb_id>` on Home, Library, Discovery and Incoming alike, with `view` and `activity` as today. A library entity with no identity (a video object, an unmatched container) is the residue and keeps a modal on `?entity=<uuid>`; an entity address whose entity has an identity canonicalises to the title address.
2. **A collection is addressed through its member.** The modal is the selected member movie's panel (UIDR-023); the member's identity is the subject, the rail patches between members, and `?movie=` retires. A collection has no tracking block of its own: the collection id was written as a `:movie` ref, and nothing read it.
3. **One view-model, one builder, facts only.** `Title.Detail` gains the library half — the typed entry, the subject, the selected member, the files — as one struct that is nil for an unowned title; `Title.Logic.title_detail/2` builds it from facts. Nothing derived lives on it: the primary action, the tracking card's presence and a series' Download scope are computed where their sections mount, by one rule each. The snapshot resolves by identity: the open detail's own, the intent's, the owner's entity, the page's copy, then TMDB. No ad hoc `Title.new!`. The activity a title was opened from is read by identity too.
4. **One host, declared subscriptions.** `Live.TitleDetailHost` loads local facts synchronously on open (ADR-051), lets remote facts land by identity as owned asyncs (ADR-049), and declares every topic the modal needs through one idempotent subscribe door, so a page that needs the same topic declares it too and no message arrives twice. Per-opening state is one struct, reset on every subject change.
5. **The library modal's presentation is the trunk.** `DetailPanel`'s block structure renders both halves: for an owned title, exactly what it renders today, verified before and after on the same titles at the same viewport; for an unowned title, the Download control (or the acquisition state) in the play card's place, the note and the overview in the prose column, no content list, content-fit height unless a tracking card renders. The facet strip is dropped for both, on the library's 2026-08-08 reasoning.
6. **One overlay.** `detail`, with a `detail_menu` region for an open glass menu; absent regions are skipped by entry order and by every edge.
7. **One vocabulary.** Library event names stay; title-only controls drop their prefix; `set_rung`, `review_open` and `close_title` are the shared names.

### Consequences

* Good, because a link to a title opens the same modal on every page, and an owned title shows Play wherever it is met.
* Good, because every fact is loaded once, refreshed by identity, and the mount-time facts that never refreshed are gone.
* Good, because the collection's movie-ref collision (tracking-controls spec, incoherence 12) is closed at the seam rather than worked around.
* Bad, because roughly 180 tests and 51 story variations change address or fixture in one campaign; the branch does not merge until the bar holds.
* Bad, because a collection can no longer be tracked as a whole until it has an identity of its own; that design is scheduled, not silent.
* Bad, because an unowned title has no cast view until a follow-up feeds one from the preview.

### Implementation notes (2026-09-14)

Landed on the branch `title-detail-unification` in five phases the same day. Three points the design left open were settled in code: the residue's view-model is a `Title.Detail` with `ref` and `title` nil and the library half as its one fact; a switch to another member of the open collection is the same document, so the modal's state and sub-view stay (a rail pick keeps Cast); an address the library cannot open — an entity without a present file, a title nothing holds and TMDB cannot fetch — is abandoned with a flash on both forms, and a titled `?entity=` deep link opens the title in place on the dead render and canonicalises on the join. The subscribe door is `MediaCentaurWeb.Live.Subscriptions`, enforced by Credo MC0011 (`LiveSubscriptions`). The bar was judged from `mockups/title-detail-unification-bar/` captures at 1920×1080.
