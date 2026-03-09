# Phase 1: DetailPanel Component — Implementation Plan

## Goal

Extract a standalone function component `MediaCentaurWeb.Components.DetailPanel` that renders full entity detail content. Both shells (modal and drawer) will wrap this same component. This phase creates the component and its tests — no shell, no page integration yet.

## Assigns Interface

```elixir
attr :entity, :map, required: true        # Entity with associations (seasons, episodes, movies, images, identifiers)
attr :progress, :map, default: nil         # ProgressSummary.t() | nil
attr :resume, :map, default: nil           # ResumeTarget result map | nil
attr :progress_records, :list, default: [] # Raw progress records for per-episode lookup
attr :watch_dirs, :list, default: []       # For stripping watch dir prefixes from file paths
attr :on_play, :string, default: "play"    # Event name for play actions
attr :on_close, :string, default: "close"  # Event name for dismiss
```

## Sections (top to bottom)

### 1. Hero (21:9)
- Full-bleed backdrop image (fall back to poster, then placeholder icon)
- Bottom gradient: `bg-gradient-to-t from-base-200 via-base-200/80 to-transparent`
- Logo overlay bottom-left (or text title fallback with drop-shadow)
- Right side bottom: series progress text + mini progress bar + Resume/Play button

**Resume button logic:**
| `resume` action | Button label | Button style |
|-----------------|-------------|--------------|
| `"resume"` | `Resume S1E7` (or `Resume at 26:24` for movies) | `btn-soft btn-success` |
| `"begin"` | `Play` | `btn-soft btn-primary` |
| `nil` | `Play` (disabled if no content_url) | `btn-soft btn-primary` |

### 2. Metadata Row
- Type badge (`badge badge-outline badge-sm`)
- Year (from `date_published`)
- Season count (TV) or movie count (movie series)
- Content rating (if present)

### 3. Description
- `line-clamp-4` initially, expandable on click (toggle `@desc_expanded`)
- Only renders if entity has description

### 4. Content List (type-dependent)

**TV Series:**
- Collapsible season sections with chevron + "Season N" + "X/Y watched"
- Auto-expand: season containing current episode (from `progress.current_episode`), or Season 1 if no current
- Episode rows: 3-column layout (number | name | status)
  - Watched: muted bg, green checkmark
  - Current: blue-tinted bg, position/duration text, mini progress bar
  - Unwatched: default bg, muted duration
- Play button per episode row

**Movie Series:**
- Flat movie list with poster thumbnail, name, year, play button

**Standalone Movie:**
- No content list section (hero + metadata + description is sufficient)

### 5. More Details (collapsible)
- File path (with watch_dir stripping, truncate-left)
- UUID
- TMDB match status

## Files

| File | Action |
|------|--------|
| `lib/media_centaur_web/components/detail_panel.ex` | Create |
| `test/media_centaur_web/components/detail_panel_test.exs` | Create |
| `assets/css/app.css` | Add detail-panel styles (hero gradient, episode row states) |

## Implementation Steps

### Step 1: Create component with hero section
- Create `detail_panel.ex` with the public `detail_panel/1` function component
- Implement hero rendering (backdrop, logo, gradient, title fallback)
- Resume button with configurable event name
- Progress bar in hero (reuse progress display logic from old library)

### Step 2: Metadata + description sections
- Type badge, year, counts
- Description with line-clamp

### Step 3: TV Series episode list
- Season headers with expand/collapse (internal state via assigns — the parent LiveView will need to manage expanded_seasons)
- Episode rows with watched/current/unwatched styling
- Per-episode progress lookup via `EpisodeList.index_progress_by_key/1`
- Auto-expand current season

**State note:** Since this is a function component (not a LiveComponent), expand/collapse state must be managed by the parent LiveView. The component accepts `expanded_seasons` as an assign (MapSet of season numbers). The parent handles `"toggle_season"` and `"toggle_episode_detail"` events.

### Step 4: Movie Series list + standalone movie variant
- Movie rows with name, year, play button
- Standalone movie: hero + metadata + description only

### Step 5: CSS
- `.detail-hero` aspect ratio and gradient
- Episode row state classes (watched, current, unwatched)
- Season header styling

### Step 6: Tests
- Test each variant renders correct sections (TV, movie series, standalone)
- Test auto-expand picks correct season
- Test resume button label logic
- Test progress display
- Use `build_*` factory helpers (no DB)

### Step 7: Verify
```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit
```

## Design Decisions

1. **Function component, not LiveComponent** — DetailPanel has no internal state. The parent LiveView (or a thin LiveComponent wrapper in the shell) manages expanded_seasons and other toggle state. This keeps the component pure and testable.

2. **Event names are configurable** — `on_play` and `on_close` allow the same component to work in both modal (where close = dismiss modal) and drawer (where close = close drawer) contexts.

3. **Progress records passed through** — The component receives pre-computed `progress` (ProgressSummary) and `resume` (ResumeTarget) from the parent, plus raw `progress_records` for per-episode lookup. No data fetching inside the component.

4. **Expanded seasons as assign** — `expanded_seasons` is a MapSet managed by the parent. The component's `auto_expand_season/1` helper computes the initial value, but the parent decides when to apply it.

## Additional Assigns (managed by parent, passed to component)

```elixir
attr :expanded_seasons, :any, default: nil   # MapSet of season numbers (nil = use auto-expand)
attr :expanded_episodes, :any, default: nil  # MapSet of episode IDs for detail expansion
```
