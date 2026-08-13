---
name: user-interface
description: "Use this skill before any UI work — LiveView templates, components, CSS, styling, layout, modals, cards, badges, buttons, themes, or visual design. Contains all component recipes, styling conventions, and design principles."
---

## Design Values

- **Readability first.** Every visual choice serves readability above aesthetics.
- **Color is signal.** Calm when healthy, color draws attention to problems.
- **Dark-only.** Cool slate grays (hue 264). One daisyUI theme (`dark`, `default: true`); there is no light theme and no theme toggle.
- **System fonts.** Monospace only for functional alignment (paths, IDs, tables).
- **Cards for grouping.** Scannable, self-contained sections.
- **Live data feels alive.** Smooth real-time updates, quiet when idle.
- **Inspiration:** Linear.app — clean, fast, focused, excellent dark mode.

## Rendering Defaults ([UIDR-012])

Media Centaur is a specialized desktop app, not a public-internet web app. We trade memory and bandwidth (essentially free in this context) for instant perception. These rules apply to every UI surface unless explicitly justified otherwise:

**Images in the page flow:**

```html
<img src={...} loading="eager" decoding="sync" />
```

Enforced by `MediaCentaur.Credo.Checks.ImgAttributeDefaults` (MC0016). `loading="lazy"` is reserved for bounded reveal-on-demand surfaces (cast headshots, track-search results). Adding a third lazy site requires extending the exempt list with a justification.

**Hero / page-dominant images:** add `fetchpriority="high"`. Two per surface max — the priority signal must remain meaningful.

```html
<img src={@hero.backdrop_url} loading="eager" decoding="sync" fetchpriority="high" />
```

**Stable iterator ids.** Every `:for`'d root element gets `id={"<component>-#{item.entity_id}"}` so morphdom preserves it across renders. Without ids, items are torn down and rebuilt on every patch, replaying the decode/paint cycle.

```html
<button :for={item <- @items} id={"poster-row-#{item.entity_id}"} ...>
```

**No entrance animations on routine renders.** A page paint is not a moment to celebrate. Don't use `phx-mounted={JS.transition(...)}` for fade-in / slide-in on lists. Modal panels keep a 150ms scale-in (signals layering) — that's the ceiling.

**Don't mask transport failures.** WebSocket is the only LiveView transport. No longpoll fallback. A real reconnect attempt is better UX than a hidden slow path.

**Image cache headers** (already wired in `MediaCentaurWeb.Plugs.ImageServer`):
- Versioned URLs (`?v=<n>`): `public, max-age=31536000, immutable`
- Plain URLs: `public, max-age=3600` + ETag

**Hashed static assets are `immutable`** (`Plug.Static` opts in `endpoint.ex`). Phoenix's content-hashed filenames guarantee correctness.

**Static defaults in HTML to avoid pre-JS flash.** Anything driven by an attribute on `<html>` (input-method, sidebar collapse) gets a sane static default in `root.html.heex`. JS upgrades it later — but the first paint already matches.

## Theme System

One dark theme via the daisyUI plugin (`name: "dark"`, `default: true`, `themes: false`). There is no light theme and no theme toggle — the app is dark-only. Colors use oklch color space with hue 264 (cool slate).

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

Every recipe below has a runnable counterpart in **Phoenix Storybook** at <http://localhost:2160/storybook> (dev-only). When adding a recipe, add a story; when changing a component that already has a story, **edit the story variation first** and treat it as the acceptance criterion before editing the component itself. See `storybook` skill → *Storybook-first for visual changes*.

The full philosophy and triage table live at [`docs/storybook.md`](../../../docs/storybook.md). The dedicated [`storybook`](../storybook/SKILL.md) skill covers conventions and anti-patterns.

**Story rule.** Story modules must live under `MediaCentaurWeb.Storybook.*` — that places them inside the `MediaCentaurWeb` boundary. The default `Storybook.*` namespace from the generator is wrong for this repo.

## Component Recipes

### Buttons ([UIDR-003])

**Always** use the `<.button>` component with a `variant` and `size`. Raw `class="btn ..."` strings in templates are flagged by `MediaCentaur.Credo.Checks.RawButtonClass` (precommit). Pass extra Tailwind utilities through the component's `class` attribute.

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

**Standard labels.** Use `"More info"` (not `"Details"`, `"More"`, or `"Info"`) for the secondary action that *opens* an entity's detail view from a card or hero — the hero CTA pair is always **Play** + **More info**. *Inside* the detail modal, the secondary toggle is **Manage** (cog icon), flipping to **Back** (arrow-left icon) when the manage sub-view is open. See [UIDR-003].

### Badges ([UIDR-002])

**Always** use the `<.badge>` component with a `variant` and `size` for any `badge`-styled element. Raw `class="badge ..."` strings (and `class={["badge ...", ...]}` list expressions) in templates are flagged by `MediaCentaur.Credo.Checks.RawBadgeClass` (precommit). Pass extra Tailwind utilities through the component's `class` attribute.

| Variant | Use | Daisy classes |
|---------|-----|---------------|
| `"metric"` (default) | Solid neutral count/score chip | `badge` |
| `"type"` | Outline classification (Movie, TV, Extra) | `badge-outline` |
| `"info"` | Solid info — neutral state (downloading, queued type) | `badge-info` |
| `"success"` | Solid success — completed, healthy | `badge-success` |
| `"warning"` | Solid warning — paused, stalled | `badge-warning` |
| `"error"` | Solid error — failed, broken | `badge-error` |
| `"ghost"` | Muted/quiet count, low-emphasis | `badge-ghost` |
| `"primary"` | Solid primary — active filter pill, attention-grabbing label | `badge-primary` |
| `"soft_primary"` | Soft primary — tonal annotation (rewatch count, manual origin) | `badge-soft badge-primary` |

Sizes: `"xs"`, `"sm"` (default), `"md"`.

```html
<.badge>{@count}</.badge>
<.badge variant="type">Movie</.badge>
<.badge variant="success">Completed</.badge>
<.badge variant="ghost" class="ml-1">×{bucket.count}</.badge>
```

**Status / reason labels** (review reasons, entity states) remain **plain colored text**, not a badge: `<span class="text-error">…</span>`. The `<.badge>` component covers metric/type/state-chip cases only — UIDR-002 #1 deliberately has no badge element.

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
- Cursor treatment: the primary ring everywhere — including bare text — unless it would visually collide with an element of the surface itself (e.g. the zone tabs' active underline); then the tier-2 soft neutral fill, per UIDR-020. Name the concrete collision before reaching for tier 2.
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
| `.text-on-image` | Body text over imagery — `text-shadow` recipe ([UIDR-011]) |
| `.text-on-image-lg` | Titles + logo PNGs over imagery — `filter: drop-shadow()` recipe ([UIDR-011]) |
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
| 010 | Page redistribution: Home/Library/Upcoming/History split |
| 011 | Text on imagery: `.text-on-image` (body, text-shadow) + `.text-on-image-lg` (title/logo, filter:drop-shadow) |

## Component Inventory

Components marked ✅ have a storybook story; ⏳ are pending; ⚠️ are intentionally skipped (state too coupled). See [`docs/storybook.md`](../../../docs/storybook.md) for the full triage.

| Component | File | Purpose | Story |
|-----------|------|---------|-------|
| `flash/1` | `core_components.ex` | Toast notifications | ✅ stub |
| `button/1` | `core_components.ex` | Links and buttons (default: soft primary) | ✅ seed |
| `badge/1` | `core_components.ex` | Metric / type / state chip (UIDR-002) | ✅ |
| `input/1` | `core_components.ex` | Form fields with label + errors | ✅ stub |
| `header/1` | `core_components.ex` | Page title bar with actions slot | ✅ stub |
| `table/1` | `core_components.ex` | Zebra-striped data tables | ✅ stub |
| `list/1` | `core_components.ex` | Key-value display list | ✅ stub |
| `icon/1` | `core_components.ex` | Heroicon rendering | ✅ stub |
| `app/1` | `layouts.ex` | Root layout (sidebar + content) |
| `poster_card/1` | `library_cards.ex` | 2:3 poster grid card |
| `cw_card/1` | `library_cards.ex` | 16:9 continue-watching backdrop card |
| `toolbar/1` | `library_cards.ex` | Type tabs + sort + filter |
| `detail_panel/1` | `detail_panel.ex` | Library detail modal (CinematicShell tenant) |
| `season_list/1` | `detail_panel.ex` | TV episode accordion |
| `cinematic_shell/1` | `cinematic_shell.ex` | Cinematic modal frame (pinned-block scroll system) |
| `track_modal/1` | `track_modal.ex` | TMDB search + track modal |
| `upcoming_zone/1` | `upcoming_cards.ex` | Calendar + release sections |
| `chip_row/1` | `console_components.ex` | Console filter chips |
| `log_list/1` | `console_components.ex` | Monospace log stream |
| `action_footer/1` | `console_components.ex` | Console controls |

## Page Structure

**Stack:** Tailwind CSS v4 + daisyUI. System fonts. Dark-only theme. Inspiration: Linear.app.

| Page | Path | Role |
|------|------|------|
| **Library** | `/` | Home page: Continue Watching, Library Browse, Upcoming zones |
| **Status** | `/status` | Operational hub: library stats, pipeline, watchers, errors, storage |
| **Review** | `/review` | Manual TMDB matching for pending files |
| **Settings** | `/settings` | Services, preferences, configuration, danger zone |
| **Console** | `/console` | Full-page log viewer (also `` ` `` drawer on every page) |

**Library** is the home page. Three zones share one LiveView, switching via `push_patch` ([UIDR-006]). DetailPanel is the library tenant of CinematicShell. Hero section (21:9 backdrop) is fixed; content list scrolls independently.

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
- `phx-value-value` on a `<button>`/`<input>` — the key `value` collides with the element's native `value` DOM property, which LiveView merges into the click payload and clobbers to `""`. The render looks right and a `render_click` test passes; it only breaks on a real click. Use a descriptive key (`phx-value-choice`, `phx-value-id`). Enforced by Credo **MC0021**. (`phx-value-name` does **not** collide — only `value`.)
- Relying on `<button>` for a pointer cursor — Tailwind v4 Preflight does **not** set `cursor: pointer` on buttons; add `cursor-pointer` explicitly, or a styled button feels inert on hover.

### Non-toggle settings controls

For a bounded numeric setting, use `MediaCentaurWeb.SettingsLive.Components.settings_stepper/1` (the −/value/+/Reset sibling of `settings_row`) — focusable nav items, absolute precomputed targets in `phx-value-choice` (the value's owner does the arithmetic), `aria-disabled` no-ops at the bounds so the nav graph never shifts. For a pick-one-of-N enum setting, restore `settings_choice/1` from git history (removed with the interface-scale stepper change when its last call site went away) rather than hand-rolling a segmented control — a native `<select>` is hostile to d-pad/10-foot use either way.
