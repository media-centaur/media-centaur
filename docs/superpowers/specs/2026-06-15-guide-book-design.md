# Guide book — design

**Date:** 2026-06-15
**Status:** design approved in brainstorming; pending spec review → campaign

## Summary

An in-app, book-style guide at its own route (`/guide`), broken into chapters that
explain how Media Centaur works — every feature, how to get the most out of it, and
enough of the machinery that an operator can diagnose their own problems. Chapters are
authored as portable markdown so a future campaign can generate the wiki from them, but
**that exporter is out of scope here** (see Follow-ups).

**Primary objective — discovery, not just reference.** The guide must actively surface
capabilities the user likely *isn't* using or doesn't know exist (e.g. what ffprobe
unlocks, track-selection behavior, relink-on-move, pursuits, the Console). It should help
the user get the most out of what's already offered — not merely document what they
already click. Every chapter is written with "what here is the reader probably missing?"
in mind.

## Decisions (settled in brainstorming)

1. **Authoring format — markdown-as-source.** Each chapter is a markdown file in the
   repo with light frontmatter (title, part, slug, order). Portable prose: rendered to
   styled HEEx in-app now, and exportable to other formats (e.g. the wiki) later. Not
   hand-written HEEx (locked to the app) and not Elixir structs (heavy to author).

2. **Destination — standalone `/guide` route.** Its own page with the book layout.
   **Deep-linkable** per chapter (`/guide/<slug>`). The *only* entry point for now is
   a link on **Settings → System** — deliberately **not** in the main nav. It can be
   linked from error/empty states later.

3. **Reader — the enthusiast operator** (matches the Status-page persona). Peer-to-peer,
   assumes technical comfort. Explains the machinery (the pipeline, pursuits, the
   deriver model), not just the buttons. Mastery is the bar: cover every little feature
   in enough detail that a motivated user can truly master the software.

4. **Reading UI — text-first.**
   - Sticky left sidebar: Parts → Chapters (same nav pattern as Settings).
   - Reading pane on the right.
   - Long chapters get a right-hand "on this page" outline of section headings.
   - Inline cross-links between chapters (markdown links resolving in-app and in wiki).
   - Title/section **filter** (client-side). Full-text body search is a later add.
   - Rich elements expressible in markdown and styled in-app, plain in wiki: callouts
     (note / tip / warning), keybinding chips, code blocks, tables.
   - **Imagery: minimal / text-first for v1.** Markdown can carry images, so screenshots
     are a clean later extension; not in scope now.

5. **Voice — the `writing-copy` skill** (`~/.claude/skills/writing-copy`). Built and
   tested during this planning session from the user's live rewrites. Plain, factual,
   reader-first; build antecedents before relying on them; comprehensibility over
   precision; true names; "we" for the makers with honest hedging; **permeable to the
   codebase** — chapters link to relevant source on GitHub and to the issue tracker
   where the operator can act.

6. **Source links must be stable.** Link to a path on `main` (no line numbers) so they
   survive refactors. The export task can stamp the current version.

## Architecture

Two units, each with one job:

- **Guide content** — `priv/guide/*.md`. Frontmatter: `title`, `part`, `slug`, `order`.
  Pure prose + the agreed rich elements. No app code.
- **Guide renderer (in-app)** — loads/parses the markdown, builds the chapter index
  (parts → chapters), renders a chapter to styled HEEx, resolves cross-links and the
  on-this-page outline. Backs `GuideLive` at `/guide` and `/guide/:slug`.

Open implementation question for the plan phase: markdown→HEEx rendering approach
(existing dependency vs. compile-time vs. runtime parse) and how rich elements
(callouts, kbd chips) are expressed in markdown. Decide in `writing-plans`.

## Table of contents (ship all over the campaign)

**Part I — Orientation**
1. What Media Centaur is (and isn't) — one app, one SQLite DB, no cloud, no transcode
2. First run — media dirs, TMDB, mpv, ffprobe (the setup tour, explained)
3. A tour of the app — what each page is for

**Part II — Your library**
4. How identification works — the ingestion pipeline (discovery → import → image), the parser, TMDB matching
5. The library model — movies / shows / seasons / episodes / extras, file tracking
6. The Review queue — what lands there and why
7. Moving & relinking media — how files stay attached when they move
8. Languages, subtitles & track selection

**Part III — Watching**
9. Playback — driving mpv, the couch UI
10. Watch history & progress
11. Keyboard & gamepad navigation

**Part IV — Acquisition (optional)**
12. Search & download — TMDB-first, Prowlarr, download clients
13. Pursuits — how a grab is tracked end to end
14. Release tracking & Upcoming

**Part V — Operating it / under the hood**
15. The mental model — bounded contexts, PubSub, the deriver model
16. Observability — the Console and the Status page
17. Troubleshooting — how to figure out what's going wrong
18. Settings, configuration & backups
19. Updates, retention & running as a service

## Per-chapter workflow (mastery requires accuracy)

Each chapter is an independent work unit, landed one (or few) per commit:

1. **Study the source first** — read the relevant modules/settings/keybindings; do not
   write from memory. Mastery-level claims must be true. While reading, note the
   **non-obvious or under-advertised capabilities** the chapter should surface (the
   discovery objective) — these are easy to miss if you only document the visible UI.
2. **Draft the chapter** in `priv/guide/`, applying the `writing-copy` skill.
3. **Render check** in-app at `/guide/<slug>`.

## Scope boundaries

- v1 is text-first; screenshots and full-text search are explicit later extensions.
- No main-nav entry; Settings → System is the sole entry point for now.
- Wiki generation is **not** part of this work (see Follow-ups). The hand-maintained
  wiki stays as-is; nothing here touches it.

## Follow-ups (separate campaigns / later)

- **Wiki exporter** — its own campaign. A `mix guide.export` (or similar) that generates
  the wiki from `priv/guide/*.md`, plus migrating/retiring the hand-maintained pages.
  The markdown-as-source format here is what makes it possible; don't design it now.
- Screenshot-rich chapters (markdown already supports images).
- Full-text search over chapter bodies.

## Not clobbering concurrent work

Another agent is editing `presentable_queries.ex`, `subtitles.ex`, and their tests.
This feature touches none of those — new files only (`priv/guide/`, a new `GuideLive`,
a `mix guide.export` task, a Settings → System link). Coordinate before any shared-file
edits.
