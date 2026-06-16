---
status: in_progress
started: 2026-06-15
last_updated: 2026-06-16
---
# Guide book

## Goal

Build an in-app, book-style guide at `/guide` that teaches the enthusiast operator how
Media Centaur actually works — every feature in enough depth to master it, plus enough
of the machinery (the pipeline, pursuits, the deriver model, observability) to diagnose
their own problems. A primary objective is **discovery**: actively surface capabilities
the user likely isn't using or doesn't know exist (what ffprobe unlocks, track selection,
relink-on-move, pursuits, the Console) so they get the most out of what's already offered.
Chapters are authored as portable markdown and rendered in-app; the guide is reachable
only from Settings → System for now. Worth doing because the software rewards
understanding and there is currently no in-app place that explains it.

## Status

**All 19 chapters written and on `main` (unpushed); pending owner review before push.**
The infrastructure (Phase 0) plus every chapter across Parts I–V are committed: Orientation
(1–3), Your library (4–8), Watching (9–11), Acquisition (12–14), Operating it (15–19). Each
chapter was researched against current source, written to the `writing-copy` voice, carries
source/issue links, and surfaces under-used capabilities (the discovery objective). Full
`mix precommit` green (Elixir 5027/0, JS 540/0). Shipped in **v0.98.0**.

**Re-aimed 2026-06-16** (pushed to `origin/main`, ahead of the v0.98.0 tag): after comparing
against the wiki, all 19 chapters were re-shaped toward the **wiki's practical goal + reference
register** (tables, numbered steps, completeness) in the `writing-copy` voice — the practical
chapters (first-run, app tour, playback, keyboard/gamepad, release-tracking, troubleshooting,
settings, updates, review-queue, search-and-download) now lead with tables/steps; the
explanatory chapters (what-it-is, identification, library model, pursuits, mental model,
observability) keep their narrative. The reading-pane title **filter**, screenshots, and
full-text search remain deferred.

## Decisions made

* `2026-06-15` — Authoring format is **markdown-as-source** in `priv/guide/*.md` (portable prose, rendered to HEEx in-app). (spec §Decisions 1)
* `2026-06-15` — Standalone **`/guide` route, deep-linkable** per chapter (`/guide/:slug`); the **only** entry point is a Settings → System link, **not** the main nav. (spec §Decisions 2)
* `2026-06-15` — Reader is the **enthusiast operator** (Status-page persona); explain the machinery, mastery is the bar. (spec §Decisions 3)
* `2026-06-15` — Reading UI is **text-first**: chapter sidebar + reading pane + on-this-page outline + title filter; callouts / kbd chips / code / tables; **no screenshots in v1**. (spec §Decisions 4)
* `2026-06-15` — Voice governed by the **`writing-copy`** skill; chapters are **permeable to the codebase** (link to source on `main` + the issue tracker). (spec §Decisions 5–6)
* `2026-06-15` — **Wiki exporter is a separate future campaign**, explicitly out of scope here. (spec §Follow-ups)
* `2026-06-15` — Each chapter is **studied against the source before drafting** — no mastery claims from memory. (spec §Per-chapter workflow)
* `2026-06-15` — **Discovery is a primary objective**: chapters must surface under-used / unknown capabilities, not just document the visible UI. (spec §Summary)
* `2026-06-15` — Markdown rendered with **Earmark** (pure Elixir, AST), **not** MDEx (Rust NIF) — keeps the "no extra installs / no native code" promise. Parse at compile time. (Phase-0 plan §Tech Stack)

## Next steps

1. ✅ Phase 0 — infrastructure + pilot chapter (merge `d9ccce9b`).
2. ✅ Part I — Orientation (1–3), Part II — Your library (4–8), Part III — Watching (9–11), Part IV — Acquisition (12–14), Part V — Operating it (15–19). One commit per part.
3. **Owner review** of the 19 chapters, then **push `main`** (held per instruction).
4. After push: the chapters' GitHub source links resolve (they point at paths on `main`).

✅ **Setup-guide expansion shipped 2026-06-16** (pushed): the guide grew from 19 → **21
chapters** — new *Setting up acquisition* (Prowlarr + download clients, Part IV) and *Settings
reference* (complete per-setting enumeration, Part V), plus the TMDB-key detail (signup, env
var, rate limit, attribution) folded into First run. Orders renumbered; slugs stable. This
absorbs the wiki's setup/reference coverage, so the guide is now close to the complete single
source (install / macOS stay wiki-only — can't read an in-app guide before installing).

✅ **Content gaps closed 2026-06-16** (pushed): file-naming conventions added as a section in
*How identification works*, and a new *Running a large library* chapter (inotify watch limit,
big-import expectations, bounded housekeeping) — **22 chapters total**. The guide's content is
now complete vs. the wiki (install/macOS intentionally wiki-only).

Remaining deferred — **features, not content**: reading-pane title filter, screenshots,
full-text search; and the wiki exporter (separate campaign).

## Doc strategy

Direction set 2026-06-16: the target is **the wiki's practical goal and coverage, written in
the `writing-copy` voice** ("wiki goals + guide voice"). The voice flexes by register — dry,
complete reference/steps for task content; narrative only where understanding is the point.
This governs both future guide work and the eventual guide→wiki generation.

## Completion criteria

* All 19 chapters (spec §Table of contents) live at `/guide`, each deep-linkable at `/guide/:slug`.
* Sidebar (Parts → Chapters), reading pane, on-this-page outline, and title filter all work.
* Settings → System links to the guide; no main-nav entry.
* Every chapter follows the `writing-copy` voice and was studied against current source; source/issue links resolve.
* Each chapter surfaces at least the non-obvious capabilities in its area (discovery objective), not just the visible UI.
* `mix precommit` green; new components have stories (MC0009) if any function components are added.
* Wiki exporter explicitly **not** delivered (its own campaign).

## Pointers

* Spec: [`docs/superpowers/specs/2026-06-15-guide-book-design.md`](../docs/superpowers/specs/2026-06-15-guide-book-design.md)
* Phase-0 plan: [`docs/superpowers/plans/2026-06-15-guide-book-phase-0.md`](../docs/superpowers/plans/2026-06-15-guide-book-phase-0.md)
* Voice skill: `~/.claude/skills/writing-copy` (canonical: `~/src/knowledge/skills/writing-copy/SKILL.md`)
* Nav/layout precedent: `lib/media_centaur_web/live/settings_live.ex` (sidebar + section pattern), `setup_live.ex` (URL-driven steps, deep-linking)
* Settings entry point: `lib/media_centaur_web/live/settings_live/system_section.ex`
* Architecture context for "under the hood" chapters: `docs/architecture.md`, ADR-057 (deriver model)
