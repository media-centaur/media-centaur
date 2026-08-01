---
status: accepted
date: 2026-08-01
---
# Needs attention — one problem-only section for acquisition capability faults

## Context and Problem Statement

When Prowlarr's indexers are failing or backed off, `/api/v1/search` still
returns `200 []` — indistinguishable from a genuinely empty result. Observed
live (2026-08-01): a dead VPN tunnel failed the only enabled indexer, Prowlarr
snoozed it, and the plan modal reported *"1 not available right now"* and
*"Searched: The Magician — 0 found"* while 62 releases existed. The false
"0 found" also invited the wrong next action ("Track these later") and was
recorded into the search corpus as fresh negative knowledge.

Separately, the Incoming page had grown two independently-invented
problem-only surfaces: the **Storage** section (escalates from a header
subtitle to a card section when a drive runs low) and the
**ConnectivityBadge** (download-client outage pill, quiet when healthy). A
third bespoke surface for indexer health would entrench the pattern of every
subsystem inventing its own warning chrome.

## Decision Outcome

Chosen option: **degraded-search honesty at the decision point, plus one
generalized "Needs attention" section**, because the sharpest failure is the
plan result lying, and because the page's problem-only surfaces are all the
same idea — capability degradations of the acquisition pipeline (search →
grab → download → land) — and deserve one consistent home.

Concretely:

1. **The plan modal never presents a blind search as a completed search.**
   When the search ran while search capability was degraded
   (Prowlarr unreachable, or every enabled indexer backed off), the gap
   banner says the search couldn't check availability — not "not available
   right now" — and the activity line stops claiming "0 found".
2. **The Storage section generalizes into "Needs attention".** Same slot,
   same half-wide glass cards, same bookkeeping voice (the 2026-07-11 owner
   call — never a page-wide alarm band). Card kinds at launch, worst-first:
   Prowlarr unreachable (error), search blind — all enabled indexers backed
   off or none enabled (error), search degraded — some indexers backed off
   (warning), drive low (existing storage severity). Each card states what's
   wrong and when/how it recovers ("retries ~01:42").
3. **Silence is the healthy state.** The section is absent (not empty) when
   nothing is wrong; the calm single-drive storage summary stays in the
   header subtitle. Never a green "search healthy" badge — the
   ConnectivityBadge lesson.
4. **One health backbone.** Persistent conditions feed the ADR-054
   `:subsystem` incident track (composed into the `acquisition` assessor);
   the Incoming section is a contextual renderer of the same assessment, and
   the Status page stays the durable record. A blind live search is also not
   recorded as fresh corpus knowledge (per `Corpus`'s own outage contract).

### Anti-patterns (explicitly rejected)

* **Notification center** — no feed, no dismiss/read state, no history.
  Conditions appear while true and vanish on recovery; history belongs to
  incidents/Status.
* **Green badges / healthy chrome** — the section only earns pixels when
  something is wrong.
* **Page-wide alarm band** — stays a section in the flow with the
  bookkeeping voice.

### Consequences

* Good, because "0 found" regains meaning: it now reliably implies the
  search actually ran against live indexers.
* Good, because future capability faults (e.g. absorbing the
  ConnectivityBadge's content) have an obvious home instead of new chrome.
* Good, because the corpus no longer caches outage-shaped false negatives.
* Bad, because indexer health is polled (30s while the page is open, plus at
  search time), so a fault can be up to one poll stale — accepted; the plan
  flow re-checks at the moment that matters.
* Bad, because Prowlarr's per-indexer back-off state is provider-specific;
  a future non-Prowlarr provider must map its own notion of "blind" into
  the same health struct.
