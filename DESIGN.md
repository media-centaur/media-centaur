# Media Centaur — UI Design Guide

Design principles, page structure, and visual standards for the Phoenix LiveView dashboard. All UI work must follow this document.

**Stack:** Tailwind CSS v4 + daisyUI. System fonts. Two themes (light/dark).

**Inspiration:** Linear.app — clean type hierarchy, fast and focused, excellent dark mode, dense-but-breathable layout, status colors that work without screaming.

---

## Design Values

### Purpose & Audience

- **Primary mode:** Glanceable health dashboard. Most visits are a quick scan — is everything healthy? Anything need attention?
- **Secondary mode:** Active workbench. When the review queue fills up, errors appear, or a scan runs, the UI becomes a hands-on tool.
- **Audience:** Single technical user (the developer). No need for progressive disclosure or beginner explanations. Every field can assume domain knowledge.
- **Implication:** Information hierarchy is critical. The "glance" view should surface anomalies and status. Detailed tables and controls should be available but not compete for attention when things are healthy.

### Visual Character

- **Aesthetic:** Clean and modern, not decorative. Data is the interface. Shares terminal values (readability, focus, no fluff) without literal terminal styling.
- **Card structure:** Cards provide good scannability and grouping. Consistent visual treatment across the design system.
- **Unified styling:** Everything must look like it belongs to one design system. Consistent spacing, color usage, and component treatment throughout.

### Color & Theme

- **Dark-first:** Design the dark theme as primary. "Not too dark" — avoid pure black. Comfortable for extended viewing.
- **Light mode:** Must be genuinely good, not a neglected afterthought.
- **Theme toggle:** Three options — System / Light / Dark. Follow OS preference by default.
- **Base palette:** Cool-tinted grays (Tailwind slate family). Slight blue undertone. Modern and technical.
- **Status colors:** Clear but not neon. Distinct at a glance, calibrated to feel natural against the cool gray base.
  - Healthy/success: muted green
  - Warning/attention: amber
  - Error/critical: clear red (not neon, not so muted it gets missed)
  - Active/in-progress: blue or cool accent
  - Neutral/idle: subdued, blends into background
- **Philosophy:** Color means something. When everything is fine, the UI is calm and mostly monochrome. Problems draw the eye through contrast, not loudness.

### Typography & Readability

- **Readability is the #1 priority** — above aesthetics, above density, above everything.
- **Font stack:** System defaults. No custom web fonts.
- **Monospace:** ONLY where it functionally serves alignment or technical content (file paths, UUIDs, numbers in tables). Never for aesthetic reasons.
- **Hierarchy:** Clear distinction between headings, labels, and data values via size and weight, not color.

### Information Density

- **Balanced.** Show plenty of info with room to breathe. Not a wall of tiny text, not wastefully spacious.

### Animation & Feedback

- **Live updates:** Smooth, real-time. When the pipeline is processing, values should tick (throughput, queue depth, progress). The page should feel alive during activity.
- **Transitions:** Subtle. Values update smoothly without jarring jumps. No gratuitous animation.
- **Philosophy:** Animation serves comprehension. A smoothly updating number communicates "this is live." A spinner communicates "working." Decoration that doesn't aid understanding is noise.

---

## UI Principles

1. **Readability is the top priority.** Every visual choice (color, spacing, typography, density) must serve readability first. When in conflict, readability wins.

2. **Function over form.** No visual element exists for decoration. Every color, icon, and animation must serve a functional purpose — communicating status, creating hierarchy, or aiding navigation.

3. **Color is signal.** Color communicates state (healthy/warning/error/active/idle). When everything is normal, the UI is calm and mostly monochrome. Problems draw the eye through color contrast, not through visual loudness or animation.

4. **Dark-first, light-right.** Design the dark theme first. Both themes must be genuinely good. Cool-tinted grays (slate) for the base. Status colors: clear but not neon.

5. **System fonts, monospace only for function.** Use the system font stack. Monospace is reserved for content where alignment matters (paths, IDs, tabular numbers). Never for aesthetic reasons.

6. **The library is the home.** The home page (`/`) is the library — the thing the user actually came here to use. Operational health, pipeline state, and administrative knobs all live on their own pages, reachable from the sidebar. The library is what the app is for; everything else supports it.

7. **Separate concerns into pages.** Library browsing, operational monitoring, review, and settings are different activities. Don't force them onto one screen. Each page has a clear purpose.

8. **Live data feels alive.** When the system is working (pipeline processing, playback active), the UI reflects it with smooth real-time updates. When idle, the UI is quiet. Animation serves comprehension, not decoration.

9. **Unified visual language.** Every component (cards, badges, tables, buttons) follows the same design system. Consistent spacing, consistent color usage, consistent treatment. Nothing should look like it was added by a different person.

10. **Balanced density.** Show plenty of information with room to breathe. Not a Bloomberg terminal, not a marketing landing page. Enough whitespace for scannability, enough data to be useful without navigating.

11. **Cards for grouping.** Use the card pattern to create scannable sections. Each card is a self-contained unit of related information.

12. **Collapsible sidebar navigation.** Left sidebar expands to 200px (icon + label) and collapses to 52px (icon-only with tooltips). State persisted to `localStorage`. Theme toggle lives in the sidebar bottom. Content area gets maximum horizontal space.

---

## CSS & Styling

### When to use custom CSS vs Tailwind

**Custom CSS** is for **coordinated multi-element visual systems** — where multiple elements share state, transitions, or theme-specific behavior that crosses component boundaries:
- Glass morphism (custom properties, backdrop-filter, theme overrides)
- Modal system (backdrop + panel with data-state transitions, scale animation)
- Sidebar (collapsed/expanded states with coordinated transitions)
- Input system focus rings (data-attribute selectors across parent/child)
- Gamepad hint bar (data-attribute conditional display)
- Keyframe animations
- Scrollbar styling
- `truncate-left` (direction: rtl trick)

**Tailwind utilities** for everything else — layout, spacing, sizing, colors, typography, one-off component styling. HEEx components handle reuse at the template level.

### Colors always use DaisyUI theme variables

Never hardcode oklch values for colors that should respond to the theme. Use DaisyUI semantic colors (`text-base-content/60`, `bg-primary/10`) in Tailwind, or relative color syntax in CSS: `oklch(from var(--color-base-content) l c h / 0.6)`. This eliminates manual `[data-theme=light]` overrides — the theme system handles both modes automatically.

Achromatic overlays (`oklch(0% 0 0 / 0.7)` for modal backdrops) and intentionally theme-independent elements (gamepad HUD) may use raw values.

---

## Component Guidelines

### Badges

- **Status/reason labels** (review reasons, entity states, labels that classify rather than act): plain colored text (`text-error`, `text-warning`, `text-info`) — no badge border or fill. The color alone is sufficient signal. Badges add visual noise without aiding readability for inline status indicators.
- **Metric badges** (confidence scores, counts): solid fill is acceptable — these are data values, not labels, and benefit from stronger visual weight to aid scanning.
- **Type badges** (Movie, TV, Extra): `badge-outline` with no color override — neutral classification, not status.

### Buttons

- **Action buttons** (approve, search, select, scan): `btn-soft` with semantic color (`btn-soft btn-success`, `btn-soft btn-info`). Soft variants use a subtle tinted background with colored text — readable against glass surfaces without competing for attention.
- **Dangerous primary actions** (Clear Database, Delete, Rematch, Stop Tracking — buttons the user deliberately reached for): `btn-soft btn-error` for irreversible/destructive, `btn-soft btn-warning` for risky-but-recoverable. Color carries the warning; `btn-soft` keeps the text readable.
- **Inline / dismiss actions** (trash icon on a file row, Cancel in a confirm modal, close `×`): `btn-ghost`, optionally tinted with `text-error` when destructive. Minimal visual weight — these recede until hover.
- **Solid-fill buttons** are acceptable only for `btn-primary` in contexts with a single dominant call-to-action (e.g. form submit). Never use solid-fill semantic buttons (`btn-success`, `btn-info`, `btn-warning`, `btn-error` without `btn-soft`) — the saturated background washes out button text.

See [UIDR-003](decisions/user-interface/2026-03-03-003-button-style-convention.md) for the full rules and the "dangerous primary vs inline dismiss" judgment rule.

---

## Page Structure

### Navigation

Collapsible left sidebar with glassmorphism treatment. Expanded (200px): icon + text label for each page link, brand, theme toggle pill, and collapse button. Collapsed (52px): icon-only with daisyUI tooltips on hover. State persisted via `data-sidebar` attribute on `<html>` and `localStorage`, set before first paint to prevent flash. Collapse toggle dispatches a `phx:toggle-sidebar` JS event.

### Pages

| Page | Path | Role |
|------|------|------|
| **Library** | `/` | Home page: entity browser with Continue Watching, Library Browse, and Upcoming zones. Playback controls and detail view. |
| **Status** | `/status` | Operational hub: library stats, pipeline, watchers, errors, storage, review & playback summaries |
| **Review** | `/review` | Manual TMDB matching for pending files |
| **Settings** | `/settings` | Services, preferences, configuration reference, danger zone |
| **Console** | `/console` | Full-page diagnostic log viewer (also available as a `` ` `` drawer on every page) |

---

### Status (`/status`)

Single scrolling page. The status page is the operational hub — everything you need to answer "is the system healthy?" at a glance. The library itself lives at `/`; this page is the developer/operator view.

**Sections:**
1. **Library stats** — aggregate counts: movies, TV series, collections, episodes, files tracked, images cached
2. **Pipeline status** — per-stage detail: status, throughput, avg duration, active count, errors, last error. Scan button.
3. **Watcher health** — per-directory status, state indicators
4. **External integrations** — TMDB rate limiter status (used/total/available), configuration status
5. **Recent errors table** — last 50 pipeline errors (stage, file, message, time)
6. **Storage metrics** — disk usage per watch directory drive + image cache directory + database file size
7. **Review summary card** — pending count, links to `/review`
8. **Playback summary card** — now playing indicator (entity name + progress), or "idle"

**Planned additions:**
- Health indicators: entities missing images, entities without TMDB IDs, library "completeness"
- Recent activity: last N entities added (what's new since I last looked)
- Auto-approve rate: % of files auto-approved vs needed review (confidence threshold effectiveness)

---

### Settings (`/settings`)

Single scrolling page. Sections:

1. **Logging toggles** — component-level log control + framework log suppression
2. **Configuration** — read-only reference of current config values (auto-approve threshold, MPV path, dirs, etc.)
3. **Danger zone** — clear database, clear & refresh image cache

---

### Review (`/review`)

Visual refresh + UX improvement:
- **Better match comparison:** Side-by-side view of parsed filename info vs. TMDB result — with images, year, description, and enough context to make a confident approve/dismiss decision.

---

### Library (`/`)

The home page. Three-zone layout with top-level tab switching. All zones share the same LiveView and loaded data — switching zones uses `push_patch`, not a full remount.

**Continue Watching** (default zone): Backdrop cards (16:9 aspect) for entities with active watch progress. Each card shows the backdrop/poster image with a gradient overlay, logo or title text, resume label ("Resume S2 E5 at 12:34"), and a progress bar. Selecting a card opens a **ModalShell** — centered overlay with backdrop blur.

**Library Browse** (tab): Full entity catalog as a poster grid with toolbar controls (type tabs: All/Movies/TV, sort: Recently Added/A–Z/Year, text filter). Selecting a poster opens a **ModalShell**.

**Upcoming** (tab): Calendar view of upcoming TMDB releases for tracked entities, with event log and rescan action.

**DetailPanel** is a shared function component rendered inside ModalShell. It displays a 21:9 hero section (backdrop + logo/title + progress + resume button), metadata row, description, and type-specific content lists (season/episode tree for TV, movie list for movie series, file details for single items).

**Detail panel scroll behavior:** The hero, metadata, and description form a fixed (non-scrolling) header. Only the content list below (seasons/episodes, movie list) scrolls. Mouse wheel and keyboard navigation scroll the content list independently — the header stays pinned. This keeps the entity identity and context always visible while browsing long episode lists.

See [UIDR-006](decisions/user-interface/2026-03-09-006-library-zone-architecture.md) for the zone architecture decision.

---

## Planned Data Requirements

Features requiring new backend tracking or computation:

| Feature | Location | Status | Implementation notes |
|---------|----------|--------|---------------------|
| Recent event feed | Status | Planned | In-memory event buffer (like Stats.recent_errors pattern) |
| Library completeness | Status | Planned | Ecto queries: entities missing images, entities without identifiers |
| Auto-approve rate | Status | Planned | Counter in Pipeline.Stats: auto_approved vs needs_review |
| Storage metrics | Status | Done | `Storage.measure_all/0` — disk usage per watch dir, images dir, database |
| Last scan timestamp | Status | Planned | Track in Watcher.Supervisor state or Stats |
