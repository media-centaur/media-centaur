# Recommend from search results — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person recommend a title straight from media-search results, by giving the title detail modal a Recommend control and making every search row open that modal.

**Architecture:** Two phases. Phase A moves the shared title surfaces out of the `Discovery` page namespace into `Components.Title.*` — pure renaming, no behaviour change. Phase B adds Recommend to `TitleDetailHost` (so Discovery and Incoming both gain it), and collapses the media-search row onto the shared title row so the modal is always one click away.

**Tech Stack:** Elixir, Phoenix LiveView, Phoenix Storybook, ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-08-recommend-from-search-design.md`

---

## Rules for this plan

- **Never run `mix` directly.** Every Mix command in this plan is `~/scripts/agents/agent-mix`. A bare `mix` in this checkout writes `.beam` files under the running dev server and can take it down.
- Tests are written before implementation. A test that has never failed proves nothing.
- `~/scripts/agents/agent-mix precommit` must pass before the last commit of each phase. Zero warnings.

## File structure

**Phase A — moved, contents unchanged apart from the module name:**

| From | To |
|---|---|
| `lib/media_centaur_web/components/discovery/pennant.ex` | `lib/media_centaur_web/components/title/pennant.ex` |
| `lib/media_centaur_web/components/discovery/intent_control.ex` | `lib/media_centaur_web/components/title/intent_control.ex` |
| `lib/media_centaur_web/components/discovery/title_row.ex` | `lib/media_centaur_web/components/title/row.ex` |
| `lib/media_centaur_web/components/discovery/title_detail.ex` | `lib/media_centaur_web/components/title/detail.ex` |
| `lib/media_centaur_web/components/discovery/title_detail_modal.ex` | `lib/media_centaur_web/components/title/detail_modal.ex` |
| `lib/media_centaur_web/live/discovery_live/logic.ex` | `lib/media_centaur_web/components/title/logic.ex` |
| `lib/media_centaur_web/live/discovery_live/recommend_modal.ex` | `lib/media_centaur_web/live/recommend_modal.ex` |
| `storybook/discovery/pennants.story.exs` | `storybook/title/pennant.story.exs` |
| `storybook/discovery/intent_control.story.exs` | `storybook/title/intent_control.story.exs` |
| `storybook/discovery/title_row.story.exs` | `storybook/title/row.story.exs` |
| `storybook/discovery/title_detail_modal.story.exs` | `storybook/title/detail_modal.story.exs` |
| `test/media_centaur_web/live/discovery_live/logic_test.exs` | `test/media_centaur_web/components/title/logic_test.exs` |

Created in Phase A: `storybook/title/_title.index.exs`.
Staying put: `components/discovery/person.ex`, `person_card.ex`, `storybook/discovery/person_card.story.exs`, `storybook/discovery/_discovery.index.exs`.

**Phase B — modified:**

| File | Responsibility after the change |
|---|---|
| `lib/media_centaur_web/components/title/logic.ex` | `row_markers/2`: membership fact is `in_library?`, the List rung says "On your list", `list_implied?` suppresses it |
| `lib/media_centaur_web/components/title/detail_modal.ex` | renders the `Recommend` control in the action strip |
| `lib/media_centaur_web/live/title_detail_host.ex` | seeds and drives `RecommendFlow` for both its hosts |
| `lib/media_centaur_web/live/recommend_flow.ex` | moduledoc: second injector, mutual exclusion |
| `lib/media_centaur_web/components/acquisition/media_results.ex` | list shell only — chips, Clear, empty states; rows are `Title.Row` |
| `lib/media_centaur_web/live/discovery_live.ex` | renders the Recommend modal; watchlist tab passes `list_implied?` |
| `lib/media_centaur_web/live/incoming_live.ex` | renders the Recommend modal; `default_grab_mode` assign; `omnibox_pick` and `watchlist_toggle` deleted |

---

# Phase A — the namespace split

Each task is one module, references updated repo-wide, suite green, commit. No behaviour changes anywhere in Phase A: the existing suite passing **is** the assertion.

### Task A1: Move `Pennant`

**Files:**
- Move: `lib/media_centaur_web/components/discovery/pennant.ex` → `lib/media_centaur_web/components/title/pennant.ex`
- Move: `storybook/discovery/pennants.story.exs` → `storybook/title/pennant.story.exs`
- Create: `storybook/title/_title.index.exs`
- Modify: `storybook/discovery/_discovery.index.exs`

- [ ] **Step 1: Create the new directories and move the files**

```bash
cd ~/src/media-centaur/media-centaur-app
mkdir -p lib/media_centaur_web/components/title storybook/title
git mv lib/media_centaur_web/components/discovery/pennant.ex lib/media_centaur_web/components/title/pennant.ex
git mv storybook/discovery/pennants.story.exs storybook/title/pennant.story.exs
```

- [ ] **Step 2: Rename the modules repo-wide**

```bash
grep -rl 'Components\.Discovery\.Pennant' lib test storybook \
  | xargs sed -i 's/Components\.Discovery\.Pennant/Components.Title.Pennant/g'
sed -i 's/MediaCentaurWeb\.Storybook\.Discovery\.Pennant/MediaCentaurWeb.Storybook.Title.Pennant/' \
  storybook/title/pennant.story.exs
```

- [ ] **Step 3: Create the storybook folder index**

Create `storybook/title/_title.index.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Title do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "film", :light, "psb:mr-1"}

  def entry("pennant"), do: [icon: {:fa, "flag-pennant", :thin}, name: "Pennant"]
end
```

- [ ] **Step 4: Drop the moved entry from the Discovery index**

In `storybook/discovery/_discovery.index.exs`, delete this line and the blank line after it:

```elixir
  def entry("pennants"), do: [icon: {:fa, "flag-pennant", :thin}, name: "Pennant"]
```

- [ ] **Step 5: Compile and run the suite**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test`
Expected: compiles with no warnings; the full suite passes exactly as before.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: move Pennant into the page-neutral Title component namespace

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task A2: Move `IntentControl`

**Files:**
- Move: `lib/media_centaur_web/components/discovery/intent_control.ex` → `lib/media_centaur_web/components/title/intent_control.ex`
- Move: `storybook/discovery/intent_control.story.exs` → `storybook/title/intent_control.story.exs`
- Modify: `storybook/title/_title.index.exs`, `storybook/discovery/_discovery.index.exs`

- [ ] **Step 1: Move the files**

```bash
git mv lib/media_centaur_web/components/discovery/intent_control.ex lib/media_centaur_web/components/title/intent_control.ex
git mv storybook/discovery/intent_control.story.exs storybook/title/intent_control.story.exs
```

- [ ] **Step 2: Rename the modules repo-wide**

```bash
grep -rl 'Components\.Discovery\.IntentControl' lib test storybook \
  | xargs sed -i 's/Components\.Discovery\.IntentControl/Components.Title.IntentControl/g'
sed -i 's/MediaCentaurWeb\.Storybook\.Discovery\.IntentControl/MediaCentaurWeb.Storybook.Title.IntentControl/' \
  storybook/title/intent_control.story.exs
```

Note: the test module `MediaCentaurWeb.Components.Discovery.IntentControlTest` is renamed by the same sed. Move its file too:

```bash
git mv test/media_centaur_web/components/discovery/intent_control_test.exs \
       test/media_centaur_web/components/title/intent_control_test.exs 2>/dev/null || true
```

If the `git mv` reports no such file, the test lives elsewhere — find it with `grep -rl IntentControlTest test` and move it to the matching path under `test/media_centaur_web/components/title/`.

- [ ] **Step 3: Move the entry between indexes**

Add to `storybook/title/_title.index.exs`, after the `pennant` entry:

```elixir
  def entry("intent_control"), do: [icon: {:fa, "sliders", :thin}, name: "Intent control"]
```

Delete the same `entry("intent_control")` clause from `storybook/discovery/_discovery.index.exs`.

- [ ] **Step 4: Compile and run the suite**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test`
Expected: no warnings, suite green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: move IntentControl into the Title component namespace

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task A3: Move `TitleRow` → `Components.Title.Row`

**Files:**
- Move: `lib/media_centaur_web/components/discovery/title_row.ex` → `lib/media_centaur_web/components/title/row.ex`
- Move: `storybook/discovery/title_row.story.exs` → `storybook/title/row.story.exs`
- Modify: both storybook indexes, `lib/media_centaur_web/live/discovery_live.ex`

- [ ] **Step 1: Move the files**

```bash
git mv lib/media_centaur_web/components/discovery/title_row.ex lib/media_centaur_web/components/title/row.ex
git mv storybook/discovery/title_row.story.exs storybook/title/row.story.exs
```

- [ ] **Step 2: Rename the modules repo-wide**

```bash
grep -rl 'Components\.Discovery\.TitleRow' lib test storybook \
  | xargs sed -i 's/Components\.Discovery\.TitleRow/Components.Title.Row/g'
sed -i 's/MediaCentaurWeb\.Storybook\.Discovery\.TitleRow/MediaCentaurWeb.Storybook.Title.Row/' \
  storybook/title/row.story.exs
```

- [ ] **Step 3: Fix the alias-derived call sites**

`discovery_live.ex` aliases the module and calls `<TitleRow.title_row .../>`. The sed above rewrote the alias target but not the local name. Update the alias so the local name matches the module:

```bash
sed -i 's/alias MediaCentaurWeb\.Components\.Title\.Row$/alias MediaCentaurWeb.Components.Title.Row, as: TitleRow/' \
  lib/media_centaur_web/live/discovery_live.ex
```

Then confirm nothing else referenced it:

Run: `grep -rn "TitleRow" lib storybook`
Expected: only `discovery_live.ex`'s alias line and its two `<TitleRow.title_row` call sites.

- [ ] **Step 4: Move the storybook entry**

Add to `storybook/title/_title.index.exs`:

```elixir
  def entry("row"), do: [icon: {:fa, "bookmark", :thin}, name: "Title row"]
```

Delete `def entry("title_row"), do: [icon: {:fa, "bookmark", :thin}, name: "Title row"]` from `storybook/discovery/_discovery.index.exs`.

- [ ] **Step 5: Compile and run the suite**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test`
Expected: no warnings, suite green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: move the title row into the Title component namespace

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task A4: Move `TitleDetail` → `Components.Title.Detail`

**Files:**
- Move: `lib/media_centaur_web/components/discovery/title_detail.ex` → `lib/media_centaur_web/components/title/detail.ex`

`TitleDetail` is a struct module (a view-model), not a function component — it has no story.

- [ ] **Step 1: Move the file**

```bash
git mv lib/media_centaur_web/components/discovery/title_detail.ex lib/media_centaur_web/components/title/detail.ex
```

- [ ] **Step 2: Rename the module repo-wide**

The name `Components.Discovery.TitleDetailModal` shares a prefix with `Components.Discovery.TitleDetail`, so anchor the substitution on a word boundary to avoid mangling it:

```bash
grep -rl 'Components\.Discovery\.TitleDetail\b' lib test storybook \
  | xargs sed -i 's/Components\.Discovery\.TitleDetail\b/Components.Title.Detail/g'
```

- [ ] **Step 3: Fix the alias-derived call sites**

Modules aliased it as `TitleDetail` and pattern-match on `%TitleDetail{}`. Keep the local name:

```bash
grep -rl 'alias MediaCentaurWeb\.Components\.Title\.Detail$' lib test \
  | xargs sed -i 's/alias MediaCentaurWeb\.Components\.Title\.Detail$/alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail/'
```

Run: `grep -rn "Components.Title.Detail" lib test | grep -v "as: TitleDetail"`
Expected: only `Components.Title.DetailModal` references (untouched, still named `TitleDetailModal` until Task A5) and the moved file's own `defmodule`.

- [ ] **Step 4: Compile and run the suite**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test`
Expected: no warnings, suite green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: move the title detail view-model into the Title namespace

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task A5: Move `TitleDetailModal` → `Components.Title.DetailModal`

**Files:**
- Move: `lib/media_centaur_web/components/discovery/title_detail_modal.ex` → `lib/media_centaur_web/components/title/detail_modal.ex`
- Move: `storybook/discovery/title_detail_modal.story.exs` → `storybook/title/detail_modal.story.exs`

- [ ] **Step 1: Move the files**

```bash
git mv lib/media_centaur_web/components/discovery/title_detail_modal.ex lib/media_centaur_web/components/title/detail_modal.ex
git mv storybook/discovery/title_detail_modal.story.exs storybook/title/detail_modal.story.exs
```

- [ ] **Step 2: Rename the modules repo-wide**

```bash
grep -rl 'Components\.Discovery\.TitleDetailModal' lib test storybook \
  | xargs sed -i 's/Components\.Discovery\.TitleDetailModal/Components.Title.DetailModal/g'
sed -i 's/MediaCentaurWeb\.Storybook\.Discovery\.TitleDetailModal/MediaCentaurWeb.Storybook.Title.DetailModal/' \
  storybook/title/detail_modal.story.exs
```

- [ ] **Step 3: Keep the local alias name**

```bash
grep -rl 'alias MediaCentaurWeb\.Components\.Title\.DetailModal$' lib test \
  | xargs sed -i 's/alias MediaCentaurWeb\.Components\.Title\.DetailModal$/alias MediaCentaurWeb.Components.Title.DetailModal, as: TitleDetailModal/'
```

- [ ] **Step 4: Move the storybook entry**

Add to `storybook/title/_title.index.exs`:

```elixir
  def entry("detail_modal"),
    do: [icon: {:fa, "window-maximize", :thin}, name: "Title detail modal"]
```

Delete the `entry("title_detail_modal")` clause from `storybook/discovery/_discovery.index.exs`.

- [ ] **Step 5: Compile and run the suite**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test`
Expected: no warnings, suite green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: move the title detail modal into the Title namespace

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task A6: Move `DiscoveryLive.Logic` → `Components.Title.Logic`

**Files:**
- Move: `lib/media_centaur_web/live/discovery_live/logic.ex` → `lib/media_centaur_web/components/title/logic.ex`
- Move: `test/media_centaur_web/live/discovery_live/logic_test.exs` → `test/media_centaur_web/components/title/logic_test.exs`

- [ ] **Step 1: Move the files**

```bash
mkdir -p test/media_centaur_web/components/title
git mv lib/media_centaur_web/live/discovery_live/logic.ex lib/media_centaur_web/components/title/logic.ex
git mv test/media_centaur_web/live/discovery_live/logic_test.exs test/media_centaur_web/components/title/logic_test.exs
```

- [ ] **Step 2: Rename the modules repo-wide**

```bash
grep -rl 'MediaCentaurWeb\.DiscoveryLive\.Logic' lib test storybook \
  | xargs sed -i 's/MediaCentaurWeb\.DiscoveryLive\.Logic/MediaCentaurWeb.Components.Title.Logic/g'
```

`discovery_live.ex` and `title_detail_host.ex` alias it as `Logic`; the sed rewrote the alias target and left the local name `Logic` intact, which still works. Verify:

Run: `grep -rn "Components.Title.Logic" lib test`
Expected: the `defmodule`, the test's `alias`, and one `alias` line each in `discovery_live.ex`, `title_detail_host.ex`, `components/title/detail_modal.ex`, `components/title/row.ex`.

- [ ] **Step 3: Reword the moduledoc, which still claims to be the Discovery page's**

In `lib/media_centaur_web/components/title/logic.ex`, replace the moduledoc with:

```elixir
  @moduledoc """
  Pure decisions for the title surfaces (ADR-030) — the ones Discovery
  and Incoming share: the title detail view-model, the acquisition-state
  words the rows and the modal show, the row markers, and a watchlist
  row's next release date. Discovery's own two tab projections live
  beside its LiveView: `RecommendationRows` and `People`.
  """
```

- [ ] **Step 4: Compile and run the suite**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test`
Expected: no warnings, suite green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: move the title presentation logic out of DiscoveryLive

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task A7: Move `DiscoveryLive.RecommendModal` → `Live.RecommendModal`

It stays under `live/`, beside the `RecommendFlow` whose assigns it renders — MC0009 requires a story for every function component under `components/**`, and this modal's contract is the flow's.

**Files:**
- Move: `lib/media_centaur_web/live/discovery_live/recommend_modal.ex` → `lib/media_centaur_web/live/recommend_modal.ex`

- [ ] **Step 1: Move the file**

```bash
git mv lib/media_centaur_web/live/discovery_live/recommend_modal.ex lib/media_centaur_web/live/recommend_modal.ex
```

- [ ] **Step 2: Rename the module repo-wide**

```bash
grep -rl 'MediaCentaurWeb\.DiscoveryLive\.RecommendModal' lib test storybook \
  | xargs sed -i 's/MediaCentaurWeb\.DiscoveryLive\.RecommendModal/MediaCentaurWeb.Live.RecommendModal/g'
```

The hosts alias it as `RecommendModal`, which the sed leaves working.

- [ ] **Step 3: Reword the moduledoc's host list, which names Discovery as the watchlist host**

In `lib/media_centaur_web/live/recommend_modal.ex`, replace this sentence:

```elixir
  `recommend_send` (form submit) and `recommend_cancel` bubble to the
  host, which is `DiscoveryLive` for watchlist rows and any `EntityModal`
  host for the library detail page.
```

with:

```elixir
  `recommend_send` (form submit) and `recommend_cancel` bubble to the
  host: any `EntityModal` host for a title with files, any
  `TitleDetailHost` host for one without.
```

- [ ] **Step 4: Compile and run the suite**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test`
Expected: no warnings, suite green.

- [ ] **Step 5: Run the full gate**

Run: `~/scripts/agents/agent-mix precommit`
Expected: PASS. Storybook compile and render tests confirm every moved story still resolves.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: move the recommend modal beside its flow

Four hosts render it and only one was Discovery. It sits with
Live.RecommendFlow, whose assigns it renders.

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task A8: Sweep the contributor docs and skills

The renaming `grep`s in A1–A7 covered `lib test storybook` only. Prose outside those trees names the moved modules and their storybook paths, and is now wrong. Known at the time of writing (re-grep, do not trust this list):

- `docs/GLOSSARY.md` — the **Title detail modal** row names `Components.Discovery.TitleDetailModal`, view-model `TitleDetail`, and calls the surface "The Discovery page's".
- `docs/social.md` — names `Components.Discovery.Pennant`.
- `.claude/skills/user-interface/SKILL.md` — names `Components.Discovery.Pennant` and the story path `/storybook/discovery/pennants`.

**Files:** whatever the sweep finds outside `lib test storybook`, excluding `docs/superpowers/**` (historical planning docs, explicitly not maintained against current code per `CLAUDE.md`).

- [ ] **Step 1: Find every stale reference**

```bash
cd ~/src/media-centaur/media-centaur-app
grep -rn "Components\.Discovery\.\(Pennant\|IntentControl\|TitleRow\|TitleDetail\|TitleDetailModal\)\|DiscoveryLive\.Logic\|DiscoveryLive\.RecommendModal\|storybook/discovery/\(pennants\|intent_control\|title_row\|title_detail_modal\)" \
  . --include='*.md' --include='*.ex' --include='*.exs' \
  | grep -v '^\./docs/superpowers/' | grep -v '^\./_build/' | grep -v '^\./deps/'
```

- [ ] **Step 2: Fix each hit**

Rewrite each to the new name and path:

| Old | New |
|---|---|
| `Components.Discovery.Pennant` | `Components.Title.Pennant` |
| `Components.Discovery.IntentControl` | `Components.Title.IntentControl` |
| `Components.Discovery.TitleRow` | `Components.Title.Row` |
| `Components.Discovery.TitleDetail` | `Components.Title.Detail` |
| `Components.Discovery.TitleDetailModal` | `Components.Title.DetailModal` |
| `MediaCentaurWeb.DiscoveryLive.Logic` | `MediaCentaurWeb.Components.Title.Logic` |
| `MediaCentaurWeb.DiscoveryLive.RecommendModal` | `MediaCentaurWeb.Live.RecommendModal` |
| `/storybook/discovery/pennants` | `/storybook/title/pennant` |
| `/storybook/discovery/intent_control` | `/storybook/title/intent_control` |
| `/storybook/discovery/title_row` | `/storybook/title/row` |
| `/storybook/discovery/title_detail_modal` | `/storybook/title/detail_modal` |

In `docs/GLOSSARY.md`, also fix the prose: the title detail modal is not "The Discovery page's" surface — it is the depth surface for a TMDB title the library does not own, hosted by Discovery **and** Incoming through `Live.TitleDetailHost`. Change the sentence "Every Discovery verb lives here." to "Every verb on such a title lives here."

- [ ] **Step 3: Re-run the sweep**

Run the Step 1 command again.
Expected: no output.

- [ ] **Step 4: Run the gate**

Run: `~/scripts/agents/agent-mix precommit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs: follow the title surfaces out of the Discovery namespace

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

---

---

# Phase B — the feature

### Task B1: `row_markers/2` — membership, the List rung, and the container's implication

`row_markers` needs to know *whether* the library owns the title, not *who* owns it. Discovery passes an owner id today only because it has one; Incoming has a `MapSet` of refs and no id. Take the honest fact.

**Files:**
- Modify: `lib/media_centaur_web/components/title/logic.ex`
- Modify: `lib/media_centaur_web/live/discovery_live.ex:436`, `:497`
- Test: `test/media_centaur_web/components/title/logic_test.exs`

- [ ] **Step 1: Write the failing tests**

In `test/media_centaur_web/components/title/logic_test.exs`, replace the three `describe "row_markers/1..."` blocks (they run from `describe "row_markers/1" do` to the end of the `row_markers/1 next release` block) with:

```elixir
  describe "row_markers/2" do
    test "in library wins, then the acquisition state" do
      assert Logic.row_markers(%{
               in_library?: true,
               acquisition_state: :downloading,
               rung: :list
             }) == ["In library"]

      assert Logic.row_markers(%{
               in_library?: false,
               acquisition_state: :needs_review,
               rung: :list
             }) == ["Needs review", "On your list"]

      assert Logic.row_markers(%{
               in_library?: false,
               acquisition_state: nil,
               rung: nil
             }) == []
    end
  end

  describe "row_markers/2 tracking" do
    test "a listed or followed title states its rung, Default resolved; Off and owned say nothing" do
      base = %{in_library?: false, acquisition_state: nil, rung: nil}

      assert Logic.row_markers(Map.merge(base, %{rung: :follow, default_grab_mode: "ask"})) ==
               ["Tracking: Follow"]

      assert Logic.row_markers(Map.merge(base, %{rung: :default, default_grab_mode: "ask"})) ==
               ["Tracking: Ask"]

      assert Logic.row_markers(Map.merge(base, %{rung: :default, default_grab_mode: "off"})) ==
               ["Tracking: Follow"]

      assert Logic.row_markers(Map.merge(base, %{rung: :list, default_grab_mode: "ask"})) ==
               ["On your list"]

      assert Logic.row_markers(Map.merge(base, %{rung: nil, default_grab_mode: "ask"})) == []

      assert Logic.row_markers(
               Map.merge(base, %{in_library?: true, rung: :grab, default_grab_mode: "ask"})
             ) == ["In library"]
    end

    test "list_implied? drops only the List marker" do
      base = %{in_library?: false, acquisition_state: nil, rung: nil, default_grab_mode: "ask"}

      assert Logic.row_markers(Map.put(base, :rung, :list), true) == []
      assert Logic.row_markers(Map.put(base, :rung, :follow), true) == ["Tracking: Follow"]
    end
  end

  describe "row_markers/2 next release" do
    test "a watchlist row states its next date when it has one" do
      assert Logic.row_markers(%{
               in_library?: false,
               acquisition_state: nil,
               rung: nil,
               next_air_date: Date.add(@today, 1),
               today: @today
             }) == ["Next: Tomorrow"]

      assert Logic.row_markers(%{
               in_library?: false,
               acquisition_state: :planning,
               rung: nil,
               next_air_date: nil,
               today: @today
             }) == ["Planning"]
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs`
Expected: FAIL — `KeyError: key :in_library? not found` from `row_markers/1`.

- [ ] **Step 3: Rewrite `row_markers` and `rung_marker`**

In `lib/media_centaur_web/components/title/logic.ex`, replace the `row_markers/1` doc, spec and body plus the four `rung_marker/2` clauses with:

```elixir
  @doc """
  The quiet text markers a title row shows after its type and year, in
  order: the library or acquisition state (one of them — In library
  wins), then the tracking rung (`rung` + `default_grab_mode`, Default
  resolved to what it does; never for an owned title, whose tracking is
  the library detail's) and the next release date when the facts carry
  one (`next_air_date` + `today`).

  `list_implied?` is a fact about the *container*, not the title: pass
  true where every row is on the list — Discovery's watchlist tab — and
  the List rung's own marker is dropped as redundant. Everywhere else a
  listed title says so, which is the only place a search result can.

  Who recommended the title is the pennant's, and a feed row's
  sender/when line is the host's; neither is a marker.
  """
  @spec row_markers(
          %{
            required(:in_library?) => boolean(),
            required(:acquisition_state) => acquisition_state(),
            optional(:rung) => TitleIntent.rung() | nil,
            optional(:default_grab_mode) => String.t(),
            optional(:next_air_date) => Date.t() | nil,
            optional(:today) => Date.t()
          },
          boolean()
        ) :: [String.t()]
  def row_markers(facts, list_implied? \\ false) do
    state =
      cond do
        facts.in_library? -> "In library"
        marker = acquisition_marker(facts.acquisition_state) -> marker
        true -> nil
      end

    tracking =
      if not facts.in_library? do
        rung_marker(Map.get(facts, :rung), Map.get(facts, :default_grab_mode), list_implied?)
      end

    next =
      case Map.get(facts, :next_air_date) do
        %Date{} = date -> "Next: " <> Present.relative_day(date, Map.fetch!(facts, :today))
        nil -> nil
      end

    Enum.reject([state, tracking, next], &is_nil/1)
  end

  # Off says nothing — the row would not be here. List says it is on the
  # list, except where the container already says so. Default says what
  # it resolves to, so the row never asks the reader to know the setting.
  defp rung_marker(nil, _default, _list_implied?), do: nil
  defp rung_marker(:list, _default, true), do: nil
  defp rung_marker(:list, _default, false), do: "On your list"
  defp rung_marker(:follow, _default, _list_implied?), do: "Tracking: Follow"
  defp rung_marker(:ask, _default, _list_implied?), do: "Tracking: Ask"
  defp rung_marker(:grab, _default, _list_implied?), do: "Tracking: Grab"

  defp rung_marker(:default, default, _list_implied?) do
    case TitleIntent.grab_mode(:default, default) do
      "all_releases" -> "Tracking: Grab"
      "ask" -> "Tracking: Ask"
      _off -> "Tracking: Follow"
    end
  end
```

- [ ] **Step 4: Update Discovery's two call sites**

In `lib/media_centaur_web/live/discovery_live.ex`, the recommendations tab (around line 436) becomes:

```heex
              markers={
                Logic.row_markers(%{
                  in_library?: not is_nil(row.library_owner_id),
                  acquisition_state: row.acquisition_state,
                  rung: row.rung
                })
              }
```

and the watchlist tab (around line 497) becomes:

```heex
              markers={
                Logic.row_markers(
                  %{
                    in_library?: not is_nil(row.library_owner_id),
                    acquisition_state: row.acquisition_state,
                    rung: row.rung,
                    default_grab_mode: @default_grab_mode,
                    next_air_date: row.next_air_date,
                    today: @today
                  },
                  true
                )
              }
```

- [ ] **Step 5: Pin the two tabs apart at the page level**

Add to `test/media_centaur_web/live/discovery_live_test.exs`, beside the nearest test that already seeds a watchlist row (find one with `grep -n "watchlist-item-" test/media_centaur_web/live/discovery_live_test.exs` and reuse its setup):

```elixir
    test "the watchlist tab does not tell you a row is on the watchlist", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/discovery/watchlist")

      assert has_element?(view, "[id^='watchlist-item-']")
      refute html =~ "On your list"
    end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs test/media_centaur_web/live/discovery_live_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: a listed title says so, except where the list itself says it

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task B2: The Recommend control in the title detail modal

**Files:**
- Modify: `lib/media_centaur_web/components/title/detail_modal.ex`
- Modify: `storybook/title/detail_modal.story.exs`
- Test: `test/media_centaur_web/live/discovery_live_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur_web/live/discovery_live_test.exs`, inside the outermost `describe` block that already opens the title detail modal (find it with `grep -n "title-detail-modal" test/media_centaur_web/live/discovery_live_test.exs` and place the test beside the nearest one):

```elixir
    test "the Recommend control follows the friend-network preference", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/discovery/watchlist")

      # Open whatever row this test module's setup put on the watchlist.
      view
      |> element("[data-component='title-row']")
      |> render_click()

      # `show_discovery` is default-off: Discovery is a preview, and
      # Recommend is the one control on this modal that belongs to it.
      refute has_element?(view, "#title-recommend")

      MediaCentaur.Settings.find_or_create_entry!(%{
        key: MediaCentaur.Settings.Preferences.DiscoveryVisibility.setting_key(),
        value: %{"enabled" => true}
      })

      render_until(view, fn _html -> has_element?(view, "#title-recommend") end)
    end
```

If the module's setup does not seed a watchlist row, copy the setup from the nearest test that asserts on `#title-detail-modal`.

**`show_discovery` defaults to off** (`MediaCentaur.Settings.Preferences.DiscoveryVisibility`), so every test in this plan that expects `#title-recommend` to render must write that entry first. The `render_until` above is how `home_live_test.exs` waits for the session-wide `SettingAware` hook to re-assign after the broadcast.

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs`
Expected: FAIL — no element matching `#title-recommend`.

- [ ] **Step 3: Add the attr**

In `lib/media_centaur_web/components/title/detail_modal.ex`, beside the component's other `attr` declarations for `title_detail_modal/1`:

```elixir
  attr :recommend?, :boolean,
    default: false,
    doc:
      "whether the Recommend control is offered — the hosts pass `show_discovery`, the preference that gates the whole friend-network preview."
```

- [ ] **Step 4: Render the control in the action strip**

In the same file, the action strip currently reads:

```heex
              <div class="flex flex-wrap items-center gap-3" data-nav-zone="title_detail_body">
                <.primary detail={@detail} scope_menu_open={@scope_menu_open} />
                <.tertiary detail={@detail} />
              </div>
```

Replace it with:

```heex
              <%!-- Recommend joins the strip's left cluster, after the
                    primary and before the `ml-auto` tertiary group. A text
                    control, not the library panel's paper-plane: this strip
                    speaks in words where that controls row is an icon
                    cluster. Same act, each surface's own idiom. --%>
              <div class="flex flex-wrap items-center gap-3" data-nav-zone="title_detail_body">
                <.primary detail={@detail} scope_menu_open={@scope_menu_open} />
                <button
                  :if={@recommend?}
                  id="title-recommend"
                  type="button"
                  class="cursor-pointer text-sm text-base-content/70 transition-colors hover:text-base-content/90"
                  phx-click="title_recommend_open"
                  data-nav-item
                  tabindex="0"
                >
                  Recommend
                </button>
                <.tertiary detail={@detail} />
              </div>
```

- [ ] **Step 5: Pass the gate from both hosts**

In `lib/media_centaur_web/live/discovery_live.ex` (around line 377) and `lib/media_centaur_web/live/incoming_live.ex` (its `<TitleDetailModal.title_detail_modal` call — find it with `grep -n "title_detail_modal" lib/media_centaur_web/live/incoming_live.ex`), add one attribute to each:

```heex
          recommend?={@show_discovery}
```

- [ ] **Step 6: Add the storybook variation**

In `storybook/title/detail_modal.story.exs`, add a variation to the existing `variations/0` list, matching the shape of the ones already there and adding `recommend?: true` to its attributes. Name it `:with_recommend` with `description: "Friend network on — the strip offers Recommend"`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/storybook_render_test.exs test/storybook_compile_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: the title detail modal offers Recommend

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task B3: Wire `RecommendFlow` into `TitleDetailHost`

**Files:**
- Modify: `lib/media_centaur_web/live/title_detail_host.ex`
- Modify: `lib/media_centaur_web/live/recommend_flow.ex` (moduledoc only)
- Modify: `lib/media_centaur_web/live/discovery_live.ex`, `lib/media_centaur_web/live/incoming_live.ex`
- Test: `test/media_centaur_web/live/incoming_live_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur_web/live/incoming_live_test.exs`, inside the `describe "omnibox — one search surface, two modes (UIDR-014)"` block:

```elixir
    test "a search result can be recommended from its detail modal", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_search_multi([
        %{
          "id" => 424_242,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        }
      ])

      # Recommend is gated on the default-off friend-network preview.
      MediaCentaur.Settings.find_or_create_entry!(%{
        key: MediaCentaur.Settings.Preferences.DiscoveryVisibility.setting_key(),
        value: %{"enabled" => true}
      })

      {:ok, view, _html} = live_async!(conn, ~p"/incoming")

      view
      |> form("form[phx-change='omnibox_change']", %{query: "sample"})
      |> render_change()

      render_async(view, 2_000)

      view |> element("#omnibox-result-movie-424242") |> render_click()
      assert_patch(view, "/incoming?title=movie-424242")

      view |> element("#title-recommend") |> render_click()
      assert has_element?(view, "#recommend-modal[data-state='open']", "Sample Movie")

      render_submit(view, "recommend_send", %{"sentiment" => "love", "note" => "Worth it"})

      refute has_element?(view, "#recommend-modal[data-state='open']")

      assert [recommendation] = MediaCentaur.Activities.list_own()
      assert recommendation.kind == :recommendation
      assert recommendation.tmdb_id == 424_242

      await_supervised_tasks()
    end
```

Before running, confirm the reader function's name: `grep -n "def list_own\|def list_" lib/media_centaur/activities.ex`. Use the function that returns the user's own activities; if it takes options, pass what the existing `activities` tests pass.

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs`
Expected: FAIL — no element matching `#title-recommend` (the gate is on, but the host has no `recommend_subject` assign and no modal rendered).

- [ ] **Step 3: Inject the flow from the host contract**

In `lib/media_centaur_web/live/title_detail_host.ex`, the `__using__` macro becomes:

```elixir
  defmacro __using__(_opts) do
    quote do
      @behaviour MediaCentaurWeb.Live.TitleDetailHost

      use MediaCentaurWeb.Live.RecommendFlow

      on_mount {MediaCentaurWeb.Live.TitleDetailHost, :default}
    end
  end
```

- [ ] **Step 4: Seed the flow's assigns and register the event**

In the same file, add the alias beside the others:

```elixir
  alias MediaCentaurWeb.Live.RecommendFlow
```

Change `on_mount/4`'s assign chain to seed the flow:

```elixir
    socket =
      socket
      |> assign(title_detail: nil, scope_menu_open: false)
      |> RecommendFlow.init()
      |> attach_hook(:title_detail_params, :handle_params, &apply_title_params/3)
      |> attach_hook(:title_detail_events, :handle_event, &handle_title_event/3)
      |> attach_hook(:title_detail_async, :handle_async, &handle_title_async/3)
      |> attach_hook(:title_detail_pubsub, :handle_info, &handle_title_info/2)
```

Add `title_recommend_open` to the stale-click list:

```elixir
  @modal_events ~w(title_scope_toggle title_scope_close title_download title_activity_delete title_recommend_open)
```

And add the opening clause immediately before the `@modal_events` catch-all clause (`def handle_title_event(event, _params, socket) when event in @modal_events`):

```elixir
  # The artwork is the detail's own — already resolved on open and
  # refreshed by the live preview. Deriving it again here would be a
  # second source for one value.
  def handle_title_event(
        "title_recommend_open",
        _params,
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ),
      do: {:halt, RecommendFlow.open(socket, detail.title, detail.poster_url)}
```

- [ ] **Step 5: Render the modal from both hosts**

In `lib/media_centaur_web/live/discovery_live.ex`, inside `<:overlays>` after the title detail modal:

```heex
        <RecommendModal.recommend_modal
          subject={@recommend_subject}
          poster_url={@recommend_poster_url}
          relay_counts={@recommend_relay_counts}
        />
```

Add the alias if the module does not have one:

```elixir
  alias MediaCentaurWeb.Live.RecommendModal
```

Do exactly the same in `lib/media_centaur_web/live/incoming_live.ex`, inside its `<:overlays>` slot.

- [ ] **Step 6: Record the contract in both moduledocs**

In `lib/media_centaur_web/live/title_detail_host.ex`, add a row to the host-contract table:

```
  | `use RecommendFlow` | injects the Recommend modal's own controls; `title_recommend_open` opens it on the detail's title |
```

and, after the table:

```
  A host that `use`s this module must not also `use` `EntityModal`: both
  inject `RecommendFlow`, and the duplicated clauses and `init/1` seed
  would collide.
```

In `lib/media_centaur_web/live/recommend_flow.ex`, extend the `## Host contract` section with:

```
  Two modules inject this flow: `EntityModal`, for a title with files,
  and `TitleDetailHost`, for one without. A LiveView may `use` one or
  the other, never both — the injected clauses and the `init/1` seed
  would collide.
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/live/discovery_live_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: recommend a title from any surface that hosts its detail

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task B4: Every search row opens the title detail modal

This is the behaviour change. The row stops carrying a verb and a bookmark; `omnibox_pick` and `watchlist_toggle` are deleted.

**Files:**
- Modify: `lib/media_centaur_web/components/acquisition/media_results.ex`
- Modify: `lib/media_centaur_web/live/incoming_live.ex`
- Test: `test/media_centaur_web/live/incoming_live_test.exs`

- [ ] **Step 1: Rewrite the two existing tests that assert the old behaviour**

In `test/media_centaur_web/live/incoming_live_test.exs`:

a) In the no-indexer test (around line 145), delete this line — the row no longer carries a verb:

```elixir
      assert has_element?(view, "#omnibox-result-movie-424242", "More info")
```

b) Rename the test at the top of the `describe "omnibox — …"` block from
`"typing in media mode surfaces TMDB results; picking patches into the plan flow"`
to
`"typing in media mode surfaces TMDB results; picking opens the title detail"`,
and replace its final assertion:

```elixir
      # Picking a result opens the plan flow via URL patch (refresh-safe).
      view
      |> element("#omnibox-result-tv_series-246810")
      |> render_click()

      assert_patch(view, "/incoming?plan=new&tmdb_id=246810&tmdb_type=tv")
```

with:

```elixir
      # Every pick lands on the title detail; Download lives inside it.
      view
      |> element("#omnibox-result-tv_series-246810")
      |> render_click()

      assert_patch(view, "/incoming?title=tv_series-246810")
      assert has_element?(view, "#title-detail-modal[data-state='open']", "Sample Show")
      refute has_element?(view, "#plan-modal[data-state='open']")

      await_supervised_tasks()
```

d) Add, to the same describe block, the assertion that a search row now carries the input system's overlay-restore origin — without it the nav cursor is dropped every time the modal closes:

```elixir
    test "a search row carries the overlay-restore origin", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_search_multi([
        %{
          "id" => 424_242,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        }
      ])

      {:ok, view, _html} = live_async!(conn, ~p"/incoming")

      view
      |> form("form[phx-change='omnibox_change']", %{query: "sample"})
      |> render_change()

      render_async(view, 2_000)

      assert has_element?(view, "#omnibox-result-movie-424242[data-entity-id='movie-424242']")

      await_supervised_tasks()
    end
```

e) Add a marker test to the same describe block:

```elixir
    test "a search result states what the library and the ladder already know", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_search_multi([
        %{
          "id" => 424_242,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        }
      ])

      {:ok, _intent} =
        MediaCentaur.Discovery.set_rung(
          MediaCentaur.TMDB.Title.new!(%{
            tmdb_id: 424_242,
            media_type: :movie,
            name: "Sample Movie"
          }),
          :list
        )

      {:ok, view, _html} = live_async!(conn, ~p"/incoming")

      view
      |> form("form[phx-change='omnibox_change']", %{query: "sample"})
      |> render_change()

      assert render_async(view, 2_000) =~ "On your list"

      await_supervised_tasks()
    end
```

Before running, confirm the intent writer's name and arity: `grep -n "def set_rung" lib/media_centaur/discovery.ex lib/media_centaur/release_tracking.ex`. Use the one the modal's `set_rung` handler calls (`ReleaseTracking.set_rung/3` per `TitleDetailHost`'s moduledoc) and pass what it expects.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs`
Expected: FAIL — the pick still patches to `/incoming?plan=new&…`, and no row renders `On your list`.

- [ ] **Step 3: Make `MediaResults` a list shell over the shared row**

In `lib/media_centaur_web/components/acquisition/media_results.ex`, replace the moduledoc with:

```elixir
  @moduledoc """
  Flat media-search results — the TMDB answer sheet rendered as page
  content below the omnibox hero (UIDR-014). No floating overlay: the
  section exists exactly while the typed query is active
  (`active_query?/1`), and clearing the query is the one dismissal —
  no click-away, nothing to lose track of.

  While it renders, the search owns the page: the host hides the
  forecast, the same convention as the release-search zone — whose
  `grid` nav zone the result rows reuse (the two modes are exclusive,
  so only one grid exists at a time). The header strip (scope chips +
  Clear) is its own `toolbar` nav zone.

  This module owns the list, not the row. Each result is a
  `Components.Title.Row` — identity, quiet markers, the whole card
  opening the title detail modal, where every verb lives (spec
  2026-09-05 §14). Media search was the last surface still carrying its
  own verb; it no longer does, so a search result and a Discovery row
  are the same row.

  Pure rendering; events bubble to the parent LiveView (`open_title`
  from the row, `omnibox_clear` and `omnibox_scope` from the header).
  """
```

Replace the imports block's `title_summary` and `pennants` imports — the row owns both now:

```elixir
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Components.Title.Row, as: TitleRow
```

The `, as: TitleRow` matches how `discovery_live.ex` aliases it (Task A3): one local name for the module everywhere, and `Row` on its own would be ambiguous next to `RecommendationRows`.

(Keep any other import the remaining markup still needs; the compiler's unused-import warning is the check.)

Delete the `release_mode_available` attr and add:

```elixir
  attr :default_grab_mode, :string,
    required: true,
    doc: "the resolved Default rung, for the row's tracking marker — `AutoGrabSettings.load().default_mode`."
```

Delete the `tracked_refs` attr — the rung marker states tracking now.

Replace the row-rendering block:

```heex
      <div data-nav-zone="grid" class="space-y-2">
        <.result_row
          :for={result <- @visible}
          result={result}
          status={release_status(result, @today)}
          release_mode_available={@release_mode_available}
          rung={Map.get(@title_rungs, {result.tmdb_id, result.media_type})}
          friend_activity={Map.get(@friend_activity_by_ref, {result.tmdb_id, result.media_type}, [])}
          in_library?={MapSet.member?(@in_library_refs, {result.tmdb_id, result.media_type})}
          tracked?={MapSet.member?(@tracked_refs, {result.tmdb_id, result.media_type})}
        />
      </div>
```

with:

```heex
      <div data-nav-zone="grid" class="space-y-2">
        <TitleRow.title_row
          :for={result <- @visible}
          id={"omnibox-result-#{result.media_type}-#{result.tmdb_id}"}
          title={result}
          poster_url={title_poster_url(result)}
          markers={markers(result, assigns)}
          friend_activity={Map.get(@friend_activity_by_ref, Title.ref(result), [])}
        />
      </div>
```

Delete `result_row/1` and its `attr` declarations, `verb/3`, `toggleable?/1` and `bookmark_label/1` entirely, and add in their place:

```elixir
  # The row's markers, from the one builder every title row uses.
  # `acquisition_state: nil` because this page does not read
  # `Acquisition.title_state/2` per result — a scheduled convergence, and
  # a one-word change here when it does.
  defp markers(%Title{} = result, assigns) do
    ref = Title.ref(result)

    Logic.row_markers(%{
      in_library?: MapSet.member?(assigns.in_library_refs, ref),
      acquisition_state: nil,
      rung: Map.get(assigns.title_rungs, ref),
      default_grab_mode: assigns.default_grab_mode
    })
  end
```

Also delete the moduledoc paragraph about the two-column `data-nav-grid` pairing if any of it survives in the file's comments — the rows are one nav item each now.

- [ ] **Step 4: Update the host**

In `lib/media_centaur_web/live/incoming_live.ex`:

a) Add the `default_grab_mode` assign at mount, beside the other seeded assigns near line 253:

```elixir
         default_grab_mode: AutoGrabSettings.load().default_mode,
```

Add the alias if it is not already there: `alias MediaCentaur.Acquisition.AutoGrabSettings` (check first — `TitleDetailHost` aliases it, the LiveView may not).

b) Update the `MediaResults.media_results` call (around line 879):

```heex
          <MediaResults.media_results
            :if={@omnibox_mode == :media}
            query={@omnibox_query}
            results={@omnibox_results}
            searching?={@omnibox_searching?}
            metadata_available={@tmdb_ready}
            scope={@omnibox_scope}
            title_rungs={@title_rungs}
            in_library_refs={@in_library_refs}
            default_grab_mode={@default_grab_mode}
            friend_activity_by_ref={@friend_activity_by_ref}
          />
```

c) Delete the whole `handle_event("omnibox_pick", …)` clause (around line 1609) and the whole `handle_event("watchlist_toggle", …)` clause (around line 1651).

d) Check whether `tracked_refs` still has a consumer:

Run: `grep -n "tracked_refs" lib/media_centaur_web/live/incoming_live.ex`
If the only hits are the mount seed (around line 254) and the reload assignment (around line 2331), delete both — the assign is dead. If anything else reads it, leave it.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs`
Expected: PASS, including the two rewritten tests and the new marker test.

- [ ] **Step 6: Run the whole suite**

Run: `~/scripts/agents/agent-mix test`
Expected: PASS. The page smoke test already covers `/incoming`; if it fails, the fixture needs a search result, not a weaker assertion.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: a media-search result opens the title detail, like every other row

Media search was the last surface carrying its own verb. The row is now
Components.Title.Row; omnibox_pick and watchlist_toggle are gone, and
Download lives in the modal the row opens.

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task B5: Storybook, copy, and the gate

**Files:**
- Modify: `storybook/acquisition/media_results.story.exs` (find it with `ls storybook/acquisition`)
- Modify: `lib/media_centaur_web/live/discovery_live.ex:473`

- [ ] **Step 1: Update the `MediaResults` story**

Its variations pass `release_mode_available` and `tracked_refs`, which no longer exist, and lean on verb and bookmark states that are gone. Replace those attributes with `default_grab_mode: "off"` in every variation, and drop any variation whose only purpose was a verb or bookmark state. Keep at least: no results, results with a mixed scope, and a result the library owns.

- [ ] **Step 2: Fix the watchlist empty-state copy**

In `lib/media_centaur_web/live/discovery_live.ex` around line 473, the empty state reads "Bookmark a title from a search or its detail view and it is kept here until you…". Search rows no longer carry a bookmark. Change that clause to "Bookmark a title from its detail view and it is kept here until you…", leaving the rest of the sentence as it is.

- [ ] **Step 3: Correct the preference's stale moduledoc**

`lib/media_centaur/settings/preferences/discovery_visibility.ex` claims the setting "Gates the sidebar's Discovery entry — nothing else", then says "the bookmark toggles on the detail modal and the Incoming search rows keep working". It already gated the library panel's Recommend control before this change, it now gates the title detail modal's, and Incoming search rows no longer have a bookmark. Replace the first two paragraphs of the moduledoc with:

```elixir
  Gates the sidebar's Discovery entry and the Recommend control on both
  title surfaces — the library detail panel and the title detail modal.
  Default-**off**: Discovery is a work-in-progress feature expected to
  change shape, so it stays out of everyone's sidebar until a user opts
  in via Settings → Preferences. The page itself stays reachable by URL,
  the tracking ladder on the detail modal keeps working, and the
  Discovery context underneath is unaffected — items already on the
  watchlist are kept, just not linked to from the nav.
```

- [ ] **Step 4: Run the storybook tests**

Run: `~/scripts/agents/agent-mix test test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS.

- [ ] **Step 5: Run the full gate**

Run: `~/scripts/agents/agent-mix precommit`
Expected: PASS — format, credo --strict, boundaries, deps.audit, sobelow, and the full suite. Fix everything it reports; zero warnings.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: storybook and copy follow the search row onto the shared row

Claude-Session: https://claude.ai/code/session_01F3FLHycnth9F1z26fCRUJE"
```

### Task B6: Real-browser verification

`render_click` is not a browser click, and this change moves a click target and a focus-restore origin. Both need a real browser before the work is called done.

- [ ] **Step 1: Rebuild assets and confirm the dev server is up**

```bash
~/scripts/agents/agent-mix assets.build
systemctl --user status media-centaur-dev --no-pager | head -5
```

If it is not running: `systemctl --user start media-centaur-dev`.

- [ ] **Step 2: Verify the click path**

```bash
~/scripts/agents/page-shot --url 'http://127.0.0.1:2160/incoming' --viewport 1920x1080 --wait-ms 3000
```

Then drive it with `chromium-probe`, waiting for `phx-connected` on `[data-phx-main]` before clicking (pre-join clicks are dropped): type a query into `#omnibox-media-input`, click the first `[data-component='title-row']`, confirm the title detail modal opens, click `#title-recommend`, confirm `#recommend-modal` opens carrying the result's name.

- [ ] **Step 3: Verify focus restore**

With the title detail modal open from a search row, close it and confirm the nav cursor lands back on the row that opened it — the behaviour `data-entity-id` provides. Use `~/scripts/agents/mc-nav-trace` for the key sequence; it is the first tool for any nav question.

- [ ] **Step 4: Record what you saw**

If either check fails, stop and fix before continuing. "Verified" means a browser was driven, not that a LiveView test was green.

### Task B7: Documentation

**Files:**
- Modify: `~/src/media-centaur/media-centaur.wiki/` (sibling git repo)

- [ ] **Step 1: Update the Downloads page**

In the wiki's *Using Media Centaur* Downloads page, change the media-search description: a search result opens the title's detail, and Download and the tracking ladder both live there. Remove any mention of a bookmark on a search row.

- [ ] **Step 2: Update the Discovery/Friends page**

Add that a title can be recommended from search results as well as from the library — anywhere its detail opens.

- [ ] **Step 3: Commit the wiki**

```bash
cd ~/src/media-centaur/media-centaur.wiki
git add -A
git commit -m "wiki: a search result opens the title detail; recommend from anywhere"
git push
```

- [ ] **Step 4: Final gate on the app repo**

```bash
cd ~/src/media-centaur/media-centaur-app
~/scripts/agents/agent-mix precommit
```

Expected: PASS. Do not push the app repo — pushing is the owner's call.
