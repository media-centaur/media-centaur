# Storybook Flesh-Out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Phoenix Storybook from a thin scaffold into a structured, comprehensive, coherent component catalog with a thin design-system foundation, enforced by a Credo coverage check.

**Architecture:** Five sequential phases — (1) audit + Credo check, (2) primitive depth, (3) foundation pages, (4) self-contained composites, (5) contract-driven cards. Module-attribute convention (`@storybook_status` / `@storybook_reason`) co-locates coverage state with the component. New custom Credo check (`MediaCentarr.Credo.Checks.StorybookCoverage`) gates `mix precommit` against undeclared coverage gaps.

**Tech Stack:** Elixir 1.17+, Phoenix 1.8, Phoenix Storybook 1.0, Credo 1.7+ (with `Credo.Test.Case` helper), Tailwind v4 + daisyUI, jujutsu (`jj`) for VCS.

**Spec:** [`docs/superpowers/specs/2026-05-02-storybook-fleshout-design.md`](../specs/2026-05-02-storybook-fleshout-design.md)

---

## File Structure

### New files

| Path | Responsibility |
|------|----------------|
| `credo_checks/storybook_coverage.ex` | Custom Credo check enforcing v1 (coverage) + v2 (story shape) |
| `test/media_centarr/credo/checks/storybook_coverage_test.exs` | Check tests |
| `storybook/foundations/_foundations.index.exs` | Sidebar entry for foundation pages |
| `storybook/foundations/colors.story.exs` | daisyUI color palette + surface treatments |
| `storybook/foundations/typography.story.exs` | Heading/body/caption type scale |
| `storybook/foundations/spacing.story.exs` | Spacing scale + glass surfaces |
| `storybook/foundations/uidr_index.story.exs` | UIDR rules entry-point linking to component stories |
| `storybook/library_cards/_library_cards.index.exs` | Sidebar entry for library cards |
| `storybook/library_cards/poster_card.story.exs` | (Phase 5) |
| `storybook/library_cards/cw_card.story.exs` | (Phase 5) |
| `storybook/library_cards/toolbar.story.exs` | (Phase 5) |
| `storybook/library_cards/poster_row.story.exs` | (Phase 5) |
| `storybook/library_cards/upcoming_cards.story.exs` | (Phase 5) |
| `storybook/detail/_detail.index.exs` | Sidebar entry for detail components |
| `storybook/detail/facet_strip.story.exs` | (Phase 4) |
| `storybook/detail/metadata_row.story.exs` | (Phase 4) |
| `storybook/detail/play_card.story.exs` | (Phase 4) |
| `storybook/detail/section.story.exs` | (Phase 4) |
| `storybook/detail/hero.story.exs` | (Phase 4) |
| `storybook/composites/_composites.index.exs` | Sidebar entry for top-level composites |
| `storybook/composites/modal_shell.story.exs` | (Phase 4) |
| `storybook/composites/hero_card.story.exs` | (Phase 4) |
| `storybook/composites/detail_panel.story.exs` | (Phase 5) |

### Modified files

| Path | Change |
|------|--------|
| `.credo.exs` | Wire `MediaCentarr.Credo.Checks.StorybookCoverage` into `enabled:` list |
| `docs/storybook.md` | Refresh triage table + add "Foundations" section |
| `.claude/skills/storybook/SKILL.md` | Document `@storybook_status` convention |
| All non-covered component modules | Add `@storybook_status` + `@storybook_reason` attributes |
| `storybook/core_components/input.story.exs` | Phase 2 — bring to rubric |
| `storybook/core_components/list.story.exs` | Phase 2 — bring to rubric |
| `storybook/core_components/header.story.exs` | Phase 2 — bring to rubric |
| `storybook/core_components/flash.story.exs` | Phase 2 — deepen |
| `storybook/core_components/table.story.exs` | Phase 2 — deepen |

---

## Phase 1 — Map and Enforce

**Phase goal:** Audit every component, classify it, declare its storybook status on the module, and land the coverage check that enforces this from now on.

### Task 1.1: Component inventory

**Files:**
- Read-only: `lib/media_centarr_web/components/**/*.ex`

- [ ] **Step 1: Enumerate component files**

Run: `find lib/media_centarr_web/components -name '*.ex' | sort`

Expected output (current state — confirm against actual):
```
lib/media_centarr_web/components/coming_up_marquee.ex
lib/media_centarr_web/components/console_components.ex
lib/media_centarr_web/components/continue_watching_row.ex
lib/media_centarr_web/components/core_components.ex
lib/media_centarr_web/components/detail/facet.ex
lib/media_centarr_web/components/detail/facet_strip.ex
lib/media_centarr_web/components/detail/hero.ex
lib/media_centarr_web/components/detail/logic.ex
lib/media_centarr_web/components/detail/metadata_row.ex
lib/media_centarr_web/components/detail/play_card.ex
lib/media_centarr_web/components/detail/section.ex
lib/media_centarr_web/components/detail_panel.ex
lib/media_centarr_web/components/hero_card.ex
lib/media_centarr_web/components/layouts.ex
lib/media_centarr_web/components/library_cards.ex
lib/media_centarr_web/components/modal_shell.ex
lib/media_centarr_web/components/poster_row.ex
lib/media_centarr_web/components/track_modal.ex
lib/media_centarr_web/components/upcoming_cards.ex
```

- [ ] **Step 2: For each file, identify exported function components**

For each `.ex` file, look at the AST/source for `attr` declarations followed by `def name(assigns)`. Record the function name(s).

Run: `grep -n "^  def " lib/media_centarr_web/components/library_cards.ex`

Expected for `library_cards.ex`: `poster_card`, `cw_card`, `toolbar`.

Build a working table (a scratch note for yourself, not committed):

| File | Function components | Has story? | Proposed status |
|------|--------------------:|-----------:|-----------------|
| `coming_up_marquee.ex` | `coming_up_marquee/1` | No | `:skip` (release-tracking timer state) |
| `console_components.ex` | (multiple) | No | `:skip` (sticky log stream state) |
| `continue_watching_row.ex` | `continue_watching_row/1` | No | `:skip` (watch-history feed) |
| `core_components.ex` | button, flash, header, icon, input, list, table, plus helpers | Yes (7) | `:covered` (no attribute needed) |
| `detail/facet.ex` | none — view-model struct | n/a | `:skip` (view-model struct, not component) |
| `detail/facet_strip.ex` | `facet_strip/1` | No | `:pending` (Phase 4) |
| `detail/hero.ex` | `hero/1` | No | `:pending` (Phase 4) |
| `detail/logic.ex` | none — pure helpers | n/a | `:skip` (pure helpers, not components) |
| `detail/metadata_row.ex` | `metadata_row/1` | No | `:pending` (Phase 4) |
| `detail/play_card.ex` | `play_card/1` | No | `:pending` (Phase 4) |
| `detail/section.ex` | `section/1` | No | `:pending` (Phase 4) |
| `detail_panel.ex` | `detail_panel/1` | No | `:pending` (Phase 5) |
| `hero_card.ex` | `hero_card/1` | No | `:pending` (Phase 4) |
| `layouts.ex` | `app/1`, `flash_group/1`, etc. | No | `:skip` (layouts, not catalog material) |
| `library_cards.ex` | `poster_card/1`, `cw_card/1`, `toolbar/1` | No | `:pending` (Phase 5) |
| `modal_shell.ex` | `modal_shell/1` | No | `:pending` (Phase 4) |
| `poster_row.ex` | `poster_row/1` | No | `:pending` (Phase 5) |
| `track_modal.ex` | `track_modal/1` | No | `:static_example` (depends on TMDB context) |
| `upcoming_cards.ex` | `upcoming_card/1` (verify) | No | `:pending` (Phase 5) |

If any file has a component count or shape that doesn't match the table above, treat the live source as authoritative and update the table accordingly.

- [ ] **Step 3: No commit yet — this is a planning step**

The inventory becomes the basis for Tasks 1.2 (refresh triage doc) and 1.3 (add module attributes).

---

### Task 1.2: Refresh triage table in `docs/storybook.md`

**Files:**
- Modify: `docs/storybook.md` — replace the "Component triage" table

- [ ] **Step 1: Replace the triage table**

Replace the existing triage table in `docs/storybook.md` with:

```markdown
## Component triage

What belongs and what doesn't. Status mirrors the `@storybook_status` module attribute on each component module — when this table and the source disagree, the source is correct.

| Component | Status | Notes |
|-----------|--------|-------|
| `core_components.button/1` | ✅ covered | Seed story; full matrix |
| `core_components.icon/1` | ✅ covered | Sizes + colors + motion |
| `core_components.input/1` | ✅ covered | Phase 2 — every input type, error states |
| `core_components.flash/1` | ✅ covered | Phase 2 — every kind, hidden/visible |
| `core_components.header/1` | ✅ covered | Phase 2 — with/without subtitle and actions |
| `core_components.list/1` | ✅ covered | Phase 2 — empty/single/many |
| `core_components.table/1` | ✅ covered | Phase 2 — empty/loaded/long/with-actions |
| `library_cards.poster_card/1` | ⏳ pending | Phase 5 — exemplifies typed-attr/ViewModel value |
| `library_cards.cw_card/1` | ⏳ pending | Phase 5 — progress bar + paused state |
| `library_cards.toolbar/1` | ⏳ pending | Phase 5 — type tabs × sort × filter axes |
| `poster_row.poster_row/1` | ⏳ pending | Phase 5 |
| `upcoming_cards.upcoming_card/1` | ⏳ pending | Phase 5 |
| `detail_panel/1` | ⏳ pending | Phase 5 — many states (no artwork, no plot, episode list) |
| `modal_shell/1` | ⏳ pending | Phase 4 — open/closed (always-in-DOM) |
| `hero_card/1` | ⏳ pending | Phase 4 |
| `detail/facet_strip/1` | ⏳ pending | Phase 4 — consumes `Detail.Facet` view-models |
| `detail/metadata_row/1` | ⏳ pending | Phase 4 |
| `detail/play_card/1` | ⏳ pending | Phase 4 |
| `detail/section/1` | ⏳ pending | Phase 4 |
| `detail/hero/1` | ⏳ pending | Phase 4 |
| `track_modal/1` | 🖼 static example | Depends on TMDB context |
| `console_components.*` | ⚠️ skip | Log stream is sticky LiveView state |
| `coming_up_marquee/1` | ⚠️ skip | Depends on release-tracking timer state |
| `continue_watching_row/1` | ⚠️ skip | Depends on watch-history feed |
| `detail/facet` | ⚠️ skip | Typed view-model struct, not a function component |
| `detail/logic` | ⚠️ skip | Pure helpers, not a function component |
| `layouts/*` | ⚠️ skip | Page layouts, not catalog material |

Closing all "pending" rows is the definition of "the storybook is the design system."
```

- [ ] **Step 2: Verify `docs/storybook.md` still renders coherently**

Run: `mix precommit` (formatter only — no behavioural change yet)
Expected: PASS (or fail only on changes outside this task)

- [ ] **Step 3: Commit**

```bash
jj describe -m "docs(storybook): refresh component triage table"
```

---

### Task 1.3: Add `@storybook_status` attributes to non-covered components

**Files:**
- Modify: every component module without a story (per the inventory)

- [ ] **Step 1: Add the attribute and reason to each non-covered module**

For each module in the inventory with a non-`:covered` status, edit the module to add the attribute pair right after `@moduledoc`. The attribute is a documentation marker only; nothing reads it at runtime — the Credo check parses it from source.

Example for `lib/media_centarr_web/components/console_components.ex`:

```elixir
defmodule MediaCentarrWeb.ConsoleComponents do
  @moduledoc """
  ...existing doc...
  """

  @storybook_status :skip
  @storybook_reason "Log stream is sticky LiveView state — covered by page smoke tests"

  # ...existing module body...
end
```

Apply identically (with the appropriate status/reason) to:

| Module | Status | Reason |
|--------|--------|--------|
| `MediaCentarrWeb.Components.ComingUpMarquee` (or actual name — verify) | `:skip` | "Depends on release-tracking timer state — covered by page smoke tests" |
| `MediaCentarrWeb.ConsoleComponents` | `:skip` | "Log stream is sticky LiveView state — covered by page smoke tests" |
| `MediaCentarrWeb.Components.ContinueWatchingRow` (verify) | `:skip` | "Depends on watch-history feed — covered by page smoke tests" |
| `MediaCentarrWeb.Components.Detail.FacetStrip` | `:pending` | "Phase 4 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.Detail.Hero` | `:pending` | "Phase 4 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.Detail.MetadataRow` | `:pending` | "Phase 4 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.Detail.PlayCard` | `:pending` | "Phase 4 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.Detail.Section` | `:pending` | "Phase 4 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.DetailPanel` (verify) | `:pending` | "Phase 5 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.HeroCard` (verify) | `:pending` | "Phase 4 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.LibraryCards` (verify) | `:pending` | "Phase 5 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.ModalShell` (verify) | `:pending` | "Phase 4 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.PosterRow` (verify) | `:pending` | "Phase 5 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |
| `MediaCentarrWeb.Components.TrackModal` (verify) | `:static_example` | "Depends on TMDB context lookups — static specimen forthcoming" |
| `MediaCentarrWeb.Components.UpcomingCards` (verify) | `:pending` | "Phase 5 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md" |

For modules that have no function components at all (`detail/facet.ex`, `detail/logic.ex`, `layouts.ex`), **don't add the attribute** — the Credo check will not run against them (it skips files with no `attr` declarations).

> Module names noted "(verify)" need a quick `head -3 <file>` to confirm — the actual `defmodule` name might use `MediaCentarrWeb.<X>` or `MediaCentarrWeb.Components.<X>`. Use whatever the source declares.

- [ ] **Step 2: Verify the project compiles**

Run: `mix compile --warnings-as-errors`
Expected: PASS — these are unused module attributes (Credo will read them later), so they should compile cleanly. If the compiler warns about unused module attributes, prefix with `@_storybook_status` is **not** the answer — the convention has to match what the Credo check reads. Instead, suppress the warning by referencing the attribute once at compile time, e.g. `_ = @storybook_status`. (Test this; if the compiler doesn't warn at all because module attributes are read by `Module.put_attribute/3` semantics that don't enforce usage, no workaround is needed.)

- [ ] **Step 3: Commit**

```bash
jj describe -m "feat(storybook): declare @storybook_status on non-covered components"
```

---

### Task 1.4: Write failing tests for `StorybookCoverage` Credo check

**Files:**
- Create: `test/media_centarr/credo/checks/storybook_coverage_test.exs`

- [ ] **Step 1: Create the test file with all v1 + v2 cases**

```elixir
defmodule MediaCentarr.Credo.Checks.StorybookCoverageTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.StorybookCoverage

  # =============================================================
  # SCOPE
  # =============================================================

  describe "scope" do
    test "ignores files outside lib/media_centarr_web/components/" do
      """
      defmodule MediaCentarrWeb.SomeOtherThing do
        attr :name, :string, required: true

        def thing(assigns) do
          ~H"<div></div>"
        end
      end
      """
      |> to_source_file("lib/media_centarr_web/some_other_thing.ex")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end

    test "ignores files under components/ that have no attr declarations" do
      """
      defmodule MediaCentarrWeb.Components.Detail.Logic do
        @moduledoc "pure helpers"
        def truncate(string, n), do: String.slice(string, 0, n)
      end
      """
      |> to_source_file("lib/media_centarr_web/components/detail/logic.ex")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end
  end

  # =============================================================
  # V1 — COVERAGE
  # =============================================================

  describe "v1 coverage — story-file detection" do
    test "passes when a corresponding story file exists" do
      # The check looks for storybook/sample/sample.story.exs
      # We simulate this by stubbing File.exists?/1 via the params keyword.
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage,
        story_paths: ["storybook/sample/sample.story.exs"]
      )
      |> refute_issues()
    end

    test "errors when no story exists and no @storybook_status declared" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> assert_issue(fn issue ->
        assert issue.category == :design
        assert issue.message =~ ~r/no story/i
      end)
    end

    test "passes when @storybook_status is :skip with a reason" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :skip
        @storybook_reason "Sticky LiveView state"

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> refute_issues()
    end

    test "passes when @storybook_status is :static_example with a reason" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :static_example
        @storybook_reason "Depends on TMDB context"

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> refute_issues()
    end

    test "warns (low priority) when @storybook_status is :pending with a reason" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :pending
        @storybook_reason "Phase 4"

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> assert_issue(fn issue ->
        assert issue.priority < 0  # priority drops below default for warnings
      end)
    end

    test "errors when @storybook_status is :skip without a reason" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :skip

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/@storybook_reason/
      end)
    end

    test "errors when @storybook_status is an unknown value" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :nonsense
        @storybook_reason "Whatever"

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/unknown.*status/i
      end)
    end
  end

  # =============================================================
  # V2 — STORY SHAPE
  # =============================================================

  describe "v2 story shape — namespace" do
    test "errors when story module is not under MediaCentarrWeb.Storybook.*" do
      """
      defmodule Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def render_source, do: :function

        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/MediaCentarrWeb\.Storybook\./
      end)
    end

    test "passes when story module is under MediaCentarrWeb.Storybook.*" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def render_source, do: :function

        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end
  end

  describe "v2 story shape — required callbacks for component stories" do
    test "errors when a :component story does not define function/0" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def render_source, do: :function
        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/function\/0/
      end)
    end

    test "errors when a :component story uses render_source :module" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def render_source, do: :module
        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/render_source.*:function/
      end)
    end

    test "passes when a :component story has render_source :function" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def render_source, do: :function
        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end

    test "passes when a :component story omits render_source (uses default)" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end

    test "ignores :page stories — they don't need function/0 or render_source" do
      """
      defmodule MediaCentarrWeb.Storybook.Foundations.Colors do
        use PhoenixStorybook.Story, :page

        def render(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("storybook/foundations/colors.story.exs")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centarr/credo/checks/storybook_coverage_test.exs`
Expected: FAIL with `module MediaCentarr.Credo.Checks.StorybookCoverage is not loaded`

- [ ] **Step 3: Commit (red)**

```bash
jj describe -m "test(credo): add failing StorybookCoverage check tests"
```

---

### Task 1.5: Implement `StorybookCoverage` v1 + v2

**Files:**
- Create: `credo_checks/storybook_coverage.ex`

- [ ] **Step 1: Implement the check**

```elixir
defmodule MediaCentarr.Credo.Checks.StorybookCoverage do
  use Credo.Check,
    id: "MC0009",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Every Phoenix function component in `lib/media_centarr_web/components/**`
      must have either:

        1. A corresponding story file at `storybook/<area>/<func>.story.exs`, OR
        2. A `@storybook_status` module attribute with a `@storybook_reason`
           explaining why no story exists.

      Valid status values:

        * `:skip` — component will never have a story (sticky LiveView state,
           orchestration-only, or otherwise not visual). Reason required.
        * `:static_example` — depends on context state in ways that prevent live
           storying; a static specimen will be added. Reason required.
        * `:pending` — story is planned but not yet written. Reason required.
           Treated as a warning; does not fail precommit.

      Story files in `storybook/**/*.story.exs` must additionally:

        * Use the `MediaCentarrWeb.Storybook.*` namespace (boundary requirement).
        * Define `function/0` for `:component` stories.
        * Use `render_source :function` for `:component` stories (or omit it).

      Source: `docs/superpowers/specs/2026-05-02-storybook-fleshout-design.md`,
      `docs/storybook.md`, `.claude/skills/storybook/SKILL.md`.
      """
    ]

  alias Credo.Code
  alias Credo.IssueMeta

  @valid_statuses [:covered, :skip, :static_example, :pending]
  @namespace_prefix "Elixir.MediaCentarrWeb.Storybook."

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    cond do
      component_file?(filename) ->
        run_component_check(source_file, issue_meta, params)

      story_file?(filename) ->
        run_story_check(source_file, issue_meta)

      true ->
        []
    end
  end

  # =============================================================
  # COMPONENT FILE CHECK (v1)
  # =============================================================

  defp component_file?(filename) do
    String.contains?(filename, "lib/media_centarr_web/components/") and
      String.ends_with?(filename, ".ex")
  end

  defp run_component_check(source_file, issue_meta, params) do
    {functions, status, reason} = scan_component_module(source_file)

    cond do
      # No function components in this file → skip silently
      functions == [] ->
        []

      # Story file exists for at least one of the components → covered
      any_story_exists?(functions, source_file, params) ->
        []

      # Status declared
      status != nil ->
        validate_status(status, reason, issue_meta, source_file)

      # No story, no status → error
      true ->
        [
          format_issue(issue_meta,
            message:
              "Component #{inspect(List.first(functions))} has no story file " <>
                "and no @storybook_status attribute. Add a story under storybook/ " <>
                "or declare @storybook_status :skip / :pending / :static_example " <>
                "with a @storybook_reason.",
            line_no: 1
          )
        ]
    end
  end

  # Walks the AST and returns:
  #   {[component_function_names :: atom], status :: atom | nil, reason :: String.t() | nil}
  defp scan_component_module(source_file) do
    ast = Code.ast(source_file) |> elem(1)

    {functions, _, status, reason} =
      Macro.prewalk(ast, {[], false, nil, nil}, fn
        {:attr, _, [_name, _type | _]} = node, {fns, _had_attr, st, rs} ->
          {node, {fns, true, st, rs}}

        {:attr, _, [_name, _type]} = node, {fns, _had_attr, st, rs} ->
          {node, {fns, true, st, rs}}

        {:def, _, [{name, _, _args} | _]} = node, {fns, true, st, rs} when is_atom(name) ->
          # `def fname(assigns)` preceded by attr declarations → component
          {node, {[name | fns], false, st, rs}}

        {:@, _, [{:storybook_status, _, [value]}]} = node, {fns, had_attr, _, rs} ->
          {node, {fns, had_attr, value, rs}}

        {:@, _, [{:storybook_reason, _, [value]}]} = node, {fns, had_attr, st, _} when is_binary(value) ->
          {node, {fns, had_attr, st, value}}

        node, acc ->
          {node, acc}
      end)
      |> elem(1)

    {Enum.uniq(functions), status, reason}
  end

  defp any_story_exists?(functions, source_file, params) do
    # `params[:story_paths]` is a test-only override for File.exists?/1.
    case Keyword.fetch(params, :story_paths) do
      {:ok, paths} ->
        Enum.any?(functions, fn fname ->
          Enum.any?(paths, fn path -> String.ends_with?(path, "/#{fname}.story.exs") end)
        end)

      :error ->
        Enum.any?(functions, fn fname ->
          path = derive_story_path(source_file.filename, fname)
          File.exists?(path)
        end)
    end
  end

  defp derive_story_path(component_filename, func_name) do
    # lib/media_centarr_web/components/library_cards.ex + :poster_card
    #   → storybook/library_cards/poster_card.story.exs
    # lib/media_centarr_web/components/detail/play_card.ex + :play_card
    #   → storybook/detail/play_card.story.exs
    relative =
      component_filename
      |> String.replace_prefix("lib/media_centarr_web/components/", "")
      |> Path.dirname()

    area =
      case relative do
        "." ->
          component_filename
          |> Path.basename(".ex")

        sub ->
          sub
      end

    Path.join(["storybook", area, "#{func_name}.story.exs"])
  end

  defp validate_status(status, reason, issue_meta, _source_file) do
    cond do
      status not in @valid_statuses ->
        [
          format_issue(issue_meta,
            message:
              "Unknown @storybook_status: #{inspect(status)}. " <>
                "Valid values: #{inspect(@valid_statuses)}.",
            line_no: 1
          )
        ]

      status in [:skip, :static_example] and (reason == nil or reason == "") ->
        [
          format_issue(issue_meta,
            message:
              "@storybook_status #{inspect(status)} requires a non-empty @storybook_reason.",
            line_no: 1
          )
        ]

      status == :pending ->
        if reason in [nil, ""] do
          [
            format_issue(issue_meta,
              message: "@storybook_status :pending requires a non-empty @storybook_reason.",
              line_no: 1
            )
          ]
        else
          [
            format_issue(issue_meta,
              message:
                "Component is :pending — #{reason}. Write a story to clear this warning.",
              priority: :low,
              line_no: 1
            )
          ]
        end

      true ->
        []
    end
  end

  # =============================================================
  # STORY FILE CHECK (v2)
  # =============================================================

  defp story_file?(filename) do
    String.starts_with?(filename, "storybook/") and
      String.ends_with?(filename, ".story.exs")
  end

  defp run_story_check(source_file, issue_meta) do
    ast = Code.ast(source_file) |> elem(1)
    {module_name, story_type, callbacks, render_source_value} = scan_story_module(ast)

    issues = []

    issues =
      if module_name && not String.starts_with?(Atom.to_string(module_name), @namespace_prefix) do
        [
          format_issue(issue_meta,
            message:
              "Story module #{inspect(module_name)} must be under " <>
                "MediaCentarrWeb.Storybook.* — boundary requirement.",
            line_no: 1
          )
          | issues
        ]
      else
        issues
      end

    issues =
      if story_type == :component and :function not in callbacks do
        [
          format_issue(issue_meta,
            message:
              "A :component story must define function/0 returning a function reference.",
            line_no: 1
          )
          | issues
        ]
      else
        issues
      end

    issues =
      if story_type == :component and render_source_value not in [nil, :function] do
        [
          format_issue(issue_meta,
            message:
              "A :component story should use `def render_source, do: :function` " <>
                "(got #{inspect(render_source_value)}). Module source is too noisy " <>
                "for function components.",
            line_no: 1
          )
          | issues
        ]
      else
        issues
      end

    issues
  end

  defp scan_story_module(ast) do
    Macro.prewalk(ast, {nil, nil, [], nil}, fn
      {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, {_, st, cbs, rs} ->
        module = Module.concat(parts)
        {node, {module, st, cbs, rs}}

      {:use, _, [{:__aliases__, _, [:PhoenixStorybook, :Story]}, type]} = node,
      {mod, _, cbs, rs}
      when is_atom(type) ->
        {node, {mod, type, cbs, rs}}

      {:def, _, [{:function, _, _} | _]} = node, {mod, st, cbs, rs} ->
        {node, {mod, st, [:function | cbs], rs}}

      {:def, _, [{:render_source, _, _}, [do: value]]} = node, {mod, st, cbs, _} ->
        {node, {mod, st, [:render_source | cbs], value}}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end
end
```

- [ ] **Step 2: Run the tests, expect them to pass**

Run: `mix test test/media_centarr/credo/checks/storybook_coverage_test.exs`
Expected: PASS (all cases).

If anything fails, fix the implementation — the tests are the spec. Common gotchas with `Credo.Code.ast/1`:
- It returns `{:ok, ast}` or `{:error, _}` — handle the tuple shape.
- AST shapes for `def name(args), do: body` differ from `def name(args) do … end`. Both must be handled.
- Module attribute AST is `{:@, _, [{:attr_name, _, [value]}]}` — match exactly.

- [ ] **Step 3: Commit (green)**

```bash
jj describe -m "feat(credo): add StorybookCoverage check (v1 coverage + v2 shape)"
```

---

### Task 1.6: Wire the check into `.credo.exs`

**Files:**
- Modify: `.credo.exs`

- [ ] **Step 1: Add the check to the enabled list**

In `.credo.exs`, find the existing block:

```elixir
{MediaCentarr.Credo.Checks.RawButtonClass, []}
```

Add immediately after it (before the closing `]`):

```elixir
{MediaCentarr.Credo.Checks.StorybookCoverage, []}
```

- [ ] **Step 2: Run Credo, observe expected output**

Run: `mix credo --strict`
Expected: PASS — every component should already have either a story or `@storybook_status` from Task 1.3. If anything fails, the missing module is one Task 1.3 didn't update; fix it before committing.

- [ ] **Step 3: Run full precommit**

Run: `mix precommit`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
jj describe -m "chore(credo): enable StorybookCoverage check in precommit"
```

---

### Task 1.7: Update the storybook skill

**Files:**
- Modify: `.claude/skills/storybook/SKILL.md`

- [ ] **Step 1: Add the convention to the "Project conventions" table**

In `.claude/skills/storybook/SKILL.md`, find the "Project conventions (non-negotiable)" table. Add a new row:

```markdown
| **Component coverage** | Every component module without a story must declare `@storybook_status :skip / :pending / :static_example` + `@storybook_reason "..."` | Enforced by `MediaCentarr.Credo.Checks.StorybookCoverage` (`mix precommit`). The reason lives next to the code so it can't drift. |
```

- [ ] **Step 2: Add a section after "Adding a new story (checklist)"**

```markdown
## Coverage status (when not adding a story)

If you add a component but **don't** add a story (sticky state, orchestration-only, awaiting contract refactor), declare the status on the module immediately so the Credo check passes:

​```elixir
defmodule MediaCentarrWeb.Components.Foo do
  @storybook_status :pending
  @storybook_reason "Awaiting typed-attr contract refactor"

  # ...
end
​```

Statuses:

- `:skip` — never going to have a story. Always paired with a reason.
- `:static_example` — depends on context state; a static visual specimen will be added.
- `:pending` — story is planned. The check warns (does not fail) until the story exists.

Omit the attribute entirely once a story is in place.
```

(Note the zero-width-joiner backticks above are placeholders for triple-backticks in the actual edit — when you make this change, use real triple-backticks.)

- [ ] **Step 3: Run precommit**

Run: `mix precommit`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
jj describe -m "docs(skill): document @storybook_status convention"
```

---

**Phase 1 exit criteria:**
- ✅ Triage table in `docs/storybook.md` lists every current component
- ✅ Every component module is either `:covered` (implicit) or declares `@storybook_status`
- ✅ `mix precommit` runs the new check
- ✅ Storybook skill documents the convention

**Ship Phase 1 before starting Phase 2.** Run `/ship` if appropriate, or push the JJ change to main.

---

## Phase 2 — Primitive Depth

**Phase goal:** Bring all `core_components` stories to the rubric bar (matches the Definition-of-Done in the spec).

For each task in this phase, the test is "the story renders without error" — the underlying component is already battle-tested via page smoke tests. Open `http://localhost:1080/storybook/core_components/<name>` after each story update and verify visually.

### Task 2.1: Deepen `flash` story

**Files:**
- Modify: `storybook/core_components/flash.story.exs`

- [ ] **Step 1: Read the current `flash` component contract**

Run: `grep -A2 "def flash\|attr :" lib/media_centarr_web/core_components.ex | head -40`

Note every value of `attr :kind, _, values: [...]` — currently `[:info, :error]` plus likely `:warning`, `:success` if those exist. Use the actual values.

- [ ] **Step 2: Replace the story body**

```elixir
defmodule MediaCentarrWeb.Storybook.CoreComponents.Flash do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.flash/1
  def imports, do: [{MediaCentarrWeb.CoreComponents, show: 1, button: 1}]
  def render_source, do: :function

  def template do
    """
    <div>
      <.button phx-click={show("#:variation_id")}>
        Trigger flash
      </.button>
      <.psb-variation/>
    </div>
    """
  end

  # Keep this list in sync with `attr :kind, :atom, values: [...]` in core_components.ex.
  @kinds [:info, :error]

  def variations do
    [
      %VariationGroup{
        id: :kinds,
        description: "All flash kinds — visible by default for screenshot review",
        variations:
          for kind <- @kinds do
            %Variation{
              id: kind,
              description: title_for(kind),
              attributes: %{
                kind: kind,
                hidden: false,
                title: title_for(kind)
              },
              slots: [body_for(kind)]
            }
          end
      },
      %VariationGroup{
        id: :hidden_until_triggered,
        description: "Hidden by default — click 'Trigger flash' to reveal",
        variations:
          for kind <- @kinds do
            %Variation{
              id: kind,
              attributes: %{
                kind: kind,
                hidden: true,
                title: title_for(kind)
              },
              slots: [body_for(kind)]
            }
          end
      },
      %Variation{
        id: :without_title,
        description: "No title — body only",
        attributes: %{
          kind: :info,
          hidden: false
        },
        slots: ["A short notice with no title"]
      },
      %Variation{
        id: :long_body,
        description: "Long body wraps cleanly",
        attributes: %{
          kind: :error,
          hidden: false,
          title: "Operation failed"
        },
        slots: [
          "The request could not be completed because a downstream " <>
            "service returned a 503. Retrying automatically in 30 seconds. " <>
            "If the problem persists, check the diagnostics drawer."
        ]
      }
    ]
  end

  defp title_for(:info), do: "Did you know?"
  defp title_for(:error), do: "Oops!"
  defp title_for(other), do: other |> Atom.to_string() |> String.capitalize()

  defp body_for(:info), do: "Background sync completed in 4.2s"
  defp body_for(:error), do: "Sorry, it just crashed"
  defp body_for(_), do: "Sample body text"
end
```

> If `core_components.flash/1` declares additional `:kind` values (e.g. `:warning`, `:success`), extend `@kinds` and add `title_for/body_for` clauses for them.

- [ ] **Step 3: Run precommit**

Run: `mix precommit`
Expected: PASS

- [ ] **Step 4: Visually verify**

Open `http://localhost:1080/storybook/core_components/flash`. Confirm: every kind renders, hidden variants need the trigger button, long body wraps inside the flash card.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(storybook): deepen flash story to rubric bar"
```

---

### Task 2.2: Deepen `table` story

**Files:**
- Modify: `storybook/core_components/table.story.exs`

- [ ] **Step 1: Add empty / loaded / long-row / no-actions variations**

Replace the story body with:

```elixir
defmodule MediaCentarrWeb.Storybook.CoreComponents.Table do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.table/1
  def imports, do: [{MediaCentarrWeb.CoreComponents, button: 1}]
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-4/5 mb-4" psb-code-hidden>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :empty,
        description: "Empty table — no rows, header still rendered",
        attributes: %{rows: []},
        slots: table_slots()
      },
      %Variation{
        id: :default,
        description: "Loaded with two rows",
        attributes: %{rows: table_rows()},
        slots: table_slots()
      },
      %Variation{
        id: :long_rows,
        description: "Many rows — verifies vertical density and zebra stripe (if any)",
        attributes: %{rows: long_rows()},
        slots: table_slots()
      },
      %Variation{
        id: :with_function,
        description: "Applying functions to row items",
        attributes: %{
          rows: table_rows(),
          row_id: {:eval, ~S|&"user-#{&1.id}"|},
          row_item: {:eval, ~S"&%{&1 | last_name: String.upcase(&1.last_name)}"}
        },
        slots: table_slots()
      },
      %Variation{
        id: :with_actions,
        description: "With an action slot — show button per row",
        attributes: %{rows: table_rows()},
        slots: [
          """
          <:action>
            <.button>Show</.button>
          </:action>
          """
          | table_slots()
        ]
      }
    ]
  end

  defp table_rows do
    [
      %{id: 1, first_name: "Jean", last_name: "Dupont", city: "Paris"},
      %{id: 2, first_name: "Sam", last_name: "Smith", city: "NY"}
    ]
  end

  defp long_rows do
    for i <- 1..12 do
      %{
        id: i,
        first_name: "Person #{i}",
        last_name: "Lastname#{i}",
        city: Enum.random(["Paris", "NY", "Tokyo", "Berlin", "Sydney"])
      }
    end
  end

  defp table_slots do
    [
      ~s(<:col :let={user} label="ID"><%= user.id %></:col>),
      ~s(<:col :let={user} label="First name"><%= user.first_name %></:col>),
      ~s(<:col :let={user} label="Last name"><%= user.last_name %></:col>),
      ~s(<:col :let={user} label="City"><%= user.city %></:col>)
    ]
  end
end
```

- [ ] **Step 2: Run precommit**

Run: `mix precommit`
Expected: PASS

- [ ] **Step 3: Visually verify**

Open `http://localhost:1080/storybook/core_components/table`. Confirm: empty shows header only, long_rows shows ≈12 rows without overflow, with_actions shows a Show button per row.

- [ ] **Step 4: Commit**

```bash
jj describe -m "feat(storybook): deepen table story to rubric bar"
```

---

### Task 2.3: Bring `input` to rubric bar

**Files:**
- Modify: `storybook/core_components/input.story.exs`

- [ ] **Step 1: Read the input contract**

Run: `grep -A30 "def input\b" lib/media_centarr_web/core_components.ex | head -60`

Note the `attr :type` values list (likely `~w(checkbox color date datetime-local email file hidden month number password range search select tel text textarea time url week)` plus `radio`, `radio-group`, etc. Use what's actually there).

- [ ] **Step 2: Replace the story body with one Variation per type plus error/no-error pairs**

```elixir
defmodule MediaCentarrWeb.Storybook.CoreComponents.Input do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.input/1
  def render_source, do: :function

  # Mirrors `attr :type, :string, values: [...]` in core_components.ex.
  # Keep in sync; the StorybookCoverage v3 check (when shipped) will diff these.
  @types ~w(text email password number search tel url textarea checkbox select)

  def variations do
    [
      %VariationGroup{
        id: :types,
        description: "Every input type — default state, no error",
        variations:
          for type <- @types do
            %Variation{
              id: String.to_atom(type),
              description: type,
              attributes: attrs_for(type)
            }
          end
      },
      %VariationGroup{
        id: :with_error,
        description: "Inputs in error state",
        variations: [
          %Variation{
            id: :text_error,
            attributes:
              attrs_for("text") |> Map.put(:errors, ["must be at least 3 characters"])
          },
          %Variation{
            id: :email_error,
            attributes:
              attrs_for("email") |> Map.put(:errors, ["is not a valid email"])
          }
        ]
      },
      %Variation{
        id: :disabled,
        description: "Disabled input",
        attributes: attrs_for("text") |> Map.put(:disabled, true)
      },
      %Variation{
        id: :with_help_text,
        description: "Input with help text",
        attributes: attrs_for("text") |> Map.put(:description, "Letters and numbers only")
      },
      %Variation{
        id: :checkbox_checked,
        description: "Checkbox in the checked state",
        attributes: attrs_for("checkbox") |> Map.put(:value, true)
      },
      %Variation{
        id: :select_with_options,
        description: "Select with options list",
        attributes:
          attrs_for("select")
          |> Map.put(:prompt, "Choose one")
          |> Map.put(:options, [{"Apple", "apple"}, {"Banana", "banana"}, {"Cherry", "cherry"}])
      }
    ]
  end

  defp attrs_for(type) do
    %{
      id: "story-input-#{type}",
      name: "story-input-#{type}",
      type: type,
      label: humanize(type),
      value: default_value_for(type),
      errors: []
    }
  end

  defp humanize(type), do: type |> String.capitalize() |> String.replace("-", " ")

  defp default_value_for("checkbox"), do: false
  defp default_value_for("number"), do: 42
  defp default_value_for("textarea"), do: "Multiple\nlines\nof text"
  defp default_value_for(_), do: "Sample value"
end
```

> Adjust `@types`, `attrs_for/1`, and `default_value_for/1` if the live `attr :type` list disagrees with the assumption above.

- [ ] **Step 3: Run precommit + visually verify**

Run: `mix precommit` — expect PASS.
Open `http://localhost:1080/storybook/core_components/input` — confirm every type renders, error state shows the error text in red, disabled looks disabled, select shows options.

- [ ] **Step 4: Commit**

```bash
jj describe -m "feat(storybook): expand input story to all types + states"
```

---

### Task 2.4: Bring `list` to rubric bar

**Files:**
- Modify: `storybook/core_components/list.story.exs`

- [ ] **Step 1: Replace the story body**

```elixir
defmodule MediaCentarrWeb.Storybook.CoreComponents.List do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.list/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :empty,
        description: "No items",
        slots: []
      },
      %Variation{
        id: :single_item,
        description: "Single item",
        slots: [
          ~s|<:item title="Title">A single value</:item>|
        ]
      },
      %Variation{
        id: :many_items,
        description: "Several items — verifies vertical rhythm",
        slots:
          for {label, value} <- [
                {"Title", "Sample Show"},
                {"Year", "2024"},
                {"Genre", "Documentary"},
                {"Runtime", "118m"},
                {"Rating", "9.1"}
              ] do
            ~s|<:item title="#{label}">#{value}</:item>|
          end
      },
      %Variation{
        id: :long_value,
        description: "Long values wrap correctly",
        slots: [
          ~s|<:item title="Plot">A long-running plot summary that should wrap to multiple lines without breaking the layout. The component must handle this without overflow on common viewport widths.</:item>|,
          ~s|<:item title="Tags">documentary, science, history, nature, biography</:item>|
        ]
      }
    ]
  end
end
```

> If `core_components.list/1` uses different slot shapes (`<:row>` instead of `<:item>`, etc.), adjust the slots accordingly. Read the live source first.

- [ ] **Step 2: Run precommit + visually verify**

Run: `mix precommit` — expect PASS.
Open `http://localhost:1080/storybook/core_components/list` — confirm.

- [ ] **Step 3: Commit**

```bash
jj describe -m "feat(storybook): expand list story to empty/single/many/long states"
```

---

### Task 2.5: Bring `header` to rubric bar

**Files:**
- Modify: `storybook/core_components/header.story.exs`

- [ ] **Step 1: Read the header contract**

Run: `grep -A20 "def header" lib/media_centarr_web/core_components.ex`

Note: header typically has `<:subtitle>` and `<:actions>` slots, plus a `class` attr.

- [ ] **Step 2: Replace the story body**

```elixir
defmodule MediaCentarrWeb.Storybook.CoreComponents.Header do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.header/1
  def imports, do: [{MediaCentarrWeb.CoreComponents, button: 1}]
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :title_only,
        description: "Title only — no subtitle, no actions",
        slots: ["Library"]
      },
      %Variation{
        id: :with_subtitle,
        description: "Title + subtitle",
        slots: [
          "Library",
          ~s|<:subtitle>1,247 titles · 12 newly added</:subtitle>|
        ]
      },
      %Variation{
        id: :with_actions,
        description: "Title + actions slot",
        slots: [
          "Library",
          """
          <:actions>
            <.button>Refresh</.button>
            <.button variant="secondary">Settings</.button>
          </:actions>
          """
        ]
      },
      %Variation{
        id: :full,
        description: "Title + subtitle + actions",
        slots: [
          "Library",
          ~s|<:subtitle>1,247 titles · 12 newly added</:subtitle>|,
          """
          <:actions>
            <.button>Refresh</.button>
          </:actions>
          """
        ]
      },
      %Variation{
        id: :long_title,
        description: "Long title wraps without breaking layout",
        slots: [
          "A very long page title that exceeds typical width to verify the component handles wrapping gracefully"
        ]
      }
    ]
  end
end
```

- [ ] **Step 3: Run precommit + visually verify + commit**

Run: `mix precommit` — expect PASS.
Open `http://localhost:1080/storybook/core_components/header` — confirm.

```bash
jj describe -m "feat(storybook): expand header story to all slot combinations"
```

---

**Phase 2 exit criteria:** All seven `core_components` stories meet the rubric. Visual review at `/storybook/core_components` shows every variant + state.

---

## Phase 3 — Foundation Pages

**Phase goal:** Add four `:page` stories under `storybook/foundations/` so opening `/storybook` orients a designer in five minutes.

### Task 3.1: Create the foundations index file

**Files:**
- Create: `storybook/foundations/_foundations.index.exs`

- [ ] **Step 1: Write the index**

```elixir
defmodule MediaCentarrWeb.Storybook.Foundations do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "swatchbook", :light, "psb:mr-1"}
  def folder_index, do: 0  # Pin to the top of the sidebar.

  def entry("colors"), do: [icon: {:fa, "palette", :thin}, name: "Colors"]
  def entry("typography"), do: [icon: {:fa, "text-size", :thin}, name: "Typography"]
  def entry("spacing"), do: [icon: {:fa, "ruler-combined", :thin}, name: "Spacing & surfaces"]
  def entry("uidr_index"), do: [icon: {:fa, "list-tree", :thin}, name: "UIDR index"]
end
```

- [ ] **Step 2: Commit**

```bash
jj describe -m "feat(storybook): add foundations sidebar group"
```

---

### Task 3.2: Implement `colors.story.exs`

**Files:**
- Create: `storybook/foundations/colors.story.exs`

- [ ] **Step 1: Inspect daisyUI tokens currently configured**

Run: `grep -A20 "daisyui\|@plugin" assets/css/app.css | head -40`

Note which daisyUI semantic colors are configured (primary/secondary/accent/info/success/warning/error/neutral, plus base-100/200/300). Adjust the swatches below to match.

- [ ] **Step 2: Write the story**

```elixir
defmodule MediaCentarrWeb.Storybook.Foundations.Colors do
  @moduledoc """
  Color palette and surface treatments — the visual foundation everything else
  composes from. Mirrors the daisyUI semantic tokens configured in
  `assets/css/app.css`.
  """

  use PhoenixStorybook.Story, :page

  def doc, do: "daisyUI semantic colors and surface treatments."

  def render(assigns) do
    ~H"""
    <div class="media-centarr">
      <div class="psb:p-6 psb:space-y-10">
        <section>
          <h1 class="psb:text-2xl psb:font-semibold psb:mb-2 psb:text-zinc-100">Colors</h1>
          <p class="psb:text-sm psb:text-zinc-400 psb:mb-6">
            Semantic tokens. Use these instead of literal hex or Tailwind palette colors —
            they pick up the active daisyUI theme.
          </p>

          <div class="psb:grid psb:grid-cols-2 psb:md:grid-cols-4 psb:gap-4">
            <.swatch token="primary" use_for="Calls-to-action, primary buttons, brand accent" />
            <.swatch token="secondary" use_for="Secondary actions, less-emphasized buttons" />
            <.swatch token="accent" use_for="Highlight elements, badges, emphasis" />
            <.swatch token="info" use_for="Informational notices, neutral status" />
            <.swatch token="success" use_for="Confirmations, completed states" />
            <.swatch token="warning" use_for="Caution states, paused, attention-needed" />
            <.swatch token="error" use_for="Failure states, danger, destructive actions" />
            <.swatch token="neutral" use_for="Neutral surfaces, less-prominent UI" />
          </div>
        </section>

        <section>
          <h2 class="psb:text-xl psb:font-semibold psb:mb-2 psb:text-zinc-100">Base surfaces</h2>
          <div class="psb:grid psb:grid-cols-3 psb:gap-4">
            <.surface token="base-100" use_for="Default content surface" />
            <.surface token="base-200" use_for="Slightly elevated surface" />
            <.surface token="base-300" use_for="Background fill" />
          </div>
        </section>

        <section>
          <h2 class="psb:text-xl psb:font-semibold psb:mb-2 psb:text-zinc-100">Surface treatments</h2>

          <div class="psb:space-y-4">
            <div>
              <h3 class="psb:text-sm psb:font-medium psb:text-zinc-300 psb:mb-2">
                Body gradient (<code>body.media-centarr</code>)
              </h3>
              <div class="psb:rounded-lg psb:overflow-hidden psb:h-24 psb:bg-gradient-to-br psb:from-zinc-900 psb:via-zinc-800 psb:to-zinc-900">
              </div>
            </div>

            <div>
              <h3 class="psb:text-sm psb:font-medium psb:text-zinc-300 psb:mb-2">
                Glass surface (<code>.glass-surface</code>)
              </h3>
              <div class="glass-surface psb:rounded-lg psb:p-4 psb:text-zinc-200">
                Real <code>.glass-surface</code> rendered against the body gradient. Used on
                cards, modals, and the detail panel.
              </div>
            </div>

            <div>
              <h3 class="psb:text-sm psb:font-medium psb:text-zinc-300 psb:mb-2">
                Focus ring (<code>[data-input=keyboard]</code> / <code>[data-input=gamepad]</code>)
              </h3>
              <p class="psb:text-xs psb:text-zinc-500 psb:mb-2">
                Focus rings only render when the user is navigating with keyboard or gamepad.
                Mouse users never see them. The input system toggles
                <code>data-input</code> on <code>&lt;html&gt;</code>.
              </p>
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :token, :string, required: true
  attr :use_for, :string, required: true

  defp swatch(assigns) do
    ~H"""
    <div class="psb:rounded-lg psb:overflow-hidden psb:border psb:border-zinc-700">
      <div class={"psb:h-16 bg-#{@token}"}></div>
      <div class="psb:p-3 psb:bg-zinc-900">
        <div class={"psb:text-sm psb:font-medium text-#{@token}"}>{@token}</div>
        <div class="psb:text-xs psb:text-zinc-400 psb:mt-1">bg-{@token} / text-{@token}</div>
        <div class="psb:text-xs psb:text-zinc-500 psb:mt-2">{@use_for}</div>
      </div>
    </div>
    """
  end

  attr :token, :string, required: true
  attr :use_for, :string, required: true

  defp surface(assigns) do
    ~H"""
    <div class="psb:rounded-lg psb:overflow-hidden psb:border psb:border-zinc-700">
      <div class={"psb:h-12 bg-#{@token}"}></div>
      <div class="psb:p-3 psb:bg-zinc-900">
        <div class="psb:text-sm psb:font-medium psb:text-zinc-200">{@token}</div>
        <div class="psb:text-xs psb:text-zinc-500 psb:mt-1">{@use_for}</div>
      </div>
    </div>
    """
  end
end
```

> The interpolated class names (`bg-#{@token}`) need to be in Tailwind's safelist or regenerated. If they don't render, add the explicit token classes to `assets/css/app.css`'s `@source` block or use static class names with a `case` statement instead of interpolation. Verify rendering in step 3 before committing.

- [ ] **Step 3: Run precommit + visually verify**

Run: `mix precommit` — expect PASS.
Open `http://localhost:1080/storybook/foundations/colors` — confirm: every swatch shows a colored band, the use-for text reads naturally, glass surface renders against the body gradient.

If any swatch is unstyled, the issue is Tailwind class detection — switch to literal class names per swatch (a small `case @token do "primary" -> "bg-primary text-primary" ; ... end` helper).

- [ ] **Step 4: Commit**

```bash
jj describe -m "feat(storybook): add colors foundation page"
```

---

### Task 3.3: Implement `typography.story.exs`

**Files:**
- Create: `storybook/foundations/typography.story.exs`

- [ ] **Step 1: Inspect the typography setup**

Run: `grep -E "font-(sans|display|mono)|@theme|--font" assets/css/app.css | head -20`

Note the configured font families. Adjust below to match.

- [ ] **Step 2: Write the story**

```elixir
defmodule MediaCentarrWeb.Storybook.Foundations.Typography do
  @moduledoc """
  Typography scale and usage. Mirrors heading + body styles used across the
  app — change here = change the design system.
  """

  use PhoenixStorybook.Story, :page

  def doc, do: "Typography scale, weights, and usage."

  def render(assigns) do
    ~H"""
    <div class="media-centarr">
      <div class="psb:p-6 psb:space-y-8">
        <section>
          <h1 class="psb:text-2xl psb:font-semibold psb:mb-4 psb:text-zinc-100">Typography</h1>
          <p class="psb:text-sm psb:text-zinc-400">
            Live samples in the actual fonts. Tailwind class shown beside each.
          </p>
        </section>

        <section>
          <h2 class="psb:text-xl psb:font-semibold psb:mb-3 psb:text-zinc-100">Headings</h2>

          <div class="psb:space-y-4">
            <.type_row tw="text-4xl font-semibold tracking-tight" sample="Library" />
            <.type_row tw="text-3xl font-semibold tracking-tight" sample="A page heading" />
            <.type_row tw="text-2xl font-semibold" sample="Section title" />
            <.type_row tw="text-xl font-medium" sample="Subsection" />
            <.type_row tw="text-lg font-medium" sample="Card title" />
            <.type_row tw="text-base" sample="Body text — the default reading size for prose." />
            <.type_row tw="text-sm text-zinc-400" sample="Caption text — for metadata, timestamps, supporting copy." />
            <.type_row tw="text-xs uppercase tracking-wider text-zinc-500" sample="LABEL · OVERLINE" />
          </div>
        </section>

        <section>
          <h2 class="psb:text-xl psb:font-semibold psb:mb-3 psb:text-zinc-100">Weights</h2>

          <div class="psb:space-y-2">
            <p class="psb:text-base psb:font-light psb:text-zinc-200">font-light — 300</p>
            <p class="psb:text-base psb:font-normal psb:text-zinc-200">font-normal — 400</p>
            <p class="psb:text-base psb:font-medium psb:text-zinc-200">font-medium — 500</p>
            <p class="psb:text-base psb:font-semibold psb:text-zinc-200">font-semibold — 600</p>
            <p class="psb:text-base psb:font-bold psb:text-zinc-200">font-bold — 700</p>
          </div>
        </section>

        <section>
          <h2 class="psb:text-xl psb:font-semibold psb:mb-3 psb:text-zinc-100">Numerics</h2>

          <p class="psb:text-sm psb:text-zinc-400 psb:mb-3">
            Use <code>tabular-nums</code> for any number that updates in place
            (progress percentages, durations, counts) — keeps the digits aligned.
          </p>

          <div class="psb:grid psb:grid-cols-2 psb:gap-4">
            <div class="psb:rounded psb:bg-zinc-900 psb:p-3 psb:font-mono psb:text-zinc-200">
              <div>Without tabular-nums:</div>
              <div class="psb:text-2xl">123.4 → 1234.5 → 12.3</div>
            </div>
            <div class="psb:rounded psb:bg-zinc-900 psb:p-3 psb:font-mono psb:text-zinc-200">
              <div>With tabular-nums:</div>
              <div class="psb:text-2xl psb:tabular-nums">123.4 → 1234.5 → 12.3</div>
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :tw, :string, required: true
  attr :sample, :string, required: true

  defp type_row(assigns) do
    ~H"""
    <div class="psb:flex psb:items-baseline psb:gap-6 psb:border-b psb:border-zinc-800 psb:pb-3">
      <div class={"psb:flex-1 psb:text-zinc-100 #{prefix_psb(@tw)}"}>{@sample}</div>
      <code class="psb:text-xs psb:text-zinc-500 psb:font-mono">{@tw}</code>
    </div>
    """
  end

  # The `tw` shown beside each sample is what a developer would type in HEEx
  # (no `psb:` prefix). The same classes need `psb:` prefixes to render here.
  defp prefix_psb(classes) do
    classes
    |> String.split(" ")
    |> Enum.map_join(" ", &"psb:#{&1}")
  end
end
```

- [ ] **Step 3: Run precommit + visually verify + commit**

Run: `mix precommit` — expect PASS.
Open `/storybook/foundations/typography` — confirm: every heading row reads at the right size, weights show visible differences, tabular-nums keeps columns aligned.

```bash
jj describe -m "feat(storybook): add typography foundation page"
```

---

### Task 3.4: Implement `spacing.story.exs`

**Files:**
- Create: `storybook/foundations/spacing.story.exs`

- [ ] **Step 1: Write the story**

```elixir
defmodule MediaCentarrWeb.Storybook.Foundations.Spacing do
  @moduledoc """
  Spacing scale and surface treatments. Tailwind defaults plus our `.glass-surface`
  conventions.
  """

  use PhoenixStorybook.Story, :page

  def doc, do: "Spacing scale and surface treatments."

  @scale [
    {1, "0.25rem", "Tightest — between icon and label"},
    {2, "0.5rem", "Compact lists, inline groups"},
    {3, "0.75rem", "Default inner padding for small components"},
    {4, "1rem", "Default — most card padding, button gaps"},
    {6, "1.5rem", "Section padding, sidebar gaps"},
    {8, "2rem", "Major separator, header padding"},
    {12, "3rem", "Page margin"},
    {16, "4rem", "Hero spacing"},
    {24, "6rem", "Large hero / landing"}
  ]

  def render(assigns) do
    assigns = assign(assigns, :scale, @scale)

    ~H"""
    <div class="media-centarr">
      <div class="psb:p-6 psb:space-y-10">
        <section>
          <h1 class="psb:text-2xl psb:font-semibold psb:mb-4 psb:text-zinc-100">Spacing</h1>

          <div class="psb:space-y-2">
            <div :for={{n, rem, use_for} <- @scale} class="psb:flex psb:items-center psb:gap-4">
              <code class="psb:w-12 psb:text-xs psb:text-zinc-500 psb:font-mono">p-{n}</code>
              <code class="psb:w-20 psb:text-xs psb:text-zinc-500 psb:font-mono">{rem}</code>
              <div class="psb:bg-zinc-700" style={"width: #{rem}; height: 1rem;"}></div>
              <span class="psb:text-sm psb:text-zinc-400">{use_for}</span>
            </div>
          </div>
        </section>

        <section>
          <h2 class="psb:text-xl psb:font-semibold psb:mb-3 psb:text-zinc-100">Glass surface</h2>

          <div class="glass-surface psb:rounded-lg psb:p-6 psb:text-zinc-200 psb:max-w-xl">
            Used on cards, modals, the detail panel, the toolbar. The actual
            <code>.glass-surface</code> class — translucent fill, blurred backdrop,
            subtle border. Layers cleanly over the body gradient.
          </div>
        </section>

        <section>
          <h2 class="psb:text-xl psb:font-semibold psb:mb-3 psb:text-zinc-100">Hover scale + focus ring</h2>

          <p class="psb:text-sm psb:text-zinc-400 psb:mb-3">
            Cards and posters scale up on hover (mouse) and show a focus ring on
            keyboard/gamepad navigation. Hover the box below; tab to it for the ring.
          </p>

          <button
            class="psb:rounded-lg psb:bg-zinc-800 psb:p-6 psb:text-zinc-200 psb:transition-transform psb:hover:scale-105 psb:focus:outline-none psb:focus:ring-2 psb:focus:ring-primary"
            type="button"
          >
            Hover or tab to me
          </button>
        </section>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 2: Run precommit + visually verify + commit**

Run: `mix precommit` — expect PASS.
Open `/storybook/foundations/spacing` — confirm: spacing rows scale linearly, glass surface renders correctly, hover/focus on the button responds.

```bash
jj describe -m "feat(storybook): add spacing & surfaces foundation page"
```

---

### Task 3.5: Implement `uidr_index.story.exs`

**Files:**
- Create: `storybook/foundations/uidr_index.story.exs`

- [ ] **Step 1: Find existing UIDR rules**

Run: `grep -rn "UIDR-" .claude/skills/user-interface/ docs/ | head -30`

Collect the (number, title, one-line description) for each rule.

- [ ] **Step 2: Write the story**

```elixir
defmodule MediaCentarrWeb.Storybook.Foundations.UidrIndex do
  @moduledoc """
  UI Design Rule (UIDR) index. Each rule links to the component story that
  implements it (when one exists).

  Source of truth for rule text: `.claude/skills/user-interface/SKILL.md`.
  This page is the visual entry-point; the skill file holds the prose.
  """

  use PhoenixStorybook.Story, :page

  def doc, do: "Browseable index of UI design rules."

  # Update this list when a new UIDR is added to the user-interface skill.
  # Format: {number, title, story_path_or_nil, summary}
  @rules [
    {1, "Theme is dark with a subtle gradient", nil,
     "Body uses .media-centarr gradient. Cards use .glass-surface."},
    {2, "Buttons declare semantic variants", "/storybook/core_components/button",
     "primary/secondary/action/info/risky/danger/dismiss/neutral/outline."},
    {3, "Inputs surface errors inline beneath the field", "/storybook/core_components/input",
     "Errors are aria-described. No toast for field-level errors."},
    {4, "Cards scale on hover, focus-ring on keyboard/gamepad", "/storybook/foundations/spacing",
     "Mouse never sees focus rings. Toggled by [data-input]."}
    # Add additional UIDRs as discovered. The list is canonical when the
    # user-interface skill agrees with it.
  ]

  def render(assigns) do
    assigns = assign(assigns, :rules, @rules)

    ~H"""
    <div class="media-centarr">
      <div class="psb:p-6 psb:max-w-3xl">
        <section class="psb:mb-6">
          <h1 class="psb:text-2xl psb:font-semibold psb:mb-2 psb:text-zinc-100">UIDR index</h1>
          <p class="psb:text-sm psb:text-zinc-400">
            UI Design Rules — the conventions every screen follows. Each entry
            links to a story or page that demonstrates the rule.
          </p>
        </section>

        <ol class="psb:space-y-4">
          <li
            :for={{n, title, path, summary} <- @rules}
            class="psb:rounded-lg psb:border psb:border-zinc-800 psb:bg-zinc-900 psb:p-4"
          >
            <div class="psb:flex psb:items-start psb:gap-4">
              <span class="psb:flex psb:items-center psb:justify-center psb:w-10 psb:h-10 psb:rounded-full psb:bg-zinc-800 psb:text-sm psb:font-mono psb:text-primary">
                {String.pad_leading(Integer.to_string(n), 3, "0")}
              </span>
              <div class="psb:flex-1">
                <h3 class="psb:text-base psb:font-medium psb:text-zinc-100 psb:mb-1">
                  {title}
                </h3>
                <p class="psb:text-sm psb:text-zinc-400 psb:mb-2">{summary}</p>
                <%= if path do %>
                  <a href={path} class="psb:text-xs psb:text-primary psb:hover:underline">
                    See story →
                  </a>
                <% else %>
                  <span class="psb:text-xs psb:text-zinc-600">No story yet</span>
                <% end %>
              </div>
            </div>
          </li>
        </ol>
      </div>
    </div>
    """
  end
end
```

> Replace `@rules` with the actual UIDR list found in step 1. If there are more than ~12 rules, keep the page paginated by category (visual / interaction / accessibility).

- [ ] **Step 3: Update `docs/storybook.md`**

Add a "Foundations" section right after the "Routes" section:

```markdown
## Foundations

Four `:page` stories under `storybook/foundations/` document the design system itself:

- `/storybook/foundations/colors` — daisyUI palette + surface treatments
- `/storybook/foundations/typography` — type scale, weights, numeric guidance
- `/storybook/foundations/spacing` — spacing scale, glass surface, hover/focus rules
- `/storybook/foundations/uidr_index` — browseable UIDR rules with links to component stories

The UIDR index is the design-system entry point. Skill files keep the prose; storybook owns the visuals.
```

- [ ] **Step 4: Run precommit + visually verify + commit**

Run: `mix precommit` — expect PASS.
Open `/storybook/foundations/uidr_index` — confirm: every rule has a number badge, links work, the page reads as orientation material.

```bash
jj describe -m "feat(storybook): add UIDR index page + docs section"
```

---

**Phase 3 exit criteria:**
- ✅ Four foundation pages exist and render
- ✅ Sidebar shows "Foundations" group at the top
- ✅ `docs/storybook.md` references the foundations
- ✅ UIDR rules link out to component stories where they exist

---

## Phase 4 — Self-Contained Composites

**Phase goal:** Stories for every component without contract debt. Seven components, one PR each.

For each component below, the workflow is identical:

1. Read the component's `attr` declarations and slot signatures.
2. Identify variants × sizes × states the component supports.
3. Write the story (one or more `Variation` / `VariationGroup`).
4. Add the story to the area's `_<area>.index.exs`.
5. Remove the `@storybook_status :pending` attribute (it's `:covered` now — implicit).
6. `mix precommit` → visually verify → commit.

The repeating recipe goes in subagent dispatches per component, not as bite-sized steps in this plan — the per-component shape is identical and listing it five times would be DRY-violating.

### Task 4.1: `modal_shell` story

- [ ] Read `lib/media_centarr_web/components/modal_shell.ex` for the contract.
- [ ] Create `storybook/composites/_composites.index.exs` (folder index).
- [ ] Create `storybook/composites/modal_shell.story.exs` with: closed state, open state (one variant), open with action footer, open with destructive footer, long-content scrolling. The "always-in-DOM" pattern means open/closed is an attribute toggle, not a mount/unmount — handle visibility per the storybook skill's "Visibility for modal/slideover-style components" recipe.
- [ ] Remove `@storybook_status :pending` + `@storybook_reason` from `modal_shell.ex`.
- [ ] `mix precommit` → visual verify at `/storybook/composites/modal_shell` → commit `feat(storybook): add modal_shell story`.

### Task 4.2: `hero_card` story

- [ ] Read `lib/media_centarr_web/components/hero_card.ex`.
- [ ] Create `storybook/composites/hero_card.story.exs` with: with-artwork, missing-artwork (fallback), long title, with metadata badges, focused state visualization.
- [ ] Remove the pending attribute. Precommit → verify → commit.

### Task 4.3: `detail/facet_strip` story

- [ ] Read `lib/media_centarr_web/components/detail/facet_strip.ex` and `detail/facet.ex` (the view-model).
- [ ] Create `storybook/detail/_detail.index.exs` (folder index).
- [ ] Create `storybook/detail/facet_strip.story.exs` with: text-only facets, chips facets, rating facet, mixed-kinds row, single-facet, no-facets (empty). Build `Detail.Facet` structs as literals in the story (`Facet.text("Year", "2024")`, etc.).
- [ ] Remove the pending attribute. Precommit → verify → commit.

### Task 4.4: `detail/metadata_row` story

- [ ] Read the component.
- [ ] Create `storybook/detail/metadata_row.story.exs` with: minimal (title only), full (title + year + runtime + rating), missing-rating, missing-runtime, very-long-title.
- [ ] Remove pending. Precommit → verify → commit.

### Task 4.5: `detail/play_card` story

- [ ] Read the component.
- [ ] Create `storybook/detail/play_card.story.exs` with: ready-to-play, in-progress (various %), completed, missing-artwork, paused, error state.
- [ ] Remove pending. Precommit → verify → commit.

### Task 4.6: `detail/section` story

- [ ] Read the component.
- [ ] Create `storybook/detail/section.story.exs` with: with-children, empty children, with title + description, no description.
- [ ] Remove pending. Precommit → verify → commit.

### Task 4.7: `detail/hero` story

- [ ] Read the component.
- [ ] Create `storybook/detail/hero.story.exs` with: with-backdrop, missing-backdrop, with-tagline, no-tagline, with-actions slot.
- [ ] Remove pending. Precommit → verify → commit.

---

**Phase 4 exit criteria:** Seven stories at rubric bar; sidebar shows three new groups (Composites, Detail, plus the existing Foundations + CoreComponents); `mix credo` passes (every component is `:covered` or has a declared status).

---

## Phase 5 — Contract-Driven Cards

**Phase goal:** Storyboarding the library cards as the forcing function for the typed-attr / ViewModel migration. One PR per component.

This phase deliberately does **not** spell out bite-sized steps because each component's contract refactor is unpredictable — the smell shape determines the fix. The per-component workflow is:

1. **Read the live component contract.** What `attr` declarations does it have? Are any `:list` / `:map` / `:any` without a `doc:` waiver? Does the call-site use the structure in ways the attr doesn't capture?
2. **Sketch the story you'd want.** What variations? Loading / empty / error / loaded / variant matrix / edge cases. Don't write it yet — what *would* you write?
3. **If the sketch is straightforward → write the story.** Same recipe as Phase 4.
4. **If the sketch reveals a contract smell** (you can't construct fixture data without faking context, or the component reaches into LiveView assigns it shouldn't) → fix the contract first:
   - Introduce a typed view-model struct in `lib/media_centarr_web/view_models/` (or inline in the component file if tightly scoped).
   - Update the component to declare `attr :card, ViewModel.t(), required: true` and consume it.
   - Update call sites to construct the view-model.
   - **Now** write the story, with literal struct fixtures.
5. `mix precommit` (boundaries + tests + credo all matter here) → visual verify → commit `feat(storybook): add <component> story` *or* `refactor(<area>): typed contract for <component> + story`.
6. Remove the `:pending` declaration from the module.

### Component order (one per task)

| Order | Component | File |
|------:|-----------|------|
| 5.1 | `poster_card` | `lib/media_centarr_web/components/library_cards.ex` |
| 5.2 | `cw_card` | `lib/media_centarr_web/components/library_cards.ex` |
| 5.3 | `toolbar` | `lib/media_centarr_web/components/library_cards.ex` |
| 5.4 | `poster_row` | `lib/media_centarr_web/components/poster_row.ex` |
| 5.5 | `upcoming_card` | `lib/media_centarr_web/components/upcoming_cards.ex` |
| 5.6 | `detail_panel` | `lib/media_centarr_web/components/detail_panel.ex` |

Reference: [`~/src/media-centarr/component-contract-plan.md`](~/src/media-centarr/component-contract-plan.md) for the typed-attr / ViewModel direction-of-travel.

`library_cards.ex` will need its own `storybook/library_cards/_library_cards.index.exs` index file when the first of 5.1/5.2/5.3 lands.

**Phase 5 exit criteria:** All six stories at rubric bar; `library_cards.ex`, `poster_row.ex`, `upcoming_cards.ex`, `detail_panel.ex` either have no `@storybook_status` (covered) or are still `:pending` with an explicit deferred-reason — but the design intent is that all six end as `:covered`.

---

## Self-Review Checklist (run before declaring complete)

- [ ] `mix precommit` clean from project root.
- [ ] `mix credo --strict` passes — every component is declared or covered.
- [ ] `/storybook` sidebar shows: Foundations, CoreComponents, Composites, Detail, LibraryCards.
- [ ] Every story renders without runtime error (visit each one).
- [ ] `docs/storybook.md` triage table matches the source-of-truth `@storybook_status` attributes.
- [ ] `.claude/skills/storybook/SKILL.md` documents the `@storybook_status` convention.
- [ ] No real show titles in any story fixture; all generic placeholders or PD/CC names.

---

## Notes for the Implementer

- **Test-first applies to the Credo check (Task 1.4 → 1.5)** but not to story writing — stories are visual specimens, not behaviour. Per the storybook skill, "no assertions, no logic" is the rule.
- **Visual verification after every story.** Open `localhost:1080/storybook/<path>` and look. Type-check passing isn't enough.
- **One commit per logical unit.** Don't batch multiple stories into one commit — they're independent units of work.
- **Use `jj describe`, not `git commit`.** This repo is jujutsu; raw git corrupts. Per `~/src/media-centarr/CLAUDE.md`.
- **Phase boundaries are ship-points.** Phase 1 ships, Phase 2 ships, etc. Don't accumulate uncommitted phases.
- **If the storybook skill text disagrees with this plan,** the skill wins (it's the durable convention; this plan is a one-time roadmap). Update the plan inline if you discover the divergence.
