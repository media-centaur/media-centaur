# Feed timeline scope — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Own reviews and listings join the Discovery Feed timeline, behind an Everyone / Friends / You scope on the house segmented control, with the rows in one list surface.

**Architecture:** The feed projection (`DiscoveryLive.FeedEntries`) admits own rows and filters by a scope that lives in the URL (`/discovery?scope=`); the row view-model carries `author` and `own?`; the card becomes a row in one inset glass list. The segmented pill becomes one `segmented_control/1` component in `CoreComponents`, and the three existing hand-rolled pills (Settings choice, Library type tabs, strip chart window) compose it. Delete stays in the modal.

**Tech Stack:** Phoenix LiveView, Tailwind v4 + daisyUI, Phoenix Storybook, ExUnit + LazyHTML. Spec: `docs/superpowers/specs/2026-09-24-feed-timeline-scope-design.md`. Record: UIDR-045.

**Ground rules for this repo (read before Task 1):**

- Never run `mix` directly in an agent shell. Every command below uses `~/scripts/agents/agent-mix`, which builds outside the checkout so the dev daily driver is never disturbed.
- Test-first: write the failing test, run it, see it fail for the right reason, then implement.
- Zero warnings. `mix precommit` runs `--warnings-as-errors`, Credo `--strict`, and the storybook compile/render tests.
- No real show titles anywhere (`Sample Movie`, `Sample Show`).
- Commit after each task. End every commit message with the line `Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L`. Never add a `Co-Authored-By` trailer. Commit straight to `main`; do not push.
- The dev server on :2160 hot-reloads from the checkout. For a visual check use `~/scripts/agents/page-shot --url http://127.0.0.1:2160/discovery --viewport 1920x1080 --wait-ms 3000` and Read the PNG. The `assets/` watchers are off: after a CSS or template change that adds new Tailwind utilities run `~/scripts/agents/agent-mix assets.build`.

---

## File structure

**Create**
- `storybook/core_components/segmented_control.story.exs` — the pill's story (three options, chosen one, a five-option row).
- `test/media_centaur_web/components/segmented_control_test.exs` — the pill's contract: one `aria-pressed`, `phx-value-choice` per option, nav attributes on or off, `value` refused.
- `storybook/discovery/feed_entry_row.story.exs` — renamed from `feed_entry_card.story.exs` (`git mv`), rewritten.
- `lib/media_centaur_web/components/discovery/feed_entry_row.ex` — renamed from `feed_entry_card.ex` (`git mv`), rewritten as a row.

**Modify**
- `lib/media_centaur_web/components/core_components.ex` — add `phx_values/1` (public) and `segmented_control/1`.
- `lib/media_centaur_web/components/settings.ex` — `settings_choice/1` composes `segmented_control/1`; drop the private `phx_values/1`.
- `lib/media_centaur_web/components/glass_menu.ex` — drop the private `phx_values/1`, use the public one.
- `lib/media_centaur_web/components/library_cards.ex` — the toolbar's type tabs become `segmented_control/1`.
- `lib/media_centaur_web/live/library_live.ex` — `switch_tab` reads `choice`.
- `lib/media_centaur_web/components/strip_chart.ex` — the window pill becomes `segmented_control/1`.
- `lib/media_centaur_web/components/strip_chart/feed.ex` — `strip_chart:window` reads `choice`.
- `test/media_centaur_web/live/status_live_test.exs` — the window click selects `phx-value-choice`.
- `lib/media_centaur_web/live/discovery_live/activity_words.ex` — `verb/3` with a subject.
- `test/media_centaur_web/live/discovery_live/activity_words_test.exs`
- `lib/media_centaur_web/components/discovery/feed_entry.ex` — `author` + `own?` replace `nickname`.
- `lib/media_centaur_web/live/discovery_live/feed_entries.ex` — scope, `parse_scope/1`, `empty_reason/2`, own rows.
- `test/media_centaur_web/live/discovery_live/feed_entries_test.exs`
- `storybook/discovery/_discovery.index.exs` — the renamed entry.
- `lib/media_centaur_web/live/discovery_live.ex` — scope in the URL, the pill, the list surface, the empty diagnosis, the width, the Feed tab link.
- `test/media_centaur_web/live/discovery_live_test.exs` — feed tests for own rows and the scope.
- `test/media_centaur_web/page_smoke_test.exs` — the two scoped routes.
- `lib/media_centaur_web/components/title/row.ex` — one moduledoc sentence names the row component.
- `docs/social.md`, `docs/GLOSSARY.md`, `.claude/skills/user-interface/SKILL.md`, `../media-centaur.wiki/Social.md` — docs.

---

### Task 1: `segmented_control/1` and a public `phx_values/1`

**Files:**
- Modify: `lib/media_centaur_web/components/core_components.ex`
- Modify: `lib/media_centaur_web/components/settings.ex:255-300` (`settings_choice/1`) and `:536-546` (private `phx_values/1`)
- Modify: `lib/media_centaur_web/components/glass_menu.ex:256-266` (private `phx_values/1`)
- Create: `test/media_centaur_web/components/segmented_control_test.exs`
- Create: `storybook/core_components/segmented_control.story.exs`
- Modify: `storybook/core_components/_core_components.index.exs`

- [ ] **Step 1: Write the failing component test**

```elixir
defmodule MediaCentaurWeb.Components.SegmentedControlTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaurWeb.CoreComponents

  @options [{:everyone, "Everyone"}, {:friends, "Friends"}, {:you, "You"}]

  defp render(overrides) do
    attrs =
      Keyword.merge(
        [label: "Scope", options: @options, selected: :friends, event: "pick"],
        overrides
      )

    render_component(&CoreComponents.segmented_control/1, attrs)
  end

  defp buttons(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.query("button.tab")

  test "one button per option carrying the event and its value as choice; only the chosen one is pressed" do
    buttons = buttons(render([]))

    assert LazyHTML.attribute(buttons, "phx-click") == ["pick", "pick", "pick"]
    assert LazyHTML.attribute(buttons, "phx-value-choice") == ["everyone", "friends", "you"]
    assert LazyHTML.attribute(buttons, "aria-pressed") == ["false", "true", "false"]
    assert Enum.map(buttons, &LazyHTML.text/1) == ["Everyone", "Friends", "You"]
  end

  test "the group carries its accessible name and extra event params reach every button" do
    html = render(id: "scope", event_value: %{"id" => "chart"})
    group = html |> LazyHTML.from_fragment() |> LazyHTML.query("#scope[role='group']")

    assert LazyHTML.attribute(group, "aria-label") == ["Scope"]
    assert html |> buttons() |> LazyHTML.attribute("phx-value-id") == ["chart", "chart", "chart"]
  end

  test "options are nav items by default and plain buttons on an iteration-phase surface" do
    assert render([]) |> buttons() |> LazyHTML.attribute("data-nav-item") |> length() == 3
    assert render([]) |> buttons() |> LazyHTML.attribute("tabindex") == ["0", "0", "0"]

    assert render(nav: false) |> buttons() |> LazyHTML.attribute("data-nav-item") == []
    assert render(nav: false) |> buttons() |> LazyHTML.attribute("tabindex") == []
  end

  test "an event param named value is refused: a button's native value clobbers it on click" do
    assert_raise ArgumentError, ~r/phx-value-value/, fn ->
      render(event_value: %{"value" => "x"})
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/segmented_control_test.exs`
Expected: FAIL — `CoreComponents.segmented_control/1 is undefined`.

- [ ] **Step 3: Add `phx_values/1` and `segmented_control/1` to `CoreComponents`**

Append to `lib/media_centaur_web/components/core_components.ex`, after `badge/1` (keep the module's existing ordering conventions; both functions are public):

```elixir
  @doc """
  `phx-value-*` attributes from a map of extra event params, string
  keys. A `value` key is refused: a button's native `value` property
  clobbers `phx-value-value` on click (MC0021), and the Credo check
  cannot see keys that arrive through a map.
  """
  @spec phx_values(map() | nil) :: map()
  def phx_values(nil), do: %{}

  def phx_values(map) do
    Map.new(map, fn
      {key, _value} when key in ["value", :value] ->
        raise ArgumentError, "phx-value-value is clobbered on click; use a descriptive key"

      {key, value} ->
        {"phx-value-#{key}", value}
    end)
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true, doc: "the group's accessible name"
  attr :options, :list, required: true, doc: "`{value, label}` pairs in display order"

  attr :selected, :any,
    required: true,
    doc: "the current option value — a string or atom, whatever the owner stores. Compared with `==`."

  attr :event, :string, required: true
  attr :event_value, :map, default: %{}, doc: "extra `phx-value-*` params (string keys)"

  attr :nav, :boolean,
    default: true,
    doc: "false on an iteration-phase surface: no nav items until its hardening pass"

  attr :class, :string, default: nil

  @doc """
  The house pick-one pill for content surfaces: a glass rail with the
  chosen option lifted (`.segmented-control` in `app.css`). Clicking an
  option pushes `@event` with `choice` set to the option value (never
  `value`: a button's native `value` property would clobber it, MC0021).
  The chosen option carries `aria-pressed`. The Settings kit's
  `settings_choice/1` composes this inside its row; Library's type tabs,
  the strip chart's window and the Feed's scope render it directly.
  Story: `/storybook/core_components/segmented_control`.
  """
  def segmented_control(assigns) do
    ~H"""
    <div
      id={@id}
      class={["tabs tabs-boxed segmented-control w-fit max-w-full", @class]}
      role="group"
      aria-label={@label}
    >
      <button
        :for={{value, label} <- @options}
        type="button"
        class="tab text-sm"
        phx-click={@event}
        phx-value-choice={value}
        {phx_values(@event_value)}
        aria-pressed={to_string(value == @selected)}
        data-nav-item={@nav}
        tabindex={if @nav, do: "0"}
      >
        {label}
      </button>
    </div>
    """
  end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/segmented_control_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Compose it from `settings_choice/1` and drop both private `phx_values/1`**

In `lib/media_centaur_web/components/settings.ex`, replace the pill inside `settings_choice/1` (the `<div id={@id} class="tabs tabs-boxed segmented-control …">…</div>` block) with:

```heex
      <.segmented_control
        id={@id}
        label={@label}
        options={@options}
        selected={@selected}
        event={@event}
        event_value={@event_value}
      />
```

Delete the private `phx_values/1` (both clauses, lines 538–546) from `settings.ex`. The remaining `{phx_values(@event_value)}` call sites in the stepper resolve to the public function through `use MediaCentaurWeb, :html`, which imports `CoreComponents`.

In `lib/media_centaur_web/components/glass_menu.ex`, delete the private `phx_values/1` (both clauses and the comment above them, lines 254–266). Its call sites also resolve to the public function.

- [ ] **Step 6: Write the story and register it**

Create `storybook/core_components/segmented_control.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.CoreComponents.SegmentedControl do
  @moduledoc """
  The house pick-one pill for content surfaces: a glass rail, the chosen
  option lifted, `aria-pressed` on it. The Feed's scope, Library's type
  tabs and the strip chart's window are this component; the Settings
  kit's choice row composes it.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.CoreComponents.segmented_control/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :three_options,
        description: "Three options, the first chosen.",
        attributes: %{
          label: "Scope",
          options: [{:everyone, "Everyone"}, {:friends, "Friends"}, {:you, "You"}],
          selected: :everyone,
          event: "pick"
        }
      },
      %Variation{
        id: :last_chosen,
        description: "The chosen option can be any of them.",
        attributes: %{
          label: "Scope",
          options: [{:everyone, "Everyone"}, {:friends, "Friends"}, {:you, "You"}],
          selected: :you,
          event: "pick"
        }
      },
      %Variation{
        id: :six_options,
        description: "A wider row: the strip chart's windows.",
        attributes: %{
          label: "Window",
          options: [{"5m", "5m"}, {"1h", "1h"}, {"5h", "5h"}, {"1d", "1d"}, {"1w", "1w"}, {"1mo", "1mo"}],
          selected: "1h",
          event: "pick",
          nav: false
        }
      }
    ]
  end
end
```

Add to `storybook/core_components/_core_components.index.exs`, keeping alphabetical order:

```elixir
  def entry("segmented_control"), do: [icon: {:fa, "grip-lines", :thin}, name: "Segmented control"]
```

- [ ] **Step 7: Run the affected suites**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components test/media_centaur_web/live/settings_live_test.exs test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: 0 failures. (The Settings choice rows render the same markup through the component; their tests assert `aria-pressed` and `phx-value-choice`, which are unchanged.)

- [ ] **Step 8: Commit**

```bash
git add lib/media_centaur_web/components/core_components.ex lib/media_centaur_web/components/settings.ex lib/media_centaur_web/components/glass_menu.ex test/media_centaur_web/components/segmented_control_test.exs storybook/core_components/segmented_control.story.exs storybook/core_components/_core_components.index.exs
git commit -m "feat(ui): one segmented control for content surfaces, composed by the Settings choice

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Task 2: Library's type tabs and the strip chart's window on the shared pill

**Files:**
- Modify: `lib/media_centaur_web/components/library_cards.ex:181-194`
- Modify: `lib/media_centaur_web/live/library_live.ex:133`
- Modify: `lib/media_centaur_web/components/strip_chart.ex:45-61`
- Modify: `lib/media_centaur_web/components/strip_chart/feed.ex:127`
- Modify: `test/media_centaur_web/live/status_live_test.exs:55`

- [ ] **Step 1: Change the status test to the component's contract and watch it fail**

In `test/media_centaur_web/live/status_live_test.exs` line 55, replace:

```elixir
      view |> element("[phx-value-window='1w']") |> render_click()
```

with:

```elixir
      view |> element("[phx-value-choice='1w']") |> render_click()
```

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/status_live_test.exs`
Expected: 1 failure — `expected selector "[phx-value-choice='1w']" to return a single element, but got none`.

- [ ] **Step 2: Migrate the strip chart's pill**

In `lib/media_centaur_web/components/strip_chart.ex`, replace the block from `<div class="tabs tabs-boxed segmented-control w-fit shrink-0"` through its closing `</div>` (lines 45–61) with:

```heex
          <.segmented_control
            label="Window"
            options={Enum.map(@windows, &{&1, Atom.to_string(&1)})}
            selected={@window}
            event="strip_chart:window"
            event_value={%{"id" => @id}}
            nav={false}
            class="shrink-0"
          />
```

(`nav={false}` keeps today's behaviour: the strip chart's pills were never nav items.) Update the moduledoc sentence "The pills push `strip_chart:window` with `phx-value-id` and `phx-value-window`" to "The pill pushes `strip_chart:window` with `phx-value-id` and the window as `choice`".

In `lib/media_centaur_web/components/strip_chart/feed.ex` line 127, change the pattern:

```elixir
  defp on_event("strip_chart:window", %{"id" => id, "choice" => label}, socket, id) do
```

- [ ] **Step 3: Run the status test to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/status_live_test.exs`
Expected: 0 failures.

- [ ] **Step 4: Migrate Library's type tabs**

In `lib/media_centaur_web/components/library_cards.ex`, replace the block from `<div role="tablist" class="tabs tabs-boxed segmented-control w-fit">` through its closing `</div>` (lines 181–194) with:

```heex
        <.segmented_control
          label="Type"
          options={[{:all, "All"}, {:movies, "Movies"}, {:tv, "TV"}]}
          selected={@active_tab}
          event="switch_tab"
        />
```

In `lib/media_centaur_web/live/library_live.ex` line 133, change the handler head:

```elixir
  def handle_event("switch_tab", %{"choice" => tab}, socket) do
```

- [ ] **Step 5: Run the Library and storybook suites**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/library_live_test.exs test/media_centaur_web/live/library_live_tracking_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: 0 failures. No test clicks the type tabs by `phx-value-tab` (verified with `grep -rn "phx-value-tab\|switch_tab" test`, which returns only Apps-page hits), and the toolbar story's variations pass `active_tab`, which is unchanged.

- [ ] **Step 6: Check the nav graph still finds the type tabs**

The Library toolbar's nav zone is `data-nav-zone="toolbar"` on the outer div and the tab buttons sat two levels below it; the component's root div replaces the `tablist` div, so the depth is unchanged. Confirm with:

```bash
~/scripts/agents/mc-nav-trace --url http://127.0.0.1:2160/library 'Right Right'
```

Expected: the cursor steps All → Movies → TV. If the trace tool reports no items in the toolbar zone, the zone's config in `assets/js/input/config.js` needs the same selector it had; nothing in this task changes that file.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/components/library_cards.ex lib/media_centaur_web/live/library_live.ex lib/media_centaur_web/components/strip_chart.ex lib/media_centaur_web/components/strip_chart/feed.ex test/media_centaur_web/live/status_live_test.exs
git commit -m "refactor(ui): Library type tabs and the strip chart window render the shared segmented control

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Task 3: The verb takes a subject

**Files:**
- Modify: `lib/media_centaur_web/live/discovery_live/activity_words.ex`
- Modify: `test/media_centaur_web/live/discovery_live/activity_words_test.exs`

- [ ] **Step 1: Write the failing test**

Add to the first module in `test/media_centaur_web/live/discovery_live/activity_words_test.exs`, after the "each kind has a verb" test:

```elixir
  test "the verb agrees with its subject: a friend wants to watch, you want to watch" do
    assert ActivityWords.verb(:listing, nil, :friend) == "wants to watch"
    assert ActivityWords.verb(:listing, nil, :you) == "want to watch"
    assert ActivityWords.verb(:review, nil, :you) == "reviewed"
    assert ActivityWords.verb(:watched, nil, :you) == "watched"
    assert ActivityWords.verb(:listing, nil) == "wants to watch"
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live/activity_words_test.exs`
Expected: FAIL — `ActivityWords.verb/3 is undefined`.

- [ ] **Step 3: Implement `verb/3`**

Replace the `verb` doc, spec and clauses in `lib/media_centaur_web/live/discovery_live/activity_words.ex` with:

```elixir
  @typedoc "Who the sentence is about: a friend, third person, or You, second person."
  @type subject :: :friend | :you

  @doc """
  The verb for a kind, agreeing with its subject: "wants to watch" for
  a friend, "want to watch" for You; "reviewed" and "watched" do not
  change. The episode rides on a watched series. A listing is present
  tense: the wish stands.
  """
  @spec verb(Activity.kind(), Episode.t() | nil, subject()) :: String.t()
  def verb(kind, episode, subject \\ :friend)
  def verb(:review, _episode, _subject), do: "reviewed"
  def verb(:watched, nil, _subject), do: "watched"

  def verb(:watched, %Episode{season_number: season, episode_number: episode}, _subject),
    do: "watched #{Format.episode_label(season, episode)}"

  def verb(:listing, _episode, :friend), do: "wants to watch"
  def verb(:listing, _episode, :you), do: "want to watch"
```

Update the moduledoc's first sentence to: `the verb ("reviewed", "watched S02E05", "wants to watch" — "want to watch" when You are the subject)`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live/activity_words_test.exs`
Expected: 0 failures (the presence sentence, third person, is untouched).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/discovery_live/activity_words.ex test/media_centaur_web/live/discovery_live/activity_words_test.exs
git commit -m "feat(discovery): the activity verb agrees with its subject

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Task 4: The projection admits own rows and takes a scope

**Files:**
- Modify: `lib/media_centaur_web/components/discovery/feed_entry.ex`
- Modify: `lib/media_centaur_web/live/discovery_live/feed_entries.ex`
- Modify: `test/media_centaur_web/live/discovery_live/feed_entries_test.exs`

- [ ] **Step 1: Rewrite the projection tests for the new contract**

Replace the whole `describe "build/2"` block in `test/media_centaur_web/live/discovery_live/feed_entries_test.exs` with the following, and change the `build/2` helper so `scope: :everyone` is the default:

```elixir
  defp build(rows, opts \\ []) do
    FeedEntries.build(
      rows,
      Keyword.merge([now: @now, window: FeedEntries.page_size(), scope: :everyone], opts)
    )
  end

  describe "build/2" do
    test "keeps every author's reviews and listings; drops watched, former-friend, ignored" do
      %{entries: entries, has_older?: false} =
        build([
          row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo-lists-1"}),
          row("Nick", %{tmdb_id: 2, kind: :review, id: "nick-recs-2"}),
          row("Nick", %{tmdb_id: 3, kind: :watched, id: "nick-watched-3"}),
          row(nil, %{tmdb_id: 4, kind: :review, id: "mine"}, %{own?: true}),
          row(nil, %{tmdb_id: 41, kind: :watched, id: "mine-watched"}, %{own?: true}),
          row(nil, %{tmdb_id: 5, kind: :listing, id: "gone"}, %{own?: false}),
          row("Sam", %{tmdb_id: 6, kind: :review, id: "ignored"}, %{rung: :ignored}),
          row(nil, %{tmdb_id: 7, kind: :review, id: "mine-ignored"}, %{own?: true, rung: :ignored})
        ])

      assert Enum.map(entries, & &1.activity_id) == ["cleo-lists-1", "nick-recs-2", "mine"]
    end

    test "the scope filters by author after the entry rule" do
      rows = [
        row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo", acted_at: ~U[2026-09-01 13:00:00Z]}),
        row(nil, %{tmdb_id: 2, kind: :review, id: "mine", acted_at: ~U[2026-09-01 12:00:00Z]}, %{own?: true}),
        row("Nick", %{tmdb_id: 3, kind: :watched, id: "nick-watched"}),
        row(nil, %{tmdb_id: 4, kind: :listing, id: "mine-listing", acted_at: ~U[2026-09-01 11:00:00Z]}, %{own?: true})
      ]

      ids = fn scope -> build(rows, scope: scope).entries |> Enum.map(& &1.activity_id) end

      assert ids.(:everyone) == ["cleo", "mine", "mine-listing"]
      assert ids.(:friends) == ["cleo"]
      assert ids.(:you) == ["mine", "mine-listing"]
    end

    test "one entry per action, newest first, never grouped" do
      %{entries: entries} =
        build([
          row("Nick", %{tmdb_id: 7, kind: :listing, id: "nick-lists", acted_at: ~U[2026-09-01 12:05:00Z]}),
          row("Nick", %{
            tmdb_id: 7,
            kind: :review,
            id: "nick-recs",
            acted_at: ~U[2026-09-01 12:00:00Z]
          }),
          row("Cleo", %{
            tmdb_id: 7,
            kind: :review,
            id: "cleo-recs",
            acted_at: ~U[2026-09-01 11:00:00Z]
          }),
          row("Sam", %{tmdb_id: 8, kind: :listing, id: "sam-lists", acted_at: ~U[2026-09-01 13:00:00Z]})
        ])

      assert Enum.map(entries, & &1.activity_id) == ["sam-lists", "nick-lists", "nick-recs", "cleo-recs"]
      assert Enum.map(entries, & &1.ref) == [{8, :movie}, {7, :movie}, {7, :movie}, {7, :movie}]
    end

    test "the window bounds the entries and says whether older ones exist" do
      rows = for id <- 1..3, do: row("Nick", %{tmdb_id: id, kind: :listing, id: "act-#{id}"})

      assert %{entries: [_, _], has_older?: true} = build(rows, window: 2)
      assert %{entries: [_, _, _], has_older?: false} = build(rows, window: 3)
      assert %{entries: [_, _, _], has_older?: false} = build(rows, window: 50)
      assert FeedEntries.page_size() == 50
    end

    test "an entry carries what the row shows and the facts the toolbar resolves from" do
      %{entries: [review, own, listing]} =
        build([
          row(
            "Nick",
            %{
              tmdb_id: 9,
              kind: :review,
              id: "nick-recs-9",
              sentiment: :love,
              text: "Saw it twice.",
              acted_at: ~U[2026-09-01 12:00:00Z]
            },
            %{
              poster_url: "/p.jpg",
              rung: :list,
              library_owner_id: "owner",
              acquisition_state: :downloading
            }
          ),
          row(
            nil,
            %{tmdb_id: 11, kind: :listing, id: "mine-11", acted_at: ~U[2026-09-01 11:00:00Z]},
            %{own?: true, rung: :list}
          ),
          row("Cleo", %{
            tmdb_id: 10,
            kind: :listing,
            id: "cleo-lists-10",
            acted_at: ~U[2026-08-31 14:00:00Z]
          })
        ])

      assert %FeedEntry{
               id: "feed-row-nick-recs-9",
               activity_id: "nick-recs-9",
               ref: {9, :movie},
               author: "Nick",
               own?: false,
               kind: :review,
               sentiment: :love,
               text: "Saw it twice.",
               ago: "2h ago",
               poster_url: "/p.jpg",
               rung: :list,
               library_owner_id: "owner",
               acquisition_state: :downloading,
               list_slot: :listed,
               download_slot: {:state, "In library"}
             } = review

      assert review.title.name == "Sample Movie 9"

      assert %FeedEntry{author: "You", own?: true, kind: :listing, list_slot: :listed} = own

      assert %FeedEntry{
               author: "Cleo",
               own?: false,
               kind: :listing,
               sentiment: nil,
               text: nil,
               ago: "1d ago",
               rung: nil,
               list_slot: :list,
               download_slot: :download
             } = listing
    end
  end

  describe "parse_scope/1" do
    test "the URL's word, Everyone for anything else" do
      assert FeedEntries.parse_scope("friends") == :friends
      assert FeedEntries.parse_scope("you") == :you
      assert FeedEntries.parse_scope("everyone") == :everyone
      assert FeedEntries.parse_scope(nil) == :everyone
      assert FeedEntries.parse_scope("nonsense") == :everyone
      assert FeedEntries.scopes() == [:everyone, :friends, :you]
    end
  end

  describe "empty_reason/2" do
    test "You never needs a relay or a friend; the other scopes diagnose readiness first" do
      assert FeedEntries.empty_reason(:you, false) == :nothing_shared
      assert FeedEntries.empty_reason(:you, true) == :nothing_shared
      assert FeedEntries.empty_reason(:everyone, false) == :not_ready
      assert FeedEntries.empty_reason(:friends, false) == :not_ready
      assert FeedEntries.empty_reason(:everyone, true) == :quiet
      assert FeedEntries.empty_reason(:friends, true) == :quiet
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live/feed_entries_test.exs`
Expected: FAIL — `KeyError key :author not found` on the struct match, and undefined `parse_scope/1`, `scopes/0`, `empty_reason/2`.

- [ ] **Step 3: Update the view-model**

In `lib/media_centaur_web/components/discovery/feed_entry.ex`: in `defstruct`, replace `:nickname` with `:author` and add `:own?` after it; in `@type t`, replace `nickname: String.t()` with `author: String.t(), own?: boolean()`. Replace the moduledoc's first paragraph with:

```elixir
  @moduledoc """
  One row on the Feed (UIDR-038, UIDR-045): one author's action on one
  title — a review or a listing — with everything the row shows and
  the two toolbar slots already resolved. `author` is the display name,
  a friend's nickname or "You"; `own?` says which, and decides the
  verb's subject and whether Ignore renders (never on an own row). A
  review's `sentiment` is its verdict or nil, and `text` its words or
  nil; both nil on a listing. A view-model, like `Person`: every fact
  here was resolved by the host (`DiscoveryLive.FeedEntries`), the row
  decides nothing.
```

Keep the second paragraph (the slots) as it is, changing "the card renders it" to "the row renders it". Change the final sentence to: `Where this could be confused with a library entry, say *feed row*.`

- [ ] **Step 4: Update the projection**

Rewrite `lib/media_centaur_web/live/discovery_live/feed_entries.ex`:

```elixir
defmodule MediaCentaurWeb.DiscoveryLive.FeedEntries do
  @moduledoc """
  The Feed's rows from the page's enriched activity rows (ADR-030,
  UIDR-038, UIDR-045): every author's reviews and listings — friends'
  and this identity's own — one row per action, newest first, flat.
  Nothing groups and nothing re-sorts. Watched actions, a former
  friend's actions and any title at the Ignored rung make no row for
  any author; the activities themselves stay for the Friends tab and
  the pennants.

  The scope filters by author after the entry rule: `:everyone`,
  `:friends` (no own rows) or `:you` (own rows only). It is navigation
  state — the page reads it off `?scope=` with `parse_scope/1` — never a
  preference. The window is the newest `window` rows; `has_older?`
  says whether *Show older* has anything to show. The tab's count is
  the window's size under the current scope.

  `empty_reason/2` is the empty state's diagnosis (UIDR-034): the You
  scope needs no relay and no friend, since a review creates its row
  locally; the other scopes ask whether the network is ready first.

  The toolbar's two resolved slots come from the same three facts the
  row markers read — the rung, library presence, the acquisition state —
  with `Logic.acquisition_marker/1` supplying the acquisition words so
  no state is spelled twice.
  """

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Discovery.FeedEntry
  alias MediaCentaurWeb.Components.Title.Logic

  @page_size 50
  @kinds [:review, :listing]
  @scopes [:everyone, :friends, :you]

  @type scope :: :everyone | :friends | :you
  @type empty_reason :: :not_ready | :quiet | :nothing_shared

  @doc "Rows per window — the initial load and each Show older step."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @doc "The scopes in the control's order; Everyone is the default."
  @spec scopes() :: [scope()]
  def scopes, do: @scopes

  @doc "The scope named by the URL's `scope` param; Everyone for anything else."
  @spec parse_scope(String.t() | nil) :: scope()
  def parse_scope("friends"), do: :friends
  def parse_scope("you"), do: :you
  def parse_scope(_other), do: :everyone

  @doc "Why the feed is empty under `scope`, given whether a relay and a friend exist."
  @spec empty_reason(scope(), boolean()) :: empty_reason()
  def empty_reason(:you, _ready?), do: :nothing_shared
  def empty_reason(_scope, false), do: :not_ready
  def empty_reason(_scope, true), do: :quiet

  @doc "The windowed rows under `scope`, newest first. `now` anchors each row's relative time."
  @spec build([map()], now: DateTime.t(), window: pos_integer(), scope: scope()) ::
          %{entries: [FeedEntry.t()], has_older?: boolean()}
  def build(rows, opts) do
    now = Keyword.fetch!(opts, :now)
    window = Keyword.fetch!(opts, :window)
    scope = Keyword.fetch!(opts, :scope)

    entries =
      rows
      |> Enum.filter(&entry?/1)
      |> Enum.filter(&in_scope?(&1, scope))
      |> Enum.sort_by(& &1.activity.acted_at, {:desc, DateTime})

    %{
      entries: entries |> Enum.take(window) |> Enum.map(&entry(&1, now)),
      has_older?: length(entries) > window
    }
  end

  # The entry rule: a review or a listing, by an author on the roster or
  # by this identity, on a title not ignored. Who wrote it is the scope's
  # question, not this one's.
  defp entry?(%{activity: activity, own?: own?, nickname: nickname, rung: rung}),
    do: activity.kind in @kinds and (own? or nickname != nil) and rung != :ignored

  defp in_scope?(_row, :everyone), do: true
  defp in_scope?(%{own?: own?}, :friends), do: not own?
  defp in_scope?(%{own?: own?}, :you), do: own?

  defp entry(%{activity: activity} = row, now) do
    %FeedEntry{
      id: "feed-row-" <> activity.id,
      activity_id: activity.id,
      ref: {activity.tmdb_id, activity.media_type},
      title: activity.title,
      poster_url: row.poster_url,
      author: if(row.own?, do: "You", else: row.nickname),
      own?: row.own?,
      kind: activity.kind,
      sentiment: if(activity.kind == :review, do: activity.sentiment),
      text: if(activity.kind == :review, do: activity.text),
      acted_at: activity.acted_at,
      ago: Format.relative_ago(activity.acted_at, now: now, sub_minute: :just_now),
      rung: row.rung,
      library_owner_id: row.library_owner_id,
      acquisition_state: row.acquisition_state,
      list_slot: list_slot(row),
      download_slot: download_slot(row)
    }
  end

  @doc "What the List position holds: the verb below the list, Listed on it, Following above it."
  @spec list_slot(%{rung: TitleIntent.rung() | nil}) :: FeedEntry.list_slot()
  def list_slot(%{rung: :list}), do: :listed

  def list_slot(%{rung: rung}) do
    if TitleIntent.follows_releases?(rung), do: :following, else: :list
  end

  @doc "What the Download position holds: In library, the acquisition marker while a plan runs, else the verb."
  @spec download_slot(%{library_owner_id: term() | nil, acquisition_state: atom() | nil}) ::
          FeedEntry.download_slot()
  def download_slot(%{library_owner_id: owner}) when not is_nil(owner), do: {:state, "In library"}

  def download_slot(%{acquisition_state: state}) do
    case Logic.acquisition_marker(state) do
      nil -> :download
      word -> {:state, word}
    end
  end
end
```

- [ ] **Step 5: Run the projection tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live/feed_entries_test.exs`
Expected: 0 failures. (`DiscoveryLive` and the story still reference `nickname`; they are rewritten in Tasks 5 and 6. Do not run the full suite yet.)

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/discovery/feed_entry.ex lib/media_centaur_web/live/discovery_live/feed_entries.ex test/media_centaur_web/live/discovery_live/feed_entries_test.exs
git commit -m "feat(discovery): the feed projection admits own rows behind an author scope

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Task 5: The row component and its story

Storybook-first: the story is edited before the component (the `storybook` skill's rule for a component that already has a story). The rename keeps MC0009 satisfied: the story filename must match the component function, `feed_entry_row`.

**Files:**
- Rename: `storybook/discovery/feed_entry_card.story.exs` → `storybook/discovery/feed_entry_row.story.exs`
- Rename: `lib/media_centaur_web/components/discovery/feed_entry_card.ex` → `lib/media_centaur_web/components/discovery/feed_entry_row.ex`
- Modify: `storybook/discovery/_discovery.index.exs`
- Modify: `lib/media_centaur_web/components/title/row.ex:9-10`

- [ ] **Step 1: Rename both files**

```bash
git mv storybook/discovery/feed_entry_card.story.exs storybook/discovery/feed_entry_row.story.exs
git mv lib/media_centaur_web/components/discovery/feed_entry_card.ex lib/media_centaur_web/components/discovery/feed_entry_row.ex
```

- [ ] **Step 2: Rewrite the story with the new contract**

Write `storybook/discovery/feed_entry_row.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Discovery.FeedEntryRow do
  @moduledoc """
  One Feed row (UIDR-038, UIDR-045): poster left, then who did what —
  the sentiment glyph after the verb when the review gives one — the
  title, the review's text when it has some, and the relative time in
  the right column. The toolbar seat is empty at rest and shows on
  hover; the variations cover every state its two resolved slots can
  hold, and the own rows, which say You and carry no Ignore. A listing
  and a review, a friend's and your own, are one row. Rows are meant to
  sit in one inset list surface; the story's template supplies it.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.FeedEntry

  def function, do: &MediaCentaurWeb.Components.Discovery.FeedEntryRow.feed_entry_row/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="glass-inset rounded-xl overflow-hidden">
      <.psb-variation/>
    </div>
    """
  end

  defp entry(id, overrides) do
    tmdb_id = Map.get(overrides, :tmdb_id, 777)

    struct!(
      %FeedEntry{
        id: "feed-row-#{id}",
        activity_id: id,
        ref: {tmdb_id, :movie},
        title: Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie", year: "2024"}),
        poster_url: "/images/sample-nosferatu-poster.jpg",
        author: "Sample Friend",
        own?: false,
        kind: :listing,
        sentiment: nil,
        text: nil,
        acted_at: ~U[2026-09-01 12:00:00Z],
        ago: "12m ago",
        rung: nil,
        library_owner_id: nil,
        acquisition_state: nil,
        list_slot: :list,
        download_slot: :download
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :listing,
        description: "A friend wants to watch it: two lines, centred against the poster, the time on the right.",
        attributes: %{entry: entry("listing", %{})}
      },
      %Variation{
        id: :review_like_with_text,
        description: "Like is the thumbs up after the verb; the text is the third line.",
        attributes: %{
          entry:
            entry("like", %{
              kind: :review,
              sentiment: :like,
              text: "Slow start, give it three episodes.",
              ago: "1d ago"
            })
        }
      },
      %Variation{
        id: :review_love,
        description: "Love is the rose heart after the verb — the only colour on a friend's row.",
        attributes: %{
          entry:
            entry("love", %{
              kind: :review,
              sentiment: :love,
              text: "Saw it twice. The last twenty minutes are the whole film.",
              ago: "2h ago"
            })
        }
      },
      %Variation{
        id: :review_dislike,
        description: "Dislike is the thumbs down after the verb.",
        attributes: %{
          entry:
            entry("dislike", %{
              kind: :review,
              sentiment: :dislike,
              text: "Gave up halfway. Nothing happens, slowly.",
              ago: "3h ago"
            })
        }
      },
      %Variation{
        id: :review_text_only,
        description: "A review with words and no verdict: no glyph, the text still leads the third line.",
        attributes: %{
          entry:
            entry("text-only", %{
              kind: :review,
              sentiment: nil,
              text: "Not sure yet. Ask me after the finale.",
              ago: "5h ago"
            })
        }
      },
      %Variation{
        id: :review_bare,
        description: "A review with neither: the name, the verb and the title, nothing else.",
        attributes: %{
          entry: entry("bare-review", %{kind: :review, sentiment: nil, text: nil, ago: "6h ago"})
        }
      },
      %Variation{
        id: :own_listing,
        description: "Your own listing: You in the primary colour, the verb in the second person, Listed filled, no Ignore.",
        attributes: %{
          entry:
            entry("own-listing", %{author: "You", own?: true, rung: :list, list_slot: :listed, ago: "3d ago"})
        }
      },
      %Variation{
        id: :own_review,
        description: "Your own review: the same row; the toolbar holds List and Download only.",
        attributes: %{
          entry:
            entry("own-review", %{
              author: "You",
              own?: true,
              kind: :review,
              sentiment: :love,
              text: "Saw it twice. The last twenty minutes are the whole film.",
              library_owner_id: "owner",
              download_slot: {:state, "In library"},
              ago: "1h ago"
            })
        }
      },
      %Variation{
        id: :listed_title,
        description: "The title is on your list: the bookmark fills and reads Listed.",
        attributes: %{entry: entry("listed", %{rung: :list, list_slot: :listed})}
      },
      %Variation{
        id: :following_title,
        description: "At Follow or above the List slot is plain state, not a toggle.",
        attributes: %{entry: entry("following", %{rung: :follow, list_slot: :following})}
      },
      %Variation{
        id: :in_library,
        description: "An owned title: the Download slot reads In library.",
        attributes: %{
          entry: entry("owned", %{library_owner_id: "owner", download_slot: {:state, "In library"}})
        }
      },
      %Variation{
        id: :downloading,
        description: "A plan in flight: Downloading with the hairline.",
        attributes: %{
          entry:
            entry("downloading", %{
              acquisition_state: :downloading,
              download_slot: {:state, "Downloading"}
            })
        }
      },
      %Variation{
        id: :no_poster,
        description: "No artwork yet: the poster slot is a quiet tile.",
        attributes: %{entry: entry("bare", %{poster_url: nil, ago: "3w ago"})}
      }
    ]
  end
end
```

In `storybook/discovery/_discovery.index.exs` replace the `feed_entry_card` entry with:

```elixir
  def entry("feed_entry_row"), do: [icon: {:fa, "stream", :thin}, name: "Feed row"]
```

- [ ] **Step 3: Rewrite the component as a row**

Write `lib/media_centaur_web/components/discovery/feed_entry_row.ex`:

```elixir
defmodule MediaCentaurWeb.Components.Discovery.FeedEntryRow do
  @moduledoc """
  One row on the Feed (UIDR-038, UIDR-045), meant for one inset list
  surface the host provides: a hairline below each row, the poster at
  56×84 on the left, to its right three lines at most — who did what
  (`Nick reviewed ♥`, `You want to watch`; the sentiment glyph after
  the verb when the review gives one, nothing when it gives none),
  which title (name and year), and the text when a review has some —
  and the relative time right-aligned in its own column, so the time
  axis reads down the edge. An own row says You in the primary colour
  and takes the second-person verb; nothing else marks it. Nothing
  else is on the body: no pennant, no marker, no synopsis, no avatar;
  the rose heart for Love is the only other colour.

  The toolbar is a fixed 20px seat at the bottom of the text block,
  empty at rest and shown while the row is hovered or holds focus, so
  hover never changes the row's height. Left to right: the List slot
  (the bookmark verb, "Listed" filled, or "Tracking" as plain state),
  the Download slot (the verb, or plain state text — "Downloading" with
  a hairline, "In library"), and Ignore on a friend's row only. State
  and verb are one control. An own row has no Ignore and no Delete:
  withdrawing is the modal's Delete, and the row opens the modal
  speaking for its action.

  Pure rendering of a `FeedEntry`; the row decides nothing. The whole
  row bubbles `open_title` with the ref and the activity; the verbs
  bubble `feed_list`, `feed_download` and `ignore_title` with the
  activity id. A `div[role=button]` because a button may not contain
  controls. Ships mouse-only: no nav items until the hardening pass.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaurWeb.Components.Discovery.FeedEntry
  alias MediaCentaurWeb.Components.Title.Sentiment
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.TitleRef

  @verb_class "inline-flex h-5 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-md px-1.5 hover:bg-base-content/10 hover:text-base-content/90"
  @state_class "inline-flex h-5 items-center whitespace-nowrap px-1.5 text-base-content/60"

  attr :entry, FeedEntry, required: true

  def feed_entry_row(assigns) do
    assigns = assign(assigns, verb_class: @verb_class, state_class: @state_class)

    ~H"""
    <div
      id={@entry.id}
      role="button"
      class="group flex w-full cursor-pointer items-start gap-3.5 border-b border-base-content/5 px-4 py-3 text-left last:border-0 hover:bg-base-content/5 focus-within:bg-base-content/5"
      data-component="feed-row"
      data-kind={@entry.kind}
      data-own={@entry.own?}
      data-list-slot={@entry.list_slot}
      data-download-slot={slot_name(@entry.download_slot)}
      phx-click="open_title"
      phx-value-ref={TitleRef.param(@entry.ref)}
      phx-value-activity={@entry.activity_id}
      data-entity-id={TitleRef.param(@entry.ref)}
    >
      <div class="h-21 w-14 shrink-0 overflow-hidden rounded-md bg-base-content/10">
        <img
          :if={@entry.poster_url}
          src={sized_image_url(@entry.poster_url, 160)}
          alt=""
          class="h-full w-full object-cover"
          loading="eager"
          decoding="sync"
        />
      </div>

      <div class="flex min-h-21 min-w-0 flex-1 flex-col self-stretch">
        <p class="truncate text-[15px] leading-snug text-base-content/70" data-role="who">
          <span class={["font-medium", if(@entry.own?, do: "text-primary", else: "text-base-content/90")]}>
            {@entry.author}
          </span>
          {ActivityWords.verb(@entry.kind, nil, subject(@entry))}
          <Sentiment.sentiment_glyph
            :if={@entry.sentiment}
            sentiment={@entry.sentiment}
            class="size-3.5"
          />
        </p>
        <p class="flex items-baseline gap-2 text-base leading-snug" data-role="title">
          <span class="truncate font-semibold">{@entry.title.name}</span>
          <span :if={@entry.title.year} class="shrink-0 text-xs text-base-content/55">
            {@entry.title.year}
          </span>
        </p>
        <p
          :if={@entry.text}
          class="mb-1 mt-1 line-clamp-4 text-sm leading-normal text-base-content/70"
          data-role="text"
        >
          {@entry.text}
        </p>

        <div
          class="-mx-1.5 mt-auto flex h-5 items-center gap-0.5 text-xs text-base-content/70 opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100"
          data-role="toolbar"
        >
          <button
            :if={@entry.list_slot == :list}
            id={"#{@entry.id}-list"}
            type="button"
            class={@verb_class}
            phx-click="feed_list"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-bookmark" class="size-3.5" /> List
          </button>
          <button
            :if={@entry.list_slot == :listed}
            id={"#{@entry.id}-list"}
            type="button"
            class={[@verb_class, "text-base-content/90"]}
            phx-click="feed_list"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-bookmark-solid" class="size-3.5" /> Listed
          </button>
          <span :if={@entry.list_slot == :following} class={@state_class}>Tracking</span>

          <button
            :if={@entry.download_slot == :download}
            id={"#{@entry.id}-download"}
            type="button"
            class={@verb_class}
            phx-click="feed_download"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-arrow-down-tray" class="size-3.5" /> Download
          </button>
          <span :if={match?({:state, _}, @entry.download_slot)} class={@state_class}>
            <span class={[
              "relative",
              @entry.acquisition_state == :downloading &&
                "after:absolute after:inset-x-0 after:-bottom-[3px] after:h-[3px] after:rounded-sm after:bg-base-content/40"
            ]}>
              {elem(@entry.download_slot, 1)}
            </span>
          </span>

          <button
            :if={not @entry.own?}
            id={"#{@entry.id}-ignore"}
            type="button"
            class={[@verb_class, "ml-auto"]}
            phx-click="ignore_title"
            phx-value-activity={@entry.activity_id}
          >
            Ignore
          </button>
        </div>
      </div>

      <span class="w-16 shrink-0 pt-px text-right text-xs leading-snug text-base-content/55" data-role="time">
        {@entry.ago}
      </span>
    </div>
    """
  end

  defp subject(%FeedEntry{own?: true}), do: :you
  defp subject(%FeedEntry{}), do: :friend

  defp slot_name(:download), do: "download"
  defp slot_name({:state, word}), do: word
end
```

In `lib/media_centaur_web/components/title/row.ex` lines 9–10, change `(The Feed's entries are \`Discovery.FeedEntryCard\`, which carries its own toolbar.)` to `(The Feed's rows are \`Discovery.FeedEntryRow\`, which carries its own toolbar.)`.

- [ ] **Step 4: Point `DiscoveryLive` at the new module so the app compiles**

In `lib/media_centaur_web/live/discovery_live.ex`: change the alias `alias MediaCentaurWeb.Components.Discovery.FeedEntryCard` to `alias MediaCentaurWeb.Components.Discovery.FeedEntryRow`, and the render call `<FeedEntryCard.feed_entry_card :for={entry <- @feed} entry={entry} />` to `<FeedEntryRow.feed_entry_row :for={entry <- @feed} entry={entry} />`. Task 6 rewrites the surrounding template; this step only keeps the build green. The `project/1` call to `FeedEntries.build/2` still lacks `scope:`; add `scope: :everyone` there for now — Task 6 replaces it with the assign.

- [ ] **Step 5: Build the CSS and render the story**

Run: `~/scripts/agents/agent-mix assets.build` (new utilities: `h-21`, `min-h-21`, `w-14`, `text-[15px]`, `w-16`).
Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: 0 failures.
Then Read a render of `http://127.0.0.1:2160/storybook/discovery/feed_entry_row` at 1920×1080 via `page-shot --wait-ms 3000` and confirm: the time sits on the right edge of every row, "You" is blue on the two own rows, the own rows show no Ignore, and a listing's two lines are centred against the poster.

- [ ] **Step 6: Commit**

```bash
git add -A lib/media_centaur_web/components/discovery lib/media_centaur_web/components/title/row.ex lib/media_centaur_web/live/discovery_live.ex storybook/discovery
git commit -m "feat(ui): the Feed entry is a row in one list surface; own rows say You

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Task 6: The page — scope in the URL, the pill, the list, the empty diagnosis, the width

**Files:**
- Modify: `lib/media_centaur_web/live/discovery_live.ex`
- Modify: `test/media_centaur_web/live/discovery_live_test.exs` (the `describe "feed tab"` block)
- Modify: `test/media_centaur_web/page_smoke_test.exs:58`

- [ ] **Step 1: Update the feed test helpers and the tests the anatomy change breaks**

In `test/media_centaur_web/live/discovery_live_test.exs`, inside `describe "feed tab"`:

Replace the two helpers:

```elixir
    defp entry(%{id: id}), do: "#feed-row-#{id}"
    defp entries(view), do: ids(view, "[data-component='feed-row']")
```

In "empty state names the prerequisites, then the quiet empty state", replace the last assertion pair:

```elixir
      {:ok, view, _html} = live(conn, "/discovery")
      assert render(view) =~ "What you and your friends review and want to watch lands here"
      assert render(view) =~ "Each action is one row, newest first."
      refute has_element?(view, "#feed-empty a[href='/settings?section=social']")
```

In "a review entry: name, verb, time, title, year, note; no pennant; opens the modal", replace

```elixir
      assert has_element?(view, entry(rec) <> " [data-role='who']", "2h ago")
```

with

```elixir
      assert has_element?(view, entry(rec) <> " [data-role='time']", "2h ago")
      refute has_element?(view, entry(rec) <> " [data-role='who']", "ago")
```

In "one entry per action, newest first: two friends on a title, one friend twice", change the four expected ids from `"feed-entry-#{…}"` to `"feed-row-#{…}"` and the pennant refutation to `refute has_element?(view, "[data-component='feed-row'] .pennant")`.

Replace the test "watched actions, own actions and a former friend's actions never make an entry" with:

```elixir
    test "watched and a former friend's actions never make a row; own reviews and listings do", %{
      conn: conn
    } do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _other} = Social.add_friend(@other_pubkey, "Other Friend")
      show = Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"})
      episode = %Episode{season_number: 2, episode_number: 5, name: "The Fifth"}

      {:ok, _watched} =
        Activities.ingest(
          Event.sign(
            Translation.to_event(:watched, show, [episode: episode], @friend_pubkey),
            @friend_secret
          )
        )

      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, mine} = Activities.review(title, :like, "mine")
      {:ok, own_listing} = Activities.listing(title)
      {:ok, _own_watched} = Activities.watched(title, nil)

      {:ok, _former} = Activities.ingest(other_event(778, :love))
      :ok = Social.remove_friend(@other_pubkey)

      {:ok, view, _html} = live(conn, "/discovery")
      # Both own acts land in the same second; their order is not this test's claim.
      assert Enum.sort(entries(view)) == Enum.sort(["feed-row-#{own_listing.id}", "feed-row-#{mine.id}"])
      assert has_element?(view, feed_badge(), "2")

      {:ok, view, _html} = live(conn, "/discovery?scope=friends")
      assert entries(view) == []
      refute has_element?(view, "[data-nav-zone='zone-tabs'] a[href='/discovery?scope=friends'] .badge")
      assert render(view) =~ "What your friends review and want to watch lands here"

      await_supervised_tasks()
    end
```

- [ ] **Step 2: Add the scope and own-row tests**

Append inside `describe "feed tab"`:

```elixir
    test "the scope filters by author, lives in the URL, and survives the modal", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      # A minute older than your review, so the order between them is fixed.
      {:ok, theirs} = Activities.ingest(friend_event(777, "Watch it.", :like, System.os_time(:second) - 60))
      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, mine} = Activities.review(title, :love, "Saw it twice.")

      {:ok, view, _html} = live(conn, "/discovery")
      assert entries(view) == ["feed-row-#{mine.id}", "feed-row-#{theirs.id}"]
      assert has_element?(view, "#feed-scope [phx-value-choice='everyone'][aria-pressed='true']")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a[href='/discovery']", "Feed")

      view |> element("#feed-scope [phx-value-choice='you']") |> render_click()
      assert_patch(view, "/discovery?scope=you")
      assert entries(view) == ["feed-row-#{mine.id}"]
      assert has_element?(view, "#feed-scope [phx-value-choice='you'][aria-pressed='true']")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a[href='/discovery?scope=you'] .badge", "1")

      # Opening and closing the modal keeps the scope in the address.
      view |> element(entry(mine)) |> render_click()
      path = assert_patch(view)
      assert path =~ "scope=you"
      assert path =~ "title=movie-999"
      assert has_element?(view, "#detail-activity-delete", "Delete review")
      render_hook(view, "close_title", %{})
      assert_patch(view, "/discovery?scope=you")

      view |> element("#feed-scope [phx-value-choice='friends']") |> render_click()
      assert_patch(view, "/discovery?scope=friends")
      assert entries(view) == ["feed-row-#{theirs.id}"]

      # A refresh keeps it; a word the URL does not offer falls back to Everyone.
      {:ok, view, _html} = live(conn, "/discovery?scope=friends")
      assert entries(view) == ["feed-row-#{theirs.id}"]
      {:ok, view, _html} = live(conn, "/discovery?scope=nonsense")
      assert has_element?(view, "#feed-scope [phx-value-choice='everyone'][aria-pressed='true']")

      await_supervised_tasks()
    end

    test "an own row: You in the second person, no Ignore, no Delete; a friend's row keeps Ignore", %{
      conn: conn
    } do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, theirs} = Activities.ingest(friend_listing_event(777))
      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, mine} = Activities.listing(title)
      {:ok, review} = Activities.review(title, :dislike, nil)

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, entry(mine) <> "[data-own] [data-role='who']", "You want to watch")
      assert has_element?(view, entry(review) <> "[data-own] [data-role='who']", "You reviewed")
      assert has_element?(view, entry(review) <> " [data-role='who'] [data-sentiment='dislike']")
      assert has_element?(view, entry(theirs) <> ":not([data-own]) [data-role='who']", "Sample Friend wants to watch")

      assert has_element?(view, entry(mine) <> "-list")
      assert has_element?(view, entry(mine) <> "-download")
      refute has_element?(view, entry(mine) <> "-ignore")
      refute has_element?(view, entry(mine) <> " [data-role='toolbar']", "Delete")
      assert has_element?(view, entry(theirs) <> "-ignore")

      await_supervised_tasks()
    end

    test "Listed on your own listing drops the title off your list, which withdraws the listing", %{
      conn: conn
    } do
      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, _} = list(title, :list)
      {:ok, mine} = Activities.listing(title)

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, entry(mine) <> "[data-list-slot='listed']")

      view |> element(entry(mine) <> "-list") |> render_click()
      refute Discovery.listed?(999, :movie)
      render_until(view, fn _html -> not has_element?(view, entry(mine)) end)
      assert Activities.list_sent() == []

      await_supervised_tasks()
    end

    test "the You scope's empty state speaks of sharing and needs no relay or friend", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery?scope=you")

      assert render(view) =~ "What you review and list lands here"
      assert render(view) =~ "A title you list is shared while Share your watchlist is on."
      assert has_element?(view, "#feed-empty a[href='/settings?section=social']", "Settings → Social")
      refute has_element?(view, "#feed-empty a[href='/discovery/friends']")
      refute render(view) =~ "Media Centaur reaches your friends over a relay"
    end
```

Note on the Listed test: `Activities.Publisher` withdraws a listing when the rung drops below List whether or not *Share your watchlist* is on (`docs/social.md` § Event shape, ADR-067), so the row leaves through the normal `activity_deleted` broadcast. If the row does not leave within the second `render_until` allows, read `lib/media_centaur/activities/publisher.ex` for the `RungChanged` handling before touching the test.

- [ ] **Step 3: Add the scoped routes to the smoke test**

In `test/media_centaur_web/page_smoke_test.exs` line 58, after `{"/discovery", "discovery feed"},` add:

```elixir
          {"/discovery?scope=friends", "discovery feed, friends scope"},
          {"/discovery?scope=you", "discovery feed, you scope"},
```

- [ ] **Step 4: Run the feed tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: failures on `#feed-scope` (no such element), the own rows, the empty copy and the `?scope=` routes. The Library/People tests in the file still pass.

- [ ] **Step 5: Wire the page**

In `lib/media_centaur_web/live/discovery_live.ex`:

(a) `mount/3` — add three assigns to the `assign(` list, after `feed_window:`:

```elixir
       feed_scope: :everyone,
       feed_ready?: false,
       feed_empty_reason: :not_ready,
```

(b) `handle_params/3` — replace the no-op with:

```elixir
  # The scope is navigation state (UIDR-045): read off the URL, so a
  # refresh, the sidebar's URL memory and the Feed tab's link all return
  # to it. Re-projecting is pure; the rows were loaded on mount.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:feed_scope, FeedEntries.parse_scope(params["scope"]))
     |> project()}
  end
```

(c) the pill's event — add beside `feed_show_older`:

```elixir
  # The pill patches the address; handle_params does the rest.
  def handle_event("feed_scope", %{"choice" => choice}, socket),
    do: {:noreply, push_patch(socket, to: feed_path(FeedEntries.parse_scope(choice)))}
```

(d) `project/1` — pass the scope and diagnose the empty state:

```elixir
  defp project(socket) do
    now = DateTime.utc_now()

    %{entries: entries, has_older?: has_older?} =
      FeedEntries.build(socket.assigns.activities,
        now: now,
        window: socket.assigns.feed_window,
        scope: socket.assigns.feed_scope
      )

    assign(socket,
      feed: entries,
      feed_has_older?: has_older?,
      feed_empty_reason:
        FeedEntries.empty_reason(socket.assigns.feed_scope, socket.assigns.feed_ready?),
      people:
        People.build(socket.assigns.activities, socket.assigns.friends,
          me: Identity.pubkey() != nil,
          now: now
        )
    )
  end
```

(e) tabs and paths — replace the contiguous region from `defp tabs(feed, items, friends)` through the end of `discovery_path/2` (it includes `feed_empty_state/1` and `current_path/1`) with:

```elixir
  defp tabs(feed, items, friends, scope),
    do: [
      %Tab{id: :feed, label: "Feed", navigate: feed_path(scope), count: length(feed)},
      %Tab{id: :watchlist, label: "Watchlist", navigate: "/discovery/watchlist", count: length(items)},
      %Tab{id: :friends, label: "Friends", navigate: "/discovery/friends", count: length(friends)}
    ]

  # The Feed under a scope, Everyone being the bare address.
  defp feed_path(:everyone), do: "/discovery"
  defp feed_path(scope), do: "/discovery?scope=#{scope}"

  # The empty state's words per diagnosis (UIDR-034): before a relay and a
  # friend exist nothing can arrive, so the copy names what is missing;
  # the You scope needs neither, so its copy is about sharing.
  defp feed_empty_headline(:everyone, :quiet),
    do: "What you and your friends review and want to watch lands here"

  defp feed_empty_headline(_scope, :nothing_shared), do: "What you review and list lands here"
  defp feed_empty_headline(_scope, _reason), do: "What your friends review and want to watch lands here"

  defp feed_empty_body(:not_ready),
    do:
      "Media Centaur reaches your friends over a relay. Add one, then add a friend by the public key they give you."

  defp feed_empty_body(:quiet), do: "Each action is one row, newest first."

  defp feed_empty_body(:nothing_shared),
    do: "A review is always shared. A title you list is shared while Share your watchlist is on."

  defp current_path(:friends), do: "/discovery/friends"
  defp current_path(:watchlist), do: "/discovery/watchlist"
  defp current_path(_action), do: "/discovery"

  # Path back to the current tab; every modal open/close patch routes
  # through this so leaving the modal never dumps the user on another
  # tab, and the Feed's scope rides along so closing the modal lands on
  # the same scope.
  defp discovery_path(socket, params) do
    base = current_path(socket.assigns.live_action)

    case params |> Keyword.merge(scope_params(socket.assigns)) |> URI.encode_query() do
      "" -> base
      query -> base <> "?" <> query
    end
  end

  # The host hands a keyword list (`title_detail_path/2`'s contract) and
  # merging appends, so the modal's own params keep their order. Every
  # caller passes a keyword list; convert at the call site if one ever
  # passes a map.
  defp scope_params(%{live_action: :feed, feed_scope: scope}) when scope != :everyone,
    do: [scope: Atom.to_string(scope)]

  defp scope_params(_assigns), do: []
```

(f) the template — replace from `<div class="mx-auto w-full max-w-3xl space-y-4 pt-10">` through the end of the `:if={@live_action == :feed}` block (up to and including the `Show older` div's closing `</div>`) with:

```heex
        <div class="mx-auto w-full max-w-4xl space-y-4 pt-10">
          <.page_header title="Discovery" class="px-1" />

          <div class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
            <.tab_strip tabs={tabs(@feed, @items, @friends, @feed_scope)} active={@live_action} />
            <.segmented_control
              :if={@live_action == :feed}
              id="feed-scope"
              label="Scope"
              options={[{:everyone, "Everyone"}, {:friends, "Friends"}, {:you, "You"}]}
              selected={@feed_scope}
              event="feed_scope"
              nav={false}
            />
          </div>

          <div :if={@live_action == :feed} class="space-y-2">
            <.empty_state
              :if={@feed == []}
              id="feed-empty"
              icon="hero-users"
              headline={feed_empty_headline(@feed_scope, @feed_empty_reason)}
            >
              {feed_empty_body(@feed_empty_reason)}
              <:action :if={@feed_empty_reason == :not_ready}>
                <.button
                  variant="primary"
                  size="sm"
                  navigate={~p"/settings?section=social"}
                  data-nav-item
                  tabindex="0"
                >
                  Add a relay
                </.button>
              </:action>
              <:action :if={@feed_empty_reason == :not_ready}>
                <.button
                  variant="dismiss"
                  size="sm"
                  navigate={~p"/discovery/friends"}
                  data-nav-item
                  tabindex="0"
                >
                  Add a friend
                </.button>
              </:action>
              <:action :if={@feed_empty_reason == :nothing_shared}>
                <.button
                  variant="dismiss"
                  size="sm"
                  navigate={~p"/settings?section=social"}
                  data-nav-item
                  tabindex="0"
                >
                  Settings → Social
                </.button>
              </:action>
            </.empty_state>

            <div :if={@feed != []} id="feed-list" class="glass-inset overflow-hidden rounded-xl">
              <FeedEntryRow.feed_entry_row :for={entry <- @feed} entry={entry} />
            </div>

            <div :if={@feed_has_older?} class="flex justify-center pt-3">
              <.button id="feed-show-older" variant="dismiss" size="sm" phx-click="feed_show_older">
                Show older
              </.button>
            </div>
          </div>
```

(g) the moduledoc — replace the Feed paragraph with:

```elixir
  Feed (`/discovery`, the page's default; UIDR-038, UIDR-045) — every
  author's reviews and listings, friends' and your own, one row per
  action, newest first, flat (`FeedEntries`), in one list surface; the
  newest `feed_window` of them and a *Show older* control past that
  (`feed_show_older`). The scope — Everyone, Friends, You — is the
  `?scope=` param, read in `handle_params`, patched by the pill
  (`feed_scope`) and carried by the Feed tab's link and every modal
  path, so it survives a refresh, the sidebar and the modal. A row's
  toolbar holds the verbs that live outside the modal: `feed_list` (the
  bottom rung as a toggle — List, Listed, or Following as plain state),
  `feed_download` (the one-click plan, the modal's plain Download) and,
  on a friend's row, `ignore_title` (the Ignored rung, with the Undo
  toast). An own row has neither Ignore nor Delete: it opens the modal
  speaking for its action, where Delete lives. Friends
```

and keep the rest of the paragraph from `(\`/discovery/friends\`) — one \`Person\` card` onward.

(h) the comment above `activity_row/3` — change `Never an own act unless named — the You card names it;` to `Never an own act unless named — the You card and an own feed row name it;`.

- [ ] **Step 6: Run the feed tests, then the smoke test**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: 0 failures.

- [ ] **Step 7: Look at it**

Run `~/scripts/agents/agent-mix assets.build` if any utility in the template is new (`max-w-4xl`, `gap-x-6`, `gap-y-3` are likely already in the bundle; build anyway), then:

```bash
~/scripts/agents/page-shot --url http://127.0.0.1:2160/discovery --viewport 1920x1080 --wait-ms 3000
~/scripts/agents/page-shot --url "http://127.0.0.1:2160/discovery?scope=you" --viewport 1920x1080 --wait-ms 3000
```

Read both PNGs. Expected: the pill sits at the right of the tab line with the chosen option lifted; the rows sit in one inset surface with hairlines; the times line up on the right; the dev database's own review (if any) reads "You reviewed" in blue. Check the Watchlist and Friends tabs once each at the wider column for anything that broke its line.

- [ ] **Step 8: Commit**

```bash
git add lib/media_centaur_web/live/discovery_live.ex test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/page_smoke_test.exs
git commit -m "feat(discovery): own actions in the Feed under an Everyone / Friends / You scope (UIDR-045)

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

---

### Task 7: Docs, glossary, skill table, wiki

**Files:**
- Modify: `docs/social.md:280-292` (Web layer, the Feed bullet)
- Modify: `docs/GLOSSARY.md` (lines 21, 65, 185, 187 as of today; grep the terms)
- Modify: `.claude/skills/user-interface/SKILL.md` (the UIDR table, after row 044 if present, else after 043)
- Modify: `../media-centaur.wiki/Social.md` (§ Feed, § Friends "Your card", the intro line)

- [ ] **Step 1: `docs/social.md` — the Feed bullet in § Web layer**

Replace the `**Feed**` bullet with:

```markdown
- **Feed** — `DiscoveryLive.FeedEntries`: every author's reviews and
  listings, friends' and this identity's own, one
  `Components.Discovery.FeedEntry` per action, newest first, flat,
  windowed (50, then *Show older*), filtered by the `?scope=` param
  (Everyone, Friends, You — `parse_scope/1`; UIDR-045). Watched, former
  friends' and ignored-title rows make no row for any author.
  `FeedEntryRow` renders one row for the page's one inset list surface,
  with its hover toolbar — `feed_list` (the bottom rung as a toggle;
  Following as plain state), `feed_download` (the modal's plain
  Download, same `Plans.plan_title/2` and flash) and, on a friend's row,
  `ignore_title` (with the Undo toast); an own row has no Ignore and no
  Delete — it opens the modal for its action, where Delete lives.
  Friend provenance for a listing or an ignore is
  `TitleIntent.friend_provenance/2`, the same spelling the modal uses.
```

Also in that section, change "What friends did with a title … is one component everywhere but the Feed, the pennant" — leave as is; it is still true. In the sentence "A feed entry flies none: each friend's action is its own entry there." change to "A feed row flies none: each action is its own row there."

- [ ] **Step 2: `docs/GLOSSARY.md`**

Change the **Entry** row's parenthetical `\`Discovery.FeedEntry\` — say *feed entry* where the Feed's unit could be mistaken for a library entry` to `\`Discovery.FeedEntry\` — say *feed row* where the Feed's unit could be mistaken for a library entry`.

In the **Ignored** row, change "Set by a feed entry's Ignore" to "Set by a friend's feed row's Ignore".

Replace the **Action** row's second sentence with: `Two kinds reach the Feed — a review and a listing — by any author, a friend or you.`

Replace the **Feed** (tab) row with:

```markdown
| **Feed** (tab) | The Discovery tab at `/discovery`, the page's default (UIDR-038, UIDR-045): every author's reviews and listings, friends' and your own, one **feed row** per action, newest first, flat, in one inset list surface, the newest window of 50 then *Show older* (`DiscoveryLive.FeedEntries`, `Components.Discovery.FeedEntry`, `FeedEntryRow`). A row shows the author — a friend's nickname or **You**, in the primary colour — the action with the sentiment glyph when a review gives one (UIDR-040), the title, the review text when there is any, and the relative time in a right-hand column; no pennant, no markers. Its hover toolbar holds List and Download, and Ignore on a friend's row. Watched actions and former friends' actions never appear. The **scope** — Everyone, Friends, You — filters by author and is the `?scope=` param, never a preference. |
```

Add two rows after it:

```markdown
| **Scope** (Feed) | The author filter on the Feed: **Everyone** (default), **Friends**, **You** — `FeedEntries.scopes/0`, read off `?scope=` by `parse_scope/1`, chosen on the segmented control at the right of the tab strip's line. Navigation state: a refresh, the sidebar's URL memory and the Feed tab's link all return to it. Not a tab and not a setting. |
| **Author** (Feed) | Who made an action, the word a feed row leads with: a friend's nickname, or **You** for this identity's own broadcasts. An own row takes the second-person verb ("You want to watch"); a friend's the third ("Cleo wants to watch"). |
```

- [ ] **Step 3: `.claude/skills/user-interface/SKILL.md`**

In the UIDR table add, after the last row:

```markdown
| 045 | Own actions join the Feed under an author scope; the segmented control is one component |
```

In the Component Inventory table, after the `tab_strip/1` row, add:

```markdown
| `segmented_control/1` | `core_components.ex` | The house pick-one pill for content surfaces (Feed scope, Library type tabs, strip chart window); `settings_choice/1` composes it | ✅ |
```

In § Library Toolbar, change the Type tabs bullet to: `**Type tabs:** \`segmented_control/1\` — the house pick-one pill (glass container, the chosen option lifted, \`aria-pressed\`); the same component renders the Feed's scope and the strip chart's window. A title's tracking controls are not a pill: …` keeping the rest of the sentence.

- [ ] **Step 4: The wiki's Social page**

In `../media-centaur.wiki/Social.md`:

In the intro paragraph change `the **Feed** (what your friends review and want to watch)` to `the **Feed** (what you and your friends review and want to watch)`.

Replace § Feed's first paragraph with:

```markdown
**Discovery → Feed** is what you and your friends did, newest first: every review and every listing, one row each. Two friends reviewing one title are two rows; a friend reviewing a title and then listing it is two rows; your own review sits among them. Nothing is grouped and nothing moves once it has landed. The tab's count is the number of rows shown.

The pill at the right of the tabs picks whose rows you see:

| Scope | Shows |
|---|---|
| **Everyone** | Every review and listing, yours and your friends', in one timeline. The default. |
| **Friends** | Your friends' only. |
| **You** | Your own only — what you have broadcast. A review is always shared; a listing only while [Share your watchlist](#sharing-what-you-watch-and-list) is on. |

The choice stays in the address, so coming back to Discovery returns to it.
```

In the "An entry shows" table, rename the heading sentence to `A row shows:` and change the three rows to:

```markdown
| Line | Content |
|---|---|
| First | Who — the friend's name, or **You** — and what they did: *reviewed*, with a thumbs down, a thumbs up or a heart after it when the review gives a verdict and nothing when it does not, or *wants to watch* (*want to watch* on your own row). |
| Second | The title and its year, beside the poster. |
| Third | The words, on a review that has any. Long reviews are cut at four lines; the title view has the whole text. |
| Right edge | How long ago. |
```

Change `Hover an entry for its toolbar:` to `Hover a row for its toolbar:` and add a line after the toolbar table:

```markdown
Your own rows carry **List** and **Download** only. To withdraw one of your own reviews or listings, open the row and use **Delete review** / **Delete listing** in the title view (see [Friends](#friends)); turning **Listed** off on your own listing withdraws it too.
```

Change `Click anywhere else on the entry to open the title view` to `Click anywhere else on the row to open the title view`, `Past the newest fifty entries` to `Past the newest fifty rows`, and replace the last paragraph of § Feed with:

```markdown
Not on the Feed: what anyone watches (the Friends tab has it), and activity from someone you removed. Under **Everyone** and **Friends**, until you have a relay and a friend, the tab explains what is missing and offers both steps; under **You** it says what will land there once you review or list a title.
```

In § Friends, the "Your card" paragraph: change `Opening one of your own titles adds **Delete review**` to `Opening one of your own titles here, or one of your own rows on the Feed, adds **Delete review**`.

- [ ] **Step 5: Commit both repositories**

```bash
git add docs/social.md docs/GLOSSARY.md .claude/skills/user-interface/SKILL.md
git commit -m "docs: the Feed's scope, author and row in the contributor docs and glossary

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
cd ../media-centaur.wiki && git add Social.md && git commit -m "wiki: Feed shows your own rows behind an Everyone / Friends / You scope" && cd ../media-centaur-app
```

Do not push either repository; the owner pushes.

---

### Task 8: Precommit and the closing check

- [ ] **Step 1: Run the whole gate in the foreground**

Run: `~/scripts/agents/agent-mix precommit` with a 600000 ms timeout (never in the background: a background shell is killed at the end of the turn).
Expected: format clean, Credo clean (MC0009 finds `feed_entry_row.story.exs`; MC0024 sees no `phx-`/`data-` literals in `=~` assertions; MC0034 sees no text under /55), boundaries clean, 0 test failures, 0 warnings.

If the formatter rewrites a file, stage and amend the last commit (nothing is pushed). If Credo reports the segmented control's `phx-value-choice` under MC0021, that is a false hit only for the literal `value` key; the component never emits it.

- [ ] **Step 2: Run the feed tests three times for flakes**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs --repeat-until-failure 3`
Expected: 3 clean runs. A failure in the Listed-withdraws test points at the Publisher's async path; fix the seam (a `render_until` on the right predicate), never a sleep.

- [ ] **Step 3: Update the spec's status line and finish**

In `docs/superpowers/specs/2026-09-24-feed-timeline-scope-design.md`, change `**Status:** designed; implementation plan to follow (UIDR-045)` to `**Status:** implemented 2026-09-24 (UIDR-045); plan in \`../plans/2026-09-24-feed-timeline-scope.md\``.

```bash
git add docs/superpowers/specs/2026-09-24-feed-timeline-scope-design.md
git commit -m "docs: mark the Feed timeline scope design implemented

Claude-Session: https://claude.ai/code/session_01JY93FNevijFHrkNdKdSw5L"
```

Report to the owner: what shipped, the three visual checks made (feed, You scope, Watchlist/Friends at the wider column), and the one item deferred by the spec that needs an eye in the browser — the Friends card's Recently watched tiles at the wider column, and whether the 240px derivative still reads well at 2× scale.
