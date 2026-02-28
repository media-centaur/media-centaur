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

6. **The dashboard is a hub.** The home page answers "do I need to go anywhere?" — library stats front and center, mini-dashboard cards summarizing each sub-page. If everything is healthy, you're done in one glance.

7. **Separate concerns into pages.** Library overview and operational monitoring are different activities. Don't force them onto one screen. Each page has a clear purpose.

8. **Live data feels alive.** When the system is working (pipeline processing, playback active), the UI reflects it with smooth real-time updates. When idle, the UI is quiet. Animation serves comprehension, not decoration.

9. **Unified visual language.** Every component (cards, badges, tables, buttons) follows the same design system. Consistent spacing, consistent color usage, consistent treatment. Nothing should look like it was added by a different person.

10. **Balanced density.** Show plenty of information with room to breathe. Not a Bloomberg terminal, not a marketing landing page. Enough whitespace for scannability, enough data to be useful without navigating.

11. **Cards for grouping.** Use the card pattern to create scannable sections. Each card is a self-contained unit of related information.

12. **Minimal navigation chrome.** Top bar is compact: app name, page links, theme toggle. No unnecessary height or decoration. Content area gets maximum vertical space.

---

## Page Structure

### Navigation

Minimal top bar: app name/icon, page links, theme toggle. Compact height, no unnecessary decoration.

### Pages

| Page | Path | Role |
|------|------|------|
| **Dashboard** | `/` | Hub page: library stats + mini-dashboard cards linking to sub-pages |
| **Operations** | `/operations` | System health, pipeline, watchers, errors, controls, config, logging |
| **Review** | `/review` | Manual TMDB matching for pending files |
| **Library** | `/library` | Entity browser with playback controls |

---

### Dashboard (`/`)

**Main content — Library section (implemented):**
- Aggregate counts: movies, TV series, collections, episodes, files tracked, images cached
- Incomplete image count (warning indicator)

**Planned additions:**
- Health indicators: entities missing images, entities without TMDB IDs, library "completeness"
- Recent activity: last N entities added (what's new since I last looked)
- Auto-approve rate: % of files auto-approved vs needed review (confidence threshold effectiveness)

**Summary cards (mini-dashboards linking to sub-pages):**
- **Operations card:** Pipeline status (idle/active/error), watcher health dots, queue depth, error count. Enough to know "all healthy" or "go look."
- **Review card:** Pending count. Enough to know "nothing to do" or "N files waiting."
- **Playback card:** Now playing indicator (entity name + progress), or "idle" when nothing plays.

**Design principle:** The dashboard should answer "do I need to go anywhere?" in one glance. If everything is healthy and the review queue is empty, you're done.

---

### Operations (`/operations`)

Single scrolling page. Sections:

1. **Pipeline status** — per-stage detail: status, throughput, avg duration, active count, errors, last error
2. **Watcher health** — per-directory status, state indicators
3. **Recent errors table** — last 50 pipeline errors (stage, file, message, time)
4. **Storage metrics** — disk usage per watch directory drive + image cache directory + database file size
5. **TMDB API integration** — rate limiter status (used/total/available), configuration status
6. **Configuration** — read-only reference of current config values (auto-approve threshold, MPV path, dirs, etc.)
7. **Logging toggles** — component-level log control (folded in from former `/logging` page)
8. **Danger zone** — clear database, clear & refresh image cache, scan directories

---

### Review (`/review`)

Visual refresh + UX improvement:
- **Better match comparison:** Side-by-side view of parsed filename info vs. TMDB result — with images, year, description, and enough context to make a confident approve/dismiss decision.

---

### Library (`/library`)

Visual refresh + structural improvements:
- **Better filtering/search:** Real search, genre filtering, year ranges (replacing the basic All/Movies/TV tabs).
- **Collapse/expand alignment:** Nested entities (TV → seasons → episodes) collapse toggles must not break the visual rhythm of the list. Expandable and non-expandable rows should look similar, with better alignment.

---

## Planned Data Requirements

Features requiring new backend tracking or computation:

| Feature | Location | Status | Implementation notes |
|---------|----------|--------|---------------------|
| Recent event feed | Dashboard | Planned | In-memory event buffer (like Stats.recent_errors pattern) |
| Library completeness | Dashboard | Planned | Ash queries: entities missing images, entities without identifiers |
| Auto-approve rate | Dashboard | Planned | Counter in Pipeline.Stats: auto_approved vs needs_review |
| Storage metrics | Operations | Done | `Storage.measure_all/0` — disk usage per watch dir, images dir, database |
| Last scan timestamp | Operations | Planned | Track in Watcher.Supervisor state or Stats |
