---
name: user-interface
description: "Use this skill before any UI work — LiveView templates, components, CSS, styling, layout, modals, cards, badges, buttons, themes, or visual design. Contains all component recipes, styling conventions, and design principles."
---

## Design Values

- **Readability first.** Every visual choice serves readability above aesthetics.
- **Color is signal.** Calm when healthy, color draws attention to problems.
- **Dark-first, light-right.** Cool slate grays (hue 264). Both themes genuinely good.
- **System fonts.** Monospace only for functional alignment (paths, IDs, tables).
- **Cards for grouping.** Scannable, self-contained sections.
- **Live data feels alive.** Smooth real-time updates, quiet when idle.
- **Inspiration:** Linear.app — clean, fast, focused, excellent dark mode.

## Theme System

Two themes via daisyUI plugin. Colors use oklch color space with hue 264 (cool slate).

**Always use theme variables** — never hardcode oklch for themeable colors:
- Tailwind: `text-base-content/60`, `bg-primary/10`
- CSS: `oklch(from var(--color-base-content) l c h / 0.6)`
- Exception: achromatic overlays (`oklch(0% 0 0 / 0.7)`) and theme-independent elements (gamepad HUD)

**Semantic colors:**
| Role | Usage |
|------|-------|
| Primary (blue) | Interactive elements, focus rings, accents |
| Success (muted green) | Healthy, completed, playing |
| Warning (amber) | Attention, risky, paused |
| Error (clear red) | Failed, destructive, critical |
| Info (cool blue) | Informational, TV type badge |
| Base content | Text hierarchy via opacity (`/60`, `/40`, `/20`) |

## Glassmorphism (Three Tiers)

| Class | Purpose | Key Properties |
|-------|---------|---------------|
| `.glass-surface` | Cards, panels, primary surfaces | Semi-transparent bg, `backdrop-filter: blur(12px)`, border, shadow |
| `.glass-inset` | Nested panels, image placeholders, toggle items | Subtler bg, no blur, no shadow |
| `.glass-sidebar` | Left navigation | `backdrop-filter: blur(30px)`, border-right |

Body has a fixed two-tone radial gradient background. Glass surfaces float above it.

## Storybook (live catalog)

Every recipe below has a runnable counterpart in **Phoenix Storybook** at <http://localhost:1080/storybook> (dev-only). When adding a recipe, add a story; when changing a component, update its story in the same PR.

The full philosophy and triage table live at [`docs/storybook.md`](../../docs/storybook.md). The dedicated [`storybook`](../storybook/SKILL.md) skill covers conventions and anti-patterns.

**Story rule.** Story modules must live under `MediaCentarrWeb.Storybook.*` — that places them inside the `MediaCentarrWeb` boundary. The default `Storybook.*` namespace from the generator is wrong for this repo.

## Component Recipes

### Buttons ([UIDR-003])

**Always** use the `<.button>` component with a `variant` and `size`. Raw `class="btn ..."` strings in templates are flagged by `MediaCentarr.Credo.Checks.RawButtonClass` (precommit). Pass extra Tailwind utilities through the component's `class` attribute.

| Variant | Use | Daisy classes (under the hood) |
|---------|-----|--------------------------------|
| `"primary"` | Solid CTA — one per view (hero Play, modal confirm) | `btn-primary` |
| `"secondary"` (default) | Soft blue — default action, navigation, hero "More info" | `btn-soft btn-primary` |
| `"action"` | Approve, install, scan | `btn-soft btn-success` |
| `"info"` | TMDB / track-related | `btn-soft btn-info` |
| `"risky"` | Rematch, stop tracking, restart | `btn-soft btn-warning` |
| `"danger"` | Delete, clear DB | `btn-soft btn-error` |
| `"dismiss"` | Cancel, close, back, page nav | `btn-ghost` |
| `"destructive_inline"` | Inline trash icons | `btn-ghost text-error` |
| `"neutral"` | Quiet pill (test connection, repair) | `btn-soft` |
| `"outline"` | Low-emphasis switch (status report) | `btn-outline` |

Sizes: `"xs"`, `"sm"`, `"md"` (default), `"lg"`. Shapes: `"circle"`, `"square"` for icon-only buttons.

```html
<.button variant="primary" size="lg" phx-click="play">Play</.button>
<.button variant="secondary" size="lg" phx-click="open">More info</.button>
<.button variant="dismiss" size="sm" phx-click="cancel">Cancel</.button>
<.button variant="danger" size="sm" phx-click="delete">Delete</.button>
```

**Never** use solid-fill semantic buttons (`btn-success`, `btn-error` alone) — text washes out on glass.

**Standard labels.** Use `"More info"` (not `"Details"`, `"More"`, or `"Info"`) for the secondary action that opens an entity's detail / info view. The hero CTA pair is always **Play** + **More info**.

### Badges ([UIDR-002])

| Context | Recipe |
|---------|--------|
| **Status labels** (review reasons, entity states) | Plain colored text: `text-error`, `text-warning`, `text-info` — no badge |
| **Metric values** (confidence, counts) | `badge badge-sm` with solid fill — data values need weight |
| **Type classification** (Movie, TV, Extra) | `badge badge-outline` — neutral, no color |

### Cards

```html
<%!-- Standard card --%>
<div class="glass-surface rounded-xl p-4 space-y-3">
  <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">Title</h3>
  <%!-- content --%>
</div>

<%!-- Nested/inset card --%>
<div class="glass-inset rounded-lg p-3">
  <%!-- content --%>
</div>
```

### Modals (Always-in-DOM Pattern)

Modals are **never** conditionally rendered with `:if={}`. They stay in the DOM and toggle via `data-state`.

```html
<div class="modal-backdrop" data-state={if @open, do: "open", else: "closed"}>
  <div class="modal-panel">
    <%!-- content --%>
  </div>
</div>
```

- `.modal-backdrop`: full inset, z-50, dark overlay with blur, opacity transition
- `.modal-panel`: centered, max 700px, scale+fade transition, inherits `color: var(--color-base-content)` ([UIDR-009])
- `.modal-panel-sm`: smaller variant, 480px max
- Event handlers (`phx-click-away`, `phx-window-keydown`) are conditionally bound with `@open && @on_close`

**Why always-in-DOM:** `backdrop-filter: blur()` has a first-frame compositing cost. Conditional rendering causes visible flash on every open.

### File Paths ([UIDR-001])

```html
<span class="truncate-left" title={full_path}>
  <bdo dir="ltr">{full_path}</bdo>
</span>
```

Start-truncation: filename (most identifying part) always visible, directory prefix elided. Full path in `title` tooltip. The `<bdo>` prevents RTL reordering of path separators.

### Durations ([UIDR-004])

Display: `3h 48m` or `45m` (omit hours when zero). Space-separated, no leading zeros, no seconds. Storage remains ISO 8601. Use `format_iso_duration/1` from `LiveHelpers`.

### Progress Bars

```html
<div class="h-[3px] bg-base-content/10 rounded-full overflow-hidden">
  <div class="progress-fill h-full bg-primary rounded-full" style={"width: #{pct}%"}></div>
</div>
```

`.progress-fill` animates width changes (`300ms ease-out`). For playback state, use `bg-success` (playing) or `bg-warning` (paused).

### Section Headers

```html
<h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">Section Name</h3>
```

Muted, small, uppercase tracking — consistent across all card/section headers.

### Icon Usage

```html
<.icon name="hero-chevron-right-mini" class="size-4" />
```

Sizes: `size-3` (12px), `size-4` (16px default), `size-5` (20px), `size-6` (24px). Icons reinforce meaning, not decoration. Interactive icons wrap in `btn btn-ghost`.

## Layout Components

### Sidebar Navigation

Fixed left, 200px expanded / 52px collapsed. State via `data-sidebar` on `<html>`, persisted in `localStorage`.

- Links: `.sidebar-link` — muted by default, primary color when `.sidebar-link-active`
- Labels: `.sidebar-label` — opacity 0 when collapsed
- Theme toggle: pill (expanded) or cycle icon (collapsed)
- Tooltips: `tooltip tooltip-right` on collapsed icons

### Zone Tabs

```html
<div data-nav-zone="zone-tabs" class="flex gap-1">
  <a class={["zone-tab", @zone == :watching && "zone-tab-active"]}
     data-nav-item data-nav-zone-value="watching" tabindex="0"
     phx-click="switch_zone" phx-value-zone="watching">
    Continue Watching
  </a>
</div>
```

Plain text links with animated underline. `.zone-tab-active` expands underline from center.

### Library Toolbar

- **Type tabs:** `.tabs.tabs-boxed.library-tabs` — glass pill container, `.tab-active` with `bg-neutral/80`
- **Sort dropdown:** `.sort-dropdown-trigger` (pill) + `.sort-dropdown-menu.glass-surface` (animated dropdown)
- **Filter input:** `.library-filter` — pill with glass border, blue focus ring

### Console Overlay (Guake-style)

- `.console-overlay` (z-60, full-screen backdrop)
- `.console-panel` (55vh, slides down from top, 280ms cubic-bezier open)
- Monospace font, `.console-entry` with timestamp + component badge + message
- Toggle with `` ` `` backtick key

## Keyboard/Gamepad Navigation

All interactive elements need `data-nav-item` and `tabindex="0"` for gamepad/keyboard navigation. See the `input-system` skill for full details.

**Key rules:**
- Zone containers: `data-nav-zone="zone-name"` — must not nest
- Grid containers: add `data-nav-grid` for column detection
- Page behavior: `data-page-behavior="page-name"` on root
- Focus rings: visible only in keyboard/gamepad mode (`[data-input=keyboard]`, `[data-input=gamepad]`)
- Nav items must be **direct children** of their zone (CSS selector uses `>` for some zones like `upcoming`)

## CSS Conventions

### When to Use Custom CSS vs Tailwind

**Custom CSS** for coordinated multi-element systems:
- Glassmorphism (custom properties, theme overrides)
- Modal system (backdrop + panel state transitions)
- Sidebar (collapsed/expanded coordinated transitions)
- Input system focus rings (data-attribute selectors)
- Keyframe animations, scrollbar styling

**Tailwind utilities** for everything else — layout, spacing, sizing, colors, typography.

### Animation Rules

- **Only animate `opacity` and `transform`** — compositor-only, GPU-cheap
- **Never animate** `background`, `backdrop-filter`, `box-shadow`, or layout properties on blur elements
- **Never use CSS keyframe animations on LiveView stream items** — morphdom replays them on re-render. Use `phx-mounted` + `JS.transition()` instead.
- **Minimize `reset_stream` calls** — only reset when grid-affecting params change

### Custom Utilities

| Utility | Purpose |
|---------|---------|
| `.glass-surface` | Primary surface (blur, border, shadow) |
| `.glass-inset` | Nested surface (subtle bg) |
| `.glass-sidebar` | Nav surface (strong blur) |
| `.truncate-left` | Start-truncation for file paths |
| `.thin-scrollbar` | Subtle scrollbar (`scrollbar-width: thin`) |
| `.progress-fill` | Animated width transition |
| `.spoiler-blur` | Blur + opacity for unwatched episode info |

## Decision Records

All UI decisions live in `decisions/user-interface/` using MADR 4.0 format.

| UIDR | Decision |
|------|----------|
| 001 | File paths: start-truncation (`.truncate-left` + `<bdo>` + `title`) |
| 002 | Badges: plain text for status, solid for metrics, outline for type |
| 003 | Buttons: `btn-soft` for actions, `btn-ghost` for dismiss, never solid semantic |
| 004 | Durations: `Xh Ym` format, no seconds, display-layer only |
| 005 | Playback card: three-row hierarchy (header, identity, progress bar) |
| 006 | Library zones: three tabs in single LiveView, `push_patch` switching |
| 007 | Sidebar: collapsible (200px/52px), replaced left-wall nav |
| 008 | Flex rows: `align-items: baseline` for mixed text sizes |
| 009 | Modal panels: explicit `color: var(--color-base-content)` inheritance |

## Component Inventory

Components marked ✅ have a storybook story; ⏳ are pending; ⚠️ are intentionally skipped (state too coupled). See [`docs/storybook.md`](../../docs/storybook.md) for the full triage.

| Component | File | Purpose | Story |
|-----------|------|---------|-------|
| `flash/1` | `core_components.ex` | Toast notifications | ✅ stub |
| `button/1` | `core_components.ex` | Links and buttons (default: soft primary) | ✅ seed |
| `input/1` | `core_components.ex` | Form fields with label + errors | ✅ stub |
| `header/1` | `core_components.ex` | Page title bar with actions slot | ✅ stub |
| `table/1` | `core_components.ex` | Zebra-striped data tables | ✅ stub |
| `list/1` | `core_components.ex` | Key-value display list | ✅ stub |
| `icon/1` | `core_components.ex` | Heroicon rendering | ✅ stub |
| `app/1` | `layouts.ex` | Root layout (sidebar + content) |
| `theme_toggle/1` | `layouts.ex` | System/Light/Dark picker |
| `poster_card/1` | `library_cards.ex` | 2:3 poster grid card |
| `cw_card/1` | `library_cards.ex` | 16:9 continue-watching backdrop card |
| `toolbar/1` | `library_cards.ex` | Type tabs + sort + filter |
| `detail_panel/1` | `detail_panel.ex` | Entity detail (hero + metadata + content) |
| `season_list/1` | `detail_panel.ex` | TV episode accordion |
| `modal_shell/1` | `modal_shell.ex` | Centered modal with backdrop blur |
| `track_modal/1` | `track_modal.ex` | TMDB search + track modal |
| `upcoming_zone/1` | `upcoming_cards.ex` | Calendar + release sections |
| `chip_row/1` | `console_components.ex` | Console filter chips |
| `log_list/1` | `console_components.ex` | Monospace log stream |
| `action_footer/1` | `console_components.ex` | Console controls |

## Page Structure

**Stack:** Tailwind CSS v4 + daisyUI. System fonts. Two themes (light/dark). Inspiration: Linear.app.

| Page | Path | Role |
|------|------|------|
| **Library** | `/` | Home page: Continue Watching, Library Browse, Upcoming zones |
| **Status** | `/status` | Operational hub: library stats, pipeline, watchers, errors, storage |
| **Review** | `/review` | Manual TMDB matching for pending files |
| **Settings** | `/settings` | Services, preferences, configuration, danger zone |
| **Console** | `/console` | Full-page log viewer (also `` ` `` drawer on every page) |

**Library** is the home page. Three zones share one LiveView, switching via `push_patch` ([UIDR-006]). DetailPanel renders inside ModalShell. Hero section (21:9 backdrop) is fixed; content list scrolls independently.

**Status** is a single scrolling page: library stats, pipeline status, watcher health, TMDB rate limiter, recent errors, storage metrics, review summary, playback summary.

**Review** uses master-detail layout: pending file list on the left, TMDB match comparison on the right.

**Settings** uses sections nav + content grid: Services, Preferences, Configuration, Danger Zone.

## Anti-Patterns

- Solid-fill semantic buttons (`btn-error` without `btn-soft`)
- Hardcoded oklch color values for themeable colors
- `:if={}` on elements with `backdrop-filter`
- CSS keyframe animations on LiveView stream items
- Monospace font for aesthetic reasons (only for paths/IDs/tables)
- Nested `data-nav-zone` containers
- Badge borders/fills on status labels (use plain colored text)
- Custom CSS for one-off styling (use Tailwind utilities)
