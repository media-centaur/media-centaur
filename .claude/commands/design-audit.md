---
description: Systematic design audit — visual language adherence, UIDR compliance, UX state coverage, and aspirational gap analysis against DESIGN.md.
argument-hint: "[page-or-component (optional)]"
allowed-tools: Read, Glob, Grep, Bash(mix compile *), mcp__chrome-devtools__list_pages, mcp__chrome-devtools__new_page, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__list_console_messages, mcp__chrome-devtools__lighthouse_audit, mcp__chrome-devtools__evaluate_script, mcp__chrome-devtools__take_snapshot
---

# Design Audit

You are performing a meticulous design audit of the Media Centarr backend UI.
Your goal is to find **concrete, evidence-based** design-language, UIDR-compliance,
and UX-coverage issues — not speculative polish suggestions. Every finding must
cite the exact file and line, quote the offending snippet, and propose a
specific fix.

**Brutal honesty is mandatory.** Do not soften findings, hedge with qualifiers,
or balance criticism with unearned praise. If the implementation drifts from
`DESIGN.md`, violates a UIDR, or ships a page without an empty state, say so
directly. A sycophantic audit is worse than no audit at all.

**Scope:** If `$ARGUMENTS` is provided, focus on that page, component, or file.
Otherwise, audit the full Phoenix LiveView UI under `lib/media_centarr_web/`.

**Strict lane.** This audit deliberately does NOT cover:

- **CSS/LiveView perf anti-patterns** (stream-item keyframes, conditional
  `backdrop-filter`, `reset_stream` overuse) — belongs to `/performance-audit`
- **DESIGN.md factual drift** (stale file paths, outdated module references,
  docs out of sync with code) — belongs to `/docs-audit`
- **Dead code, unused styles, duplication in logic** — belongs to
  `/engineering-audit`

If a finding clearly belongs in a sibling lane, **skip it**. Do not emit
"see also" cross-references.

**The cardinal rule: read the source.** Every design claim you verify must be
checked against actual component/LiveView files, not against other
documentation. Authority sources are `DESIGN.md`, the `decisions/user-interface/`
UIDR records, and `assets/css/app.css`. Everything else is audited against them.

---

## Phase 1 — Orientation

Load the authority layer before analysis.

1. Read `DESIGN.md` in full — the 12 UI principles, page architecture, component
   guidelines, and the `Planned Data Requirements` table.
2. Read every file in `decisions/user-interface/` matching
   `*-NNN-*.md` (UIDRs 001 through 008 as of writing; glob for any later ones
   the user may have added). Template file is `template.md` — skip it.
3. Read `assets/css/app.css` — note the theme block boundaries so Pass 3 can
   distinguish legitimate theme token definitions from hardcoded values in
   application CSS.
4. Glob `lib/media_centarr_web/components/*.ex` and
   `lib/media_centarr_web/live/*.ex` to build the target inventory.
5. Read `lib/media_centarr_web/router.ex` — extract the list of `live "/path"`
   routes for Pass 4's orphan check.

---

## Phase 2 — Analysis Passes

Work through each pass sequentially. For each pass, explore the relevant code
thoroughly. Do not guess — read the actual source and quote what you find.

### Pass 1 — Design philosophy adherence

Audit implementation against `DESIGN.md`'s 12 numbered UI principles:

1. **Readability top priority** — any place where density, color, or cleverness
   compromises legibility
2. **Function over form** — decorative elements with no functional purpose
3. **Color is signal** — color used for decoration rather than state; healthy
   UI that uses saturated color; problem UI that doesn't draw the eye
4. **Dark-first, light-right** — theme coverage drift; elements broken in one
   theme; hardcoded colors that ignore theme
5. **System fonts, monospace only for function** — custom web fonts; monospace
   used for aesthetic text; proportional fonts for file paths, UUIDs, or
   tabular numbers
6. **Dashboard as hub** — dashboard missing a key summary block listed in the
   DESIGN.md sections table; secondary pages trying to be hubs
7. **Separate concerns into pages** — mixed-concern pages; unrelated sections
   crammed together
8. **Live data feels alive** — pipeline/playback/watcher status that doesn't
   tick during activity; idle state that doesn't go quiet
9. **Unified visual language** — cards, badges, tables, or buttons that look
   like they came from a different design system than their siblings
10. **Balanced density** — Bloomberg-terminal walls of text; marketing-page
    whitespace bloat
11. **Cards for grouping** — grouped content that doesn't use the card pattern;
    ungrouped content wrapped in redundant card shells
12. **Collapsible sidebar** — sidebar collapse state loss; missing tooltip on
    collapsed state; content area not reclaiming horizontal space

Per-page narrative check: for each LiveView in
`lib/media_centarr_web/live/` (`dashboard_live`, `library_live`, `review_live`,
`settings_live`, `console_live`, `console_page_live`), assess in 1-2
sentences whether the page embodies the stated principles. A page that
obviously honors all 12 gets "No issues found." A page that drifts gets a
finding per drift.

### Pass 2 — UIDR compliance (mechanical)

For each UIDR, run a concrete grep-based violation scan. Each violation is a
separate finding.

#### UIDR-001 — File path display convention

**Rule:** File paths in the UI use the `.truncate-left` utility, a `title`
attribute with the full path, and a `<bdo dir="ltr">` wrapper around the text.

**Scan:**
- Grep for likely path-rendering sites: `<%=.*path%>`, `<.live_component.*path`,
  `<%= .*file.*%>`, and the `.ex` LiveView templates rendering
  `WatchedFile`, `Review.Pending*`, or anything with `.path` or `.filepath`.
- For each site, verify all three elements are present. Missing any of them is
  a finding.
- Raw paths rendered without a tooltip at all → **Critical**
- Tooltip present but end-truncation (`class="truncate"`) used instead of
  `truncate-left` → **Moderate**
- `truncate-left` without the `<bdo dir="ltr">` BiDi fix → **Moderate**

#### UIDR-002 — Badge style convention

**Rule:** Status/reason labels use plain colored text (`text-error`,
`text-warning`, `text-info`). Metric badges (confidence, counts) may use solid
fill. Type badges (Movie, TV, Extra) use `badge-outline` with no color override.

**Scan:**
- Grep for `badge-error`, `badge-warning`, `badge-info`, `badge-success`
  (solid fills) in `.ex` files.
- For each hit, determine whether the badge labels a *status/reason* (violation)
  or a *metric value* (allowed).
- Any solid-fill badge used for a review reason, entity state, or label →
  **Moderate**
- Type badges using a color override (e.g. `badge-outline badge-primary`) →
  **Minor**
- Status labels using `<.badge>` at all instead of plain `<span
  class="text-error">` → **Moderate**

#### UIDR-003 — Button style convention

**Rule:** Action buttons use `btn-soft` + semantic color. Destructive/dismiss
actions use `btn-ghost`. Solid-fill is acceptable only for `btn-primary` in
dominant-CTA contexts.

**Scan:**
- Grep for `btn-success`, `btn-info`, `btn-warning`, `btn-error`, `btn-accent`
  in `.ex` files.
- Any hit without a paired `btn-soft` → **Moderate** (washed-out text on
  glass surfaces is the documented failure mode)
- Destructive actions (delete, clear, discard, dismiss, abandon) using solid
  fills or semantic colors → **Moderate**
- More than one `btn-primary` on a single page → **Minor** (dilutes the
  "dominant CTA" semantics)

#### UIDR-004 — Human-readable durations

**Rule:** Durations rendered to users must use `Xh Ym` / `Xm` format via the
project's display helper in `LiveHelpers`. Raw ISO 8601 (`"PT3H48M"`) or raw
seconds (`3600`, `"3600s"`) must never reach the DOM.

**Scan:**
- Grep for `"PT` inside `.ex` files in `lib/media_centarr_web/` — if it
  appears in a template rendering (not inside `@moduledoc` / comments /
  schema definitions), it's a raw ISO 8601 leak → **Critical**
- Grep for `duration` or `runtime` fields being interpolated directly in HEEx
  without a formatting helper call → **Moderate**
- Grep for template strings containing numeric seconds concatenated with `"s"`
  or `" seconds"` that render duration-shaped data → **Moderate**

#### UIDR-005 — Playback card hierarchy

**Rule:** Playback summary card uses the three-row layout (header, identity
block with series/episode, progress row with state-colored bar). Bar color
matches state (`progress-success` playing, `progress-warning` paused). Idle
state shows "Idle" muted text with no progress bar.

**Scan:**
- Find the dashboard playback card component (likely in
  `components/upcoming_cards.ex` or inlined in `dashboard_live.ex`).
- Verify series name is rendered as its own line for TV state → missing →
  **Critical**
- Verify the progress bar uses state-conditional color classes → missing
  conditional → **Moderate**
- Verify idle state renders no progress bar (bar omitted when duration zero or
  absent) → **Minor**

#### UIDR-006 — Library two-zone layout

**Rule:** Library page has two zones — Continue Watching (default, modal
detail) and Library Browse (drawer detail). Zone switching uses `push_patch`
within a single LiveView, preserving loaded data. `DetailPanel` is shared
between the two shells.

**Scan:**
- Verify `library_live.ex` handles two zone states.
- Verify zone switching goes through `push_patch`, not remount → non-patch
  navigation → **Moderate**
- Verify Continue Watching uses `ModalShell` and Library Browse uses
  `DrawerShell` — transpositions are a **Moderate** finding. (Note: DESIGN.md
  currently says Library Browse uses ModalShell; UIDR-006 says DrawerShell.
  UIDR-006 is the authority; any DESIGN.md divergence is a docs-audit concern,
  not a design-audit finding.)
- Verify `DetailPanel` is a shared component rendered inside both shells →
  duplicated implementations → **Moderate**

#### UIDR-007 — Left wall enters sidebar

**Rule:** Pressing Left at index 0 of *any* horizontal navigation row (zone
tabs, toolbar, grid) enters the sidebar. Right from the sidebar restores
focus to the remembered context.

**Scan:**
- Read `assets/js/input/` nav-graph wiring for `library`, `review`,
  `dashboard`, `settings`, `console` pages.
- Any horizontal row registered in a page behavior without a left-exit edge to
  the sidebar → **Critical** (documented as a user spatial-model violation)
- Missing return-focus-restoration logic → **Moderate**

#### UIDR-008 — Baseline alignment for mixed-size text rows

**Rule:** Flex rows containing text items of different font sizes use
`items-baseline`. Text/control rows (label + toggle/checkbox/button) use
`items-center`.

**Scan:**
- Grep for `items-center` in `.ex` files inside flex rows that contain two or
  more text elements of different sizes (e.g. `text-base` label + `text-xs`
  mono value). Visual inspection of the template is required — not every
  `items-center` is wrong.
- Confirmed text/text mismatches → **Minor**
- Text/text rows with no `items-*` at all (default alignment drift) →
  **Minor**

### Pass 3 — Visual consistency

Scan for:

- **Hardcoded colors** — grep for `#[0-9a-fA-F]{3,8}`, `rgb(`, `rgba(`, `oklch(`
  in `.ex` files and in `assets/css/app.css` **outside the theme plugin block**
  (the theme definitions use `oklch` legitimately; application CSS should use
  `var(--color-*)` or Tailwind tokens). Each hit is **Minor** unless it also
  breaks theme response (e.g. a hex color that doesn't invert for light mode),
  in which case **Moderate**.
- **Hardcoded spacing/sizes** — grep for `style="` in `.ex` files. Inline
  styles setting color, padding, margin, width, height are candidates. A
  hardcoded px value where a Tailwind scale step would fit is **Minor**. Use of
  `style` for dynamic runtime values (progress bar width) is allowed.
- **Typography drift** — bare `font-size` declarations in custom CSS, or
  inconsistent `text-*` modifiers for equivalent content (e.g. one page uses
  `text-sm text-base-content/60` for secondary labels, another uses
  `text-xs opacity-70`). Pick one and flag the other. **Minor** each.
- **Duplicate component patterns** — the same card header, footer, or
  action-row shape implemented twice in different files. **Moderate** — each
  duplicate should become a shared function component.
- **Icon source inconsistency** — if the project uses Heroicons exclusively,
  flag any other icon library or inline SVG; if it uses a mix deliberately,
  skip this check.

### Pass 4 — UX state coverage & flow gaps

For each interactive LiveView in `lib/media_centarr_web/live/`, check:

- **Empty state** — what does the page render when there is no data? Search
  for `:if={}` or `cond do` branches handling empty collections. A page that
  renders nothing (blank area, no message, no call to action) when empty →
  **Critical**. A page that renders a minimal "no results" without designed
  empty state (illustration, affordance to trigger population) → **Moderate**.
- **Loading state** — for operations that take longer than ~100ms (database
  fetches in mount, API calls, scans), is there a skeleton, spinner, or
  `phx-loading-*` transition? Missing loading feedback on a slow path →
  **Moderate**.
- **Error state** — `assign_async` branches, `handle_info` failure messages,
  broadcast error payloads. Pages that silently swallow errors (no user-visible
  indication) → **Critical**.
- **Destructive confirmations** — grep `handle_event` callbacks for verbs like
  `"delete"`, `"clear"`, `"abandon"`, `"discard"`, `"overwrite"`, `"reset"`.
  Each destructive handler must be gated by either a confirmation dialog
  (`ModalShell`) or `phx-confirm` / `data-confirm`. Unguarded destructive
  actions → **Critical**.
- **Orphan pages** — cross-reference the router's `live "/path"` routes against
  the LiveView modules in `lib/media_centarr_web/live/`. Also check the
  sidebar navigation (find where nav links are rendered — likely
  `components/layouts.ex` or `core_components.ex`). A LiveView registered in
  the router but not reachable from the sidebar nav or any in-page link is
  orphan. **Moderate**.
- **Input system coverage** — pages with interactive content (cards, buttons,
  forms, toggles) that do not have `data-nav-*` attributes or a registered
  page behavior in `assets/js/input/behaviors/`. Grep the page template for
  any focusable without `data-nav-item` or equivalent. Keyboard/gamepad users
  stuck on a page → **Moderate**.

### Pass 5 — Aspirational gap analysis

Read `DESIGN.md`'s **Planned Data Requirements** table and every **Planned
additions** / **Planned** marker in the per-page sections. For each entry:

1. Determine whether the feature is implemented (search for evidence —
   relevant modules, assigns, template blocks).
2. If implemented, skip (no finding).
3. If partially implemented, flag as **Moderate** with specifics about what's
   missing.
4. If not implemented at all, flag as **Moderate** with the feature name,
   the DESIGN.md location, and the implementation notes from the table.

Also scan DESIGN.md's per-page sections for concrete claims that should exist
in the implementation:

- "Dashboard shows library stats, pipeline status, watcher health, external
  integrations, recent errors table, storage metrics, review summary,
  playback summary" — verify each section exists on the dashboard.
- "Collapsible sidebar with 200px expanded / 52px collapsed" — verify both
  widths and the persisted state.
- "Theme toggle in sidebar bottom" — verify placement.
- "Detail panel scroll behavior: header fixed, content list scrolls
  independently" — verify the library detail panel scrolls as described.

Each verifiable claim that does not match reality is a finding.

**Symmetry note:** this pass asks "does reality fulfill DESIGN.md's promises?"
`/docs-audit` asks "does DESIGN.md match reality?" A missing-but-promised
feature is a design-audit gap. An extra-but-undocumented feature is a
docs-audit drift. If you catch yourself about to flag the latter, stop — it
belongs to the sibling.

### Pass 6 — Live visual inspection (opportunistic)

This pass is **optional and runs only if** chrome-devtools MCP is available
**and** the dev server is reachable at `http://127.0.0.1:4001`.

**Availability probe.** Attempt `mcp__chrome-devtools__list_pages`. If the
tool is unavailable or the call fails with a connection error, skip the entire
pass and record a single note in the final summary: *"Pass 6 skipped: dev
server not reachable at 127.0.0.1:4001"*. Never error out; never block the
static passes.

**If available, run the following against each top-level page** (`/`,
`/review`, `/library`, `/settings`, `/console`):

1. **Navigate and screenshot.** `mcp__chrome-devtools__navigate_page` to the
   route, wait for the page to settle, `mcp__chrome-devtools__take_screenshot`.
   Use the screenshot as narrative evidence for findings.
2. **Console cleanliness.**
   `mcp__chrome-devtools__list_console_messages` — any error is **Critical**,
   any warning is **Moderate**. Quote the message text in the finding.
3. **Accessibility baseline.** `mcp__chrome-devtools__lighthouse_audit` with
   only the `accessibility` category enabled. Flag every individual audit that
   fails with its ID (e.g. `color-contrast`, `image-alt`, `label`,
   `focus-traversable`). Severity = **Critical** for blocker audits
   (`color-contrast`, `image-alt`, `label`, `button-name`, `link-name`),
   **Moderate** for others.
4. **Rendered contrast spot-check.** For each page, use
   `mcp__chrome-devtools__evaluate_script` to sample the primary text/background
   pairs:
   ```js
   const el = document.querySelector('h1, .text-base-content');
   const s = getComputedStyle(el);
   return { color: s.color, background: getComputedStyle(document.body).backgroundColor };
   ```
   Compute WCAG contrast ratio manually and flag anything below 4.5:1 for
   normal text or 3:1 for large text. **Critical** for body text, **Moderate**
   for decorative.
5. **Focus ring visibility.** `evaluate_script` to `document.querySelector(':focus, [tabindex="0"]').focus()`,
   then `take_screenshot`. If the screenshot shows no visible focus indicator on
   the focused element, that is **Critical**.

Findings from this pass use the same `DS` numbering and severity rubric as
the static passes. Reference screenshots inline ("Focus ring absent on search
input at top of library page; see screenshot").

---

## Phase 3 — Severity Classification

Rate every finding with this rubric:

| Severity | Criteria |
|----------|----------|
| **Critical** | User-visible design bug, accessibility blocker (missing focus ring, sub-AA contrast on body text, missing label), missing required state (page renders nothing when empty), console error on a clean load, unguarded destructive action |
| **Moderate** | Inconsistency that degrades polish (badge/button style deviation in a page), aspirational gap (planned feature missing), missing nice-to-have state (no skeleton on a slow fetch), orphan LiveView (router-registered but not linked from nav or any in-page affordance), single-UIDR violation with observable impact |
| **Minor** | Cosmetic deviation, single-instance hardcoded value, single `items-*` drift on a mixed-size row, edge-case flow gap |

---

## Phase 4 — Output Format

Present findings **grouped by pass**, sorted **Critical → Moderate → Minor**
within each pass. For each finding:

1. **Location** — exact `file_path:line_number` (or `page_path` for Pass 6)
2. **Issue** — one-sentence description
3. **Evidence** — quoted snippet, grep result, or screenshot reference
4. **Severity** — Critical / Moderate / Minor
5. **Fix** — concrete, specific change

At the end, provide a **summary** with:

- **Findings per pass** — count per pass, broken down by severity
- **Top 5 cross-cutting improvements** — patterns that appear in 3+ places or
  that would have the highest overall impact on UI health
- **Overall design health assessment** — one paragraph synthesizing the
  findings
- **Pass 6 status** — a single line recording whether Pass 6 ran, and if
  skipped, why

If the user is curating a shared backlog file (e.g. a `todo.md` distilled
from the four audits), prefix each finding with **`DS1`, `DS2`, …** to
parallel the `E/P/D` conventions used by the sibling audits (`DS` = DeSign;
two letters to avoid collision with docs-audit's `D` prefix). This command
never writes the backlog itself — output goes to the chat, and the user
decides what to persist.

---

## Rules

- **Evidence, not speculation.** Only flag patterns with concrete evidence of
  violation. "This *could* be inconsistent if…" is not a finding. "This *might*
  look wrong on mobile" is not a finding. Grep result, file:line, and a quoted
  snippet are required. Every past audit run has produced false positives —
  P1, P7, and P10 were all wrong. Apply the same discipline here.
- **Stay in the lane.** If a finding belongs to engineering-audit,
  performance-audit, or docs-audit, skip it. Do not emit "see also" notes.
- **Cite every finding.** Every issue must include the exact file path and
  line number (or page path for Pass 6). No exceptions.
- **Skip what's fine.** If a pass has no issues, say "No issues found" and
  move on. Do not pad the report.
- **No unearned praise.** If an area is clean, one sentence suffices. Spend
  your words on problems, not compliments. A clean report is a valid outcome
  — but only if you genuinely found nothing.
- **No modifications.** This command produces analysis only. Do not edit any
  files. Do not create any files. Output goes to the chat; the user decides
  what to persist.
- **Scope to arguments.** If `$ARGUMENTS` names a specific page, component, or
  file, analyze only that area and the UIDRs/principles that apply to it.
  Special cases:
  - No arg → full audit (Passes 1-5, plus Pass 6 if dev server is up).
  - `library` / `review` / `dashboard` / `settings` / `console` → scope to
    that LiveView + the components it uses (and only that route for Pass 6).
  - `components/<file>.ex` → scope to that single file; Pass 6 is skipped
    (no route to visit).
  - `DESIGN.md` → run only Pass 1 (philosophy) and Pass 5 (gap analysis).
    Skip mechanical passes and Pass 6.
- **Pass 6 graceful degradation.** If chrome-devtools MCP or the dev server
  are unavailable, emit the skip note in the summary and proceed. Never block
  the static passes on live inspection.
