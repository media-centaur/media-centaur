---
status: accepted
date: 2026-05-22
---
# Language codes are canonicalized to ISO 639-2/T at the boundary; one comparison helper

## Context and Problem Statement

The playback language-preferences subsystem compares language codes
that arrive from three independent sources, each using a different
ISO 639 representation:

* **TMDB** stores `original_language` as ISO 639-**1** (2-letter:
  `"en"`, `"ja"`, `"fr"`).
* **mpv**'s `track-list` reports embedded-stream languages as ISO
  639-**2** (3-letter: `"eng"`, `"jpn"`, `"fra"`), and may emit either
  the bibliographic or terminologic 3-letter form (`"fre"` vs `"fra"`).
* **User policy** (`understood_languages`, per-entity overrides) is
  free-typed and could be either form.

These representations are not string-equal but denote the same
language. The `TrackResolver` originally compared them with raw `==`,
which silently failed across forms. The "original audio" branch never
matched for any TMDB-sourced non-English entity, and conditional
subtitle selection skipped the correct track.

The failure mode was insidious:

1. It was **invisible for the common English-only case** — both sides
   happened to spell English the same way in the paths that mattered,
   so the bug only surfaced for foreign-language content, which the
   default test fixtures didn't exercise (they used matching forms on
   both sides of every comparison).
2. The first fix sprinkled an `Iso639.equal?/2` tolerant comparison at
   each call site. That is **fragile by construction** — it relies on a
   developer remembering to use the helper at every new comparison.
   We proved the fragility immediately: the fix missed one of five
   sites (`pick_main_subtitle`'s inline filter), so foreign-audio films
   still showed no subtitles until a second fix.

The root problem is not "we compared wrong" — it is "the same value
exists in multiple representations and comparisons are scattered."

## Decision Outcome

Chosen option: **canonicalize every language code to 3-letter ISO
639-2/T at the system boundary, and funnel all in-resolver comparisons
through a single helper.**

Concretely:

* **`MediaCentaur.Playback.Iso639`** is the one place that knows the
  code table. `normalize/1` maps any common 2-letter or bibliographic
  form to the canonical terminologic 3-letter form; `equal?/2` and
  `find_match/2` build on it.
* **Boundary normalization** — every code is normalized at the point it
  enters the subsystem, so only the canonical form exists downstream:
  * `LanguageContext.parse_track_list/1` normalizes each `Track.lang`
    as it parses mpv's track-list.
  * `LanguageContext.init/1` normalizes `original_language` when it
    reads the entity.
  * `LanguagePolicy.load/0` normalizes `understood_languages`.
* **One comparison helper** — `TrackResolver.matches_lang?/2` is the
  sole language-equality site. The previous four/five scattered
  comparisons (`find_by_lang`, `find_forced`, `find_sub_in_lang`,
  `pick_main_subtitle`) all route through it. It uses `Iso639.equal?/2`
  as belt-and-suspenders: with boundary normalization in place the
  inputs are already canonical, but the helper would still match if a
  raw code ever slipped past the boundary.
* **Test fixtures use mixed forms deliberately** — boundary tests
  assert `parse_track_list` turns `"en"`→`"eng"` and `"ja"`→`"jpn"`,
  policy-load turns `["en","es"]`→`["eng","spa"]`, and a resolver
  regression test feeds TMDB-style `"ja"` against mpv-style track tags.
  The old suite passed *through* the bug precisely because it used
  matching forms; representative fixtures are part of the guarantee.

A custom Credo check that flags raw `.lang ==` comparisons was
considered and **rejected**: AST-matching "is this a language
comparison" is brittle and noisy, and it polices the symptom rather
than removing the failure mode. Boundary normalization makes the
mismatch structurally impossible instead.

### Consequences

* **Good.** The cross-representation mismatch class becomes
  structurally impossible: a `"en"` code cannot reach a comparison,
  because it is rewritten to `"eng"` the moment it enters. Even raw
  `==` would now be correct downstream.
* **Good.** New comparison sites have exactly one correct way to be
  written (`matches_lang?/2`). The "forgot the helper at one of five
  sites" failure can't recur for the resolver.
* **Good.** Stored overrides, captured selections, and displayed codes
  are all canonical, so they round-trip consistently across re-rips
  and different release groups that tag the same language differently.
* **Bad.** `Iso639`'s table covers ~40 common languages plus the usual
  bibliographic alternates. An unknown code passes through unchanged;
  if mpv and TMDB disagree on an obscure language outside the table,
  the mismatch can still occur. Extending the table is the remedy, and
  the single-helper structure means the fix lands in one place.
* **Bad.** Normalizing `understood_languages` on *load* (not on save)
  means the value the user typed and the value used internally can
  differ in form. When the Settings UI lands it should normalize on
  save too, so what the user sees matches what is stored.

## Pointers

* Modules: `MediaCentaur.Playback.Iso639`,
  `MediaCentaur.Playback.LanguageContext`,
  `MediaCentaur.Playback.LanguagePolicy`,
  `MediaCentaur.Playback.TrackResolver`
* Feature plan: `~/.claude/plans/let-s-think-about-a-elegant-meteor.md`
* Related principle: [ADR-045 file-presence ownership](2026-05-17-045-file-presence-ownership.md)
  applies the same "make the bad state unrepresentable at the boundary"
  approach to file presence.
