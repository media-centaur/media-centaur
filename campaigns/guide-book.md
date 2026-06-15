---
status: planning
started: 2026-06-15
last_updated: 2026-06-15
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

Planning. Design spec approved
([`docs/superpowers/specs/2026-06-15-guide-book-design.md`](../docs/superpowers/specs/2026-06-15-guide-book-design.md)).
The `writing-copy` voice skill it depends on is built and tested. No feature code yet.

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

Concrete, ordered. Phase 0 proves the whole vertical slice before any chapter farming.

1. ✅ **Phase-0 TDD plan written** — [`docs/superpowers/plans/2026-06-15-guide-book-phase-0.md`](../docs/superpowers/plans/2026-06-15-guide-book-phase-0.md). Rendering resolved: Earmark, compile-time parse.
2. **Phase 0 — infrastructure + pilot chapter.** Execute the Phase-0 plan, task by task.
   - Guide content loader/index over `priv/guide/*.md` (frontmatter: `title`, `part`, `slug`, `order`).
   - Markdown→HEEx renderer with the rich elements (callouts, kbd chips, code, tables) + cross-link resolution + on-this-page outline.
   - `GuideLive` at `/guide` and `/guide/:slug`; sidebar (Parts → Chapters) + reading pane, following the Settings nav pattern; client-side title filter.
   - Settings → System link to `/guide`.
   - **Pilot chapter: "How identification works" (ch. 4)** authored end-to-end — exercises source links, a callout, and a cross-link to the Review queue chapter.
   - `mix precommit` green; live render check at `/guide/how-identification-works`.
3. **Phase 1 — Part I (Orientation):** chapters 1–3.
4. **Phase 2 — Part II (Your library):** chapters 5–8 (4 shipped as pilot).
5. **Phase 3 — Part III (Watching):** chapters 9–11.
6. **Phase 4 — Part IV (Acquisition):** chapters 12–14.
7. **Phase 5 — Part V (Operating it / under the hood):** chapters 15–19.

Chapters land one (or a few) per commit; each is independent. A part may span sessions.

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
