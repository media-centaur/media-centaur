---
status: accepted
date: 2026-09-14
---
# Tracking is the bookmark and two switches over one record

Supersedes UIDR-036 rules 1, 4 (its bookmark exception) and 5. Design: `docs/superpowers/specs/2026-09-14-tracking-controls-design.md`.

## Context and Problem Statement

The seven-way strip (Ignore · Off · List · Follow · Ask · Grab · Default) put three questions on one control and offered two exits as if they were levels. List restated what the bookmark already said; Off and Ignore were exits, not answers; Follow meant nothing for a title already out; and Ask, Grab and Default were three spellings of one per-title policy that already existed globally as the Download button's planning mode.

## Decision Outcome

Chosen option: "three controls for three questions", because a person's intent about a title is on my list / keep its calendar / plan its releases, in that order, and who commits a plan is one preference.

1. **The bookmark is membership.** It lists a title and removes it at any rung. Removal deletes the record and the calendar derived from it; re-listing derives it again.
2. **Track release dates is Follow.** A Settings-kit toggle row, shown only while a release is ahead: an unreleased movie, or any series. Its description says what Coming up will show.
3. **Auto-grab is Grab.** A toggle row shown for any title the library does not own outright. Its description says whether a drop downloads without asking or parks for approval, as the person's planning mode says, and where that is set.
4. **The ladder is Ignored · List · Follow · Grab.** No per-title grab policy; `PlanningMode.approval_policy/1` stamps every plan. The global "When a release appears" setting is deleted.
5. **Ignore belongs to the Feed.** It stays the Feed card's verb and leaves the title view.

### Consequences

* Good, because each control reads as a yes/no the person recognises, and the Download button and auto-grab ask first under the same rule.
* Good, because two global answers to one question became one.
* Bad, because the global setting can no longer move every title at once; auto-grab is set per title.
* Bad, because nothing notifies on a tracked release — Coming up is the surface. A follow-up pill source is scheduled in the spec.
