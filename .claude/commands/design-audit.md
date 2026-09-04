---
description: Design audit — design values and anti-patterns from the user-interface skill, UIDR compliance, UX state coverage, input-system coverage, and live inspection of the dev server.
argument-hint: "[route-or-component (optional)]"
allowed-tools: Read, Glob, Grep, Bash(mix compile *), Bash(ls *), Bash(page-shot *), Bash(chromium-probe *), Bash(mc-nav-trace *), Bash(mc-ui-probe *), Bash(systemctl --user is-active *), Bash(curl *)
---

# Design Audit

You are auditing the Media Centaur UI (Phoenix LiveView, Tailwind CSS v4, daisyUI,
dark-only theme, desktop media-center app driven by keyboard and gamepad as much as
mouse). Findings must be **concrete and evidence-based**: file and line, quoted
snippet or screenshot, and a specific fix. Not polish suggestions.

**Brutal honesty is mandatory.** Do not soften findings or balance them with praise.

**Scope:** If `$ARGUMENTS` is provided, focus on that route, LiveView, or component
file. Otherwise audit the whole UI under `lib/media_centaur_web/`.

**Strict lane.** Not covered here: LiveView/CSS performance (`/performance-audit`),
documentation drift (`/docs-audit`), dead code and duplication in logic
(`/engineering-audit`). Skip such findings; do not emit "see also" notes.

**What is already enforced — do not re-audit it.** Credo checks in `credo_checks/`
gate raw badge and button classes (MC0007/MC0010), typed component attrs and
storybook coverage (MC0008/MC0009), modal backdrop and click-away rules
(MC0006/MC0020), native confirm dialogs (MC0027), image attribute defaults and
declared artwork widths (MC0016/MC0028), `phx-value-value` (MC0021), and the entity
modal contract (MC0011). Assume `mix precommit` is green.

## The authority layer

There is no `DESIGN.md`. Authority, in order:

1. **`.claude/skills/user-interface/SKILL.md`** — design values (readability first,
   color is signal, dark-only, system fonts, cards for grouping), rendering defaults
   ([UIDR-012]), the glass tiers, component recipes, layout components, CSS
   conventions, and the **Anti-Patterns** section. Read it in full.
2. **`decisions/user-interface/*.md`** — every UIDR on disk (glob; numbering gaps
   such as 007 are deliberate retirements; read the latest ones, which the skill's
   table may not list yet). `template.md` is not a record.
3. **`assets/css/app.css`** — the theme block, glass utilities, custom utilities.
4. **`storybook/**/*.story.exs`** — the pinned state matrix per component.
5. **The `writing-copy` skill** (global, `~/.claude/skills/writing-copy/`) for any user-facing words, and
   `.claude/skills/input-system/SKILL.md` plus `docs/input-system.md` for
   keyboard/gamepad behaviour.

Build the page inventory from `lib/media_centaur_web/router.ex` (`live "/…"`
routes: home, apps, console, discovery and its tabs, guide, history, incoming,
library, reconcile, review, settings, setup, status) and the sidebar in
`lib/media_centaur_web/components/layouts.ex`. Do not work from a memorised list.

---

## Passes

### Pass 1 — Design values and anti-patterns

For each page, assess against the skill's design values and its Anti-Patterns
section in one or two sentences; each drift is a finding. Specific checks:

- **Readability first / function over form:** decoration without function; density
  or cleverness that costs legibility; walls of text or marketing whitespace.
- **Color is signal:** saturated color on healthy state; problem state that fails to
  draw the eye; color used to decorate. The "console look" and chip palettes belong
  only to the console; colored edge or accent bars are banned as a component idiom
  (use icon, text, or tinted wash).
- **Dark-only:** any light-theme conditional, `data-theme` toggle, or hardcoded
  color that assumes a light ground.
- **Typography:** custom web fonts; monospace for anything but paths, ids, and
  tabular numbers; proportional fonts for those.
- **Cards for grouping:** grouped content without the card pattern; redundant card
  shells around single items; nested cards.
- **No rails, no redundant empty states:** bookkeeping surfaces behind a disclosure,
  empty-state CTAs that duplicate a visible affordance.
- **Unified language:** a card, badge, table, or button that looks foreign next to
  its siblings; icon sources other than Heroicons.
- **Copy:** labels, empty states, errors, and tooltips that break the `writing-copy`
  voice or use code vocabulary ("entity", "release" outside acquisition).

### Pass 2 — UIDR compliance

For every UIDR on disk, read its Decision section and check the files it governs.
The mechanical ones:

- **UIDR-001 file paths:** `.truncate-left` + `title` + `<bdo dir="ltr">` at every
  path-rendering site (grep `path`, `file_path`, `WatchedFile`, `truncate`). Raw
  path with no tooltip → Critical; end-truncation → Moderate; missing `<bdo>` →
  Moderate.
- **UIDR-002 badges / UIDR-003 buttons:** the component layer enforces classes, so
  audit *usage*: a status or reason rendered as a solid badge, a destructive action
  that is not `btn-ghost`, more than one dominant `btn-primary` on a page.
- **UIDR-004 durations:** `"PT`, raw seconds, or `runtime`/`duration` interpolated
  without the `LiveHelpers` formatter → Critical for ISO leaks, Moderate otherwise.
- **UIDR-008 baseline alignment:** `items-center` on rows mixing text sizes.
- **UIDR-011 text on imagery:** text over artwork without `.text-on-image`.
- **UIDR-012 rendering defaults:** lazy images, unstable ids, entrance animations.
- **UIDR-013 modal dismissal / UIDR-019 detail modal two regions / UIDR-021
  artwork ladder / UIDR-024 progress hairline:** verify in `modal.ex`,
  `cinematic_shell.ex`, `detail_panel.ex`, and `progress_hairline.ex`.
- **UIDR-018 focus, cursor, scroll / UIDR-020 cursor tiers / UIDR-026 nav reselect
  scrolls to top / UIDR-028 BACK enters the main menu:** read `assets/js/input/
  config.js` and the page behaviours (`assets/js/input/<page>_behavior.js`). A
  content context with a left edge into `sidebar` → Critical; a page without a
  behaviour or without a `sidebar` node → Moderate. Nav items must never carry a
  permanent outline (gamepad mode pre-sets it); selection states use an inset ring.
- **UIDR-027 play in place / UIDR-029 plan board diagnosis:** verify the surfaces
  they name still exist and behave as decided.

For the remaining UIDRs, one finding per observable deviation from the Decision.

### Pass 3 — Visual consistency

- Hardcoded colors (`#hex`, `rgb(`, `oklch(`) in `.ex` files or in `app.css` outside
  the theme block; inline `style=` for static spacing or color (dynamic runtime
  values such as progress widths are fine).
- Typography drift: two conventions for the same role (secondary label, mono value,
  section header) across pages.
- Duplicate component shapes implemented twice instead of a shared function
  component (each is Moderate); stories missing a state the app exercises.
- Glass tiers used outside their documented layer.

### Pass 4 — UX state coverage and flow gaps

For each LiveView:

- **Empty state:** nothing rendered when empty → Critical; bare "no results" where
  the skill prescribes a designed state → Moderate; a redundant empty state (CTA
  duplicating a visible control) → Minor.
- **Loading state:** `assign_async` or slow mounts without feedback → Moderate.
- **Error state:** async failures or broadcast error payloads swallowed silently →
  Critical. Conditions should reach the Status page, not vanish.
- **Destructive confirmations:** every destructive `handle_event` (delete, clear,
  discard, dismiss all, reset, withdraw) gated by a confirmation surface →
  unguarded → Critical.
- **Orphan pages:** a router `live` route reachable from neither the sidebar nor an
  in-page link → Moderate.
- **Input-system coverage:** interactive content without `data-nav-*` attributes or
  a registered page behaviour; run `mc-nav-trace` for any nav question (it flags
  clipped focus and layout-versus-rect traps). Keyboard/gamepad users stuck on a
  page → Moderate. The console drawer is deliberately outside the input system —
  do not flag it.

### Pass 5 — Promised but missing

Read the open items in `campaigns/*.md` (Next steps, deferred lists) and the
Consequences sections of the newest UIDRs. For each UI promise: implemented (skip),
partial (Moderate, say what is missing), absent (Moderate). The symmetry rule: a
promised-but-missing feature is a design finding; an undocumented-but-present one is
a docs-audit finding.

### Pass 6 — Live inspection (when the dev server is up)

Probe `systemctl --user is-active media-centaur-dev` and `curl -s -o /dev/null -w
'%{http_code}' http://127.0.0.1:2160/`. If either fails, record "Pass 6 skipped: dev
server not reachable" and continue. Never use the chrome-devtools MCP tools; they do
not work on this machine.

For each route in scope:

1. **Screenshot:** `page-shot --url http://127.0.0.1:2160/<route> --viewport
   1920x1080 --wait-ms 3000`, then Read the PNG. Use it as evidence; do not ask
   the user to look.
2. **Console cleanliness:** `chromium-probe --with-console http://127.0.0.1:2160/
   <route> 'document.title'` — any console error → Critical, warning → Moderate;
   quote it.
3. **Contrast spot-check:** with `chromium-probe`, evaluate computed `color` and
   `background-color` for body text, secondary text, and text on glass; compute the
   WCAG ratio; below 4.5:1 for body text → Critical, below 3:1 for large text →
   Moderate.
4. **Focus visibility:** headless Chromium has no window focus and transitions never
   settle, so assert on the driving state (the focused `data-nav-item`, its
   classes, the `focus-visible` rules in `app.css`), not on animated values. A
   focus indicator that would be invisible → Critical.
5. **Backdrop geometry** after any `.orientation-backing*` or modal backdrop change:
   `mc-ui-probe align|shift|shot`.

Clicks issued before `phx-connected` appears on `[data-phx-main]` are dropped; wait
for it. Live inspection reads the real library; never mutate through the browser.

---

## Severity

| Severity | Criteria |
|----------|----------|
| **Critical** | User-visible design bug, accessibility blocker (invisible focus, sub-AA body text, missing label), page renders nothing when empty, console error on a clean load, unguarded destructive action, a retired gesture reintroduced |
| **Moderate** | Inconsistency that degrades polish, UIDR deviation with observable impact, missing loading/empty design, orphan route, page without input-system coverage, promised feature missing |
| **Minor** | Cosmetic deviation, single hardcoded value, single alignment drift |

## Output

Number findings **DS1, DS2, …** grouped by pass, Critical → Minor within a pass. For
each: **Location** (`file_path:line` or route), **Issue**, **Evidence** (snippet,
grep result, or screenshot path), **Severity**, **Fix**. End with findings per pass,
the top 5 cross-cutting improvements, a one-paragraph health assessment, and a
one-line Pass 6 status.

## Rules

- **Evidence, not speculation.** Grep result, file:line, and a quoted snippet or
  screenshot are required. Past runs produced false positives; verify before
  reporting.
- **Stay in the lane.** No "see also" notes.
- **Skip what's fine.** "No issues found" is a valid pass result.
- **No unearned praise.**
- **Analysis only.** Do not modify or create project files; screenshots go to the
  scratchpad. Output goes to the chat.
- **Scope to arguments.** A route name scopes to that LiveView, its components, its
  page behaviour, and that route for Pass 6; a component file skips Pass 6.
