# Choose Episodes Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A series' scope select gains a third value, "Choose episodes", which sends Download to the existing picker on Incoming with the click's planning mode; the picker's own Download then performs that mode.

**Architecture:** The picker and its logic already exist (`PlanModal` targeting stage, `IncomingLive.PlanLogic`). This change adds one module that builds and parses the plan modal's URL query (`IncomingLive.PlanQuery`), one wire-form parser for the planning mode (`PlanningMode.parse_mode/1`), generalises the host's board hand-off callback to `open_plan/2`, and teaches Incoming to read a `mode` param and stamp the plan's approval policy from it. The select's value becomes a named type on `ModalState`; `DownloadScope` stays a rule resolver.

**Tech Stack:** Elixir, Phoenix LiveView, ExUnit (`MediaCentaur.Case` / `DataCase` / `ConnCase`), Phoenix Storybook, Req.Test stubs.

**Spec:** `docs/superpowers/specs/2026-09-23-choose-episodes-scope-design.md`. Decision numbers below refer to it.

**Repo rules that apply to every task:**
- Never run `mix` directly. Run `~/scripts/agents/agent-mix <task>` (it uses an isolated build root so the dev server is not disturbed).
- Test first: write the test, run it and see it fail, then implement.
- Zero warnings. An unused alias or import fails `mix precommit`.
- Commit each task on `main` with a conventional message. Do not push.
- No real show titles in tests or docs: use `Sample Show`, `Sample Movie`.

---

## File map

| File | Responsibility |
|---|---|
| `lib/media_centaur/settings/preferences/planning_mode.ex` | Modify: `parse_mode/1`, the mode's one wire-form parser; `parse/1` delegates to it. |
| `test/media_centaur/settings/preferences/planning_mode_test.exs` | Modify: `parse_mode/1` tests. |
| `lib/media_centaur_web/live/incoming_live/plan_query.ex` | Create: the plan modal's address — build (`board/1`, `picker/3`, `path/1`) and parse (`parse/1`). |
| `test/media_centaur_web/live/incoming_live/plan_query_test.exs` | Create: pure tests for the module above. |
| `lib/media_centaur_web/live/title_detail_host.ex` | Modify: callback `open_plan/2` replaces `open_plan_board/2`; the Download event resolves its mode through `parse_mode/1` and its scope through `ModalState.parse_scope_choice/1`; `land_download` hands off through `PlanQuery.board/1`. |
| `lib/media_centaur_web/live/title_detail_host/acquisition.ex` | Modify: `start_download/4` with `:choose_episodes` opens the picker; the missing-episode landing uses `open_plan/2`. |
| `lib/media_centaur_web/live/{home,discovery,library,incoming}_live.ex` | Modify: the `open_plan/2` implementation. |
| `lib/media_centaur_web/components/detail/season_list.ex` | Modify: the "Download more of this show" link is built by `PlanQuery`. |
| `lib/media_centaur_web/live/incoming_live.ex` | Modify: params parsed by `PlanQuery.parse/1`; `plan_mode` assign; `plan_create` stamps the approval policy from it and ends per mode; `resume_plan` and `plan_create` hand off through `open_plan/2`. |
| `lib/media_centaur_web/components/title/modal_state.ex` | Modify: `scope_choice/0` type, `scope_choices/0`, `parse_scope_choice/1`. |
| `lib/media_centaur_web/components/title/logic.ex` | Modify: `download_scope_label/1` names the third value. |
| `lib/media_centaur_web/components/detail_panel.ex` | Modify: the scope select lists `ModalState.scope_choices/0`. |
| `storybook/detail_panel/detail_panel.story.exs` | Modify: a variation with Choose episodes selected. |
| `lib/media_centaur_web/live/plan_flow.ex` | Modify: `land_plan/5`, the one ending for a plan a surface has just created; moduledoc names the surfaces that exist. |
| `docs/GLOSSARY.md`, two specs, three wiki pages | Modify: documentation (Task 6). |
| Tests: `discovery_live_test.exs`, `incoming_live_test.exs`, `modal_state_test.exs`, `logic_test.exs` | Modify: behaviour tests per task. |

---

### Task 1: `PlanningMode.parse_mode/1` — one parser for the mode's wire form

The two mode strings are mapped by hand in the host's Download event and again in `PlanningMode.parse/1`. The URL param (Task 4) would be a third copy. Put the mapping in one function and make both existing sites use it (coherence pass, 3).

**Files:**
- Modify: `lib/media_centaur/settings/preferences/planning_mode.ex`
- Modify: `lib/media_centaur_web/live/title_detail_host.ex` (the `"download"` event, around line 851)
- Test: `test/media_centaur/settings/preferences/planning_mode_test.exs`

- [x] **Step 1: Write the failing tests**

Add this `describe` to `test/media_centaur/settings/preferences/planning_mode_test.exs`, after the `describe "approval_policy/1"` block:

```elixir
  describe "parse_mode/1 — the wire form" do
    test "reads both mode strings" do
      assert PlanningMode.parse_mode("auto_select_best_release") == {:ok, :auto_select_best_release}
      assert PlanningMode.parse_mode("manually_select_release") == {:ok, :manually_select_release}
    end

    test "anything else is :error, never the default" do
      assert PlanningMode.parse_mode("grab_everything") == :error
      assert PlanningMode.parse_mode(nil) == :error
      assert PlanningMode.parse_mode(:auto_select_best_release) == :error
    end
  end
```

- [x] **Step 2: Run the test file and watch it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/settings/preferences/planning_mode_test.exs`
Expected: 2 failures, `UndefinedFunctionError` for `PlanningMode.parse_mode/1`.

- [x] **Step 3: Implement `parse_mode/1` and make `parse/1` delegate**

In `lib/media_centaur/settings/preferences/planning_mode.ex`, replace the `parse/1` clauses (the three lines under `@doc "Parses a stored value; …"`) with:

```elixir
  @doc """
  Parses the mode's wire form — the string a Download event's `mode`
  value or a plan link's `mode` param carries. `:error` for anything
  else; each caller decides what an absent or unknown value means (the
  Download button: the title's default; a plan link: the person's
  default, or a malformed link).
  """
  @spec parse_mode(term()) :: {:ok, mode()} | :error
  def parse_mode("auto_select_best_release"), do: {:ok, :auto_select_best_release}
  def parse_mode("manually_select_release"), do: {:ok, :manually_select_release}
  def parse_mode(_other), do: :error

  @doc "Parses a stored value; anything but a known mode string is the default."
  @spec parse(term()) :: mode()
  def parse(%{"mode" => mode}) do
    case parse_mode(mode) do
      {:ok, mode} -> mode
      :error -> @default
    end
  end

  def parse(_value), do: @default
```

- [x] **Step 4: Make the host's Download event use it**

In `lib/media_centaur_web/live/title_detail_host.ex`, in `handle_title_event("download", params, …)`, replace

```elixir
    mode =
      case params do
        %{"mode" => "auto_select_best_release"} -> :auto_select_best_release
        %{"mode" => "manually_select_release"} -> :manually_select_release
        _default -> detail.planning_mode
      end
```

with

```elixir
    mode =
      case PlanningMode.parse_mode(params["mode"]) do
        {:ok, mode} -> mode
        :error -> detail.planning_mode
      end
```

`PlanningMode` is already aliased in that module (line 90).

In `planning_mode.ex`'s moduledoc, after the paragraph ending "so a bad row can never turn on unattended commits.", add:

```
  The mode also travels on the wire — a Download event's `mode` value, a
  plan link's `mode` param — as the same two strings; `parse_mode/1` is
  their one parser.
```

- [x] **Step 5: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/settings/preferences/planning_mode_test.exs test/media_centaur_web/live/discovery_live_test.exs`
Expected: all pass (the Discovery tests cover the Download event's mode handling: "the menu names the other mode and performs it").

- [x] **Step 6: Commit**

```bash
git add lib/media_centaur/settings/preferences/planning_mode.ex lib/media_centaur_web/live/title_detail_host.ex test/media_centaur/settings/preferences/planning_mode_test.exs
git commit -m "refactor(settings): one parser for the planning mode's wire form"
```

---

### Task 2: `IncomingLive.PlanQuery` — the plan modal's address, built and parsed once

**Files:**
- Create: `lib/media_centaur_web/live/incoming_live/plan_query.ex`
- Test: `test/media_centaur_web/live/incoming_live/plan_query_test.exs`

- [x] **Step 1: Write the failing tests**

Create `test/media_centaur_web/live/incoming_live/plan_query_test.exs`:

```elixir
defmodule MediaCentaurWeb.IncomingLive.PlanQueryTest do
  @moduledoc """
  The plan modal's address: two shapes (the board, the picker), built and
  parsed by one module so every link, patch and navigate agrees on them.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.IncomingLive.PlanQuery

  describe "board/1 and picker/3 — the two shapes" do
    test "the board is the plan id alone" do
      assert PlanQuery.board("abc") == %{"plan" => "abc"}
    end

    test "the picker names the title, the id as a string" do
      assert PlanQuery.picker(246_810, "tv") ==
               %{"plan" => "new", "tmdb_id" => "246810", "tmdb_type" => "tv"}
    end

    test "the picker carries a mode only when given one" do
      assert PlanQuery.picker("550", "movie", :auto_select_best_release) ==
               %{
                 "plan" => "new",
                 "tmdb_id" => "550",
                 "tmdb_type" => "movie",
                 "mode" => "auto_select_best_release"
               }

      refute Map.has_key?(PlanQuery.picker("550", "movie", nil), "mode")
    end

    test "the picker refuses a type Incoming cannot target" do
      assert_raise FunctionClauseError, fn -> PlanQuery.picker("1", "book") end
    end
  end

  describe "path/1 — a query as a path to Incoming" do
    test "renders the board" do
      assert PlanQuery.path(PlanQuery.board("abc")) == "/incoming?plan=abc"
    end

    test "renders the picker with every param" do
      "/incoming?" <> query = PlanQuery.path(PlanQuery.picker("246810", "tv", :manually_select_release))

      assert URI.decode_query(query) == %{
               "plan" => "new",
               "tmdb_id" => "246810",
               "tmdb_type" => "tv",
               "mode" => "manually_select_release"
             }
    end
  end

  describe "parse/1 — Incoming's params" do
    test "no plan param is closed" do
      assert PlanQuery.parse(%{}) == :closed
      assert PlanQuery.parse(%{"zone" => "history"}) == :closed
    end

    test "a plan id is its board" do
      assert PlanQuery.parse(%{"plan" => "abc"}) == {:board, "abc"}
    end

    test "new with a title is the picker, mode nil when absent" do
      assert PlanQuery.parse(%{"plan" => "new", "tmdb_id" => "246810", "tmdb_type" => "tv"}) ==
               {:picker, "246810", "tv", nil}
    end

    test "new with a mode carries it as the atom" do
      assert PlanQuery.parse(%{
               "plan" => "new",
               "tmdb_id" => "550",
               "tmdb_type" => "movie",
               "mode" => "auto_select_best_release"
             }) == {:picker, "550", "movie", :auto_select_best_release}
    end

    test "round-trips what it builds" do
      assert PlanQuery.parse(PlanQuery.board("abc")) == {:board, "abc"}
      assert PlanQuery.parse(PlanQuery.picker("1", "tv")) == {:picker, "1", "tv", nil}

      assert PlanQuery.parse(PlanQuery.picker("1", "tv", :manually_select_release)) ==
               {:picker, "1", "tv", :manually_select_release}
    end

    test "a bad mode, a bad type, a missing id or a non-string plan is malformed" do
      assert PlanQuery.parse(%{"plan" => "new", "tmdb_id" => "1", "tmdb_type" => "tv", "mode" => "grab"}) ==
               {:error, :malformed}

      assert PlanQuery.parse(%{"plan" => "new", "tmdb_id" => "1", "tmdb_type" => "book"}) ==
               {:error, :malformed}

      assert PlanQuery.parse(%{"plan" => "new", "tmdb_type" => "tv"}) == {:error, :malformed}
      assert PlanQuery.parse(%{"plan" => ["abc"]}) == {:error, :malformed}
    end
  end
end
```

- [x] **Step 2: Run the test file and watch it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/plan_query_test.exs`
Expected: every test fails with `UndefinedFunctionError` (module `PlanQuery` does not exist).

- [x] **Step 3: Create the module**

Create `lib/media_centaur_web/live/incoming_live/plan_query.ex`:

```elixir
defmodule MediaCentaurWeb.IncomingLive.PlanQuery do
  @moduledoc """
  The plan modal's address — the `?plan=…` query Incoming reads to open
  the board or the picker (UIDR-014) — built and parsed in one place, so
  every link, patch and navigate to it agrees on the params (spec
  2026-09-23, coherence pass 2).

  Two shapes. The board of an existing plan: `plan=<id>`. The picker for
  a series, or the confirm card for a movie:
  `plan=new&tmdb_id=<id>&tmdb_type=tv|movie`, optionally `&mode=<mode>`
  — a planning mode's wire form (`PlanningMode.parse_mode/1`) naming
  which mode the picker's Download performs. Absent means the person's default; Incoming resolves
  that, this module only carries it. A `mode` or `tmdb_type` the app
  cannot mean parses as `{:error, :malformed}`.

  Builders return query maps: a host on Incoming patches with one
  (`incoming_path/2`), any other page navigates to `path/1`.
  """

  use MediaCentaurWeb, :verified_routes

  alias MediaCentaur.Settings.Preferences.PlanningMode

  @tmdb_types ["tv", "movie"]

  @type query :: %{String.t() => String.t()}
  @type parsed ::
          :closed
          | {:board, plan_id :: String.t()}
          | {:picker, tmdb_id :: String.t(), tmdb_type :: String.t(), PlanningMode.mode() | nil}
          | {:error, :malformed}

  @doc "The board of an existing plan."
  @spec board(String.t()) :: query()
  def board(plan_id) when is_binary(plan_id), do: %{"plan" => plan_id}

  @doc """
  The picker for a series (`"tv"`) or the confirm card for a movie
  (`"movie"`). `mode` is the planning mode the picker's Download performs,
  or nil for the person's default.
  """
  @spec picker(String.t() | integer(), String.t(), PlanningMode.mode() | nil) :: query()
  def picker(tmdb_id, tmdb_type, mode \\ nil) when tmdb_type in @tmdb_types do
    query = %{"plan" => "new", "tmdb_id" => to_string(tmdb_id), "tmdb_type" => tmdb_type}
    if mode, do: Map.put(query, "mode", Atom.to_string(mode)), else: query
  end

  @doc "A query as a path to Incoming, for a navigate from another page."
  @spec path(query()) :: String.t()
  def path(query) when is_map(query), do: ~p"/incoming?#{query}"

  @doc "What Incoming's params say the plan modal should show."
  @spec parse(map()) :: parsed()
  def parse(%{"plan" => "new"} = params), do: parse_picker(params)
  def parse(%{"plan" => plan_id}) when is_binary(plan_id), do: {:board, plan_id}
  def parse(%{"plan" => _not_a_string}), do: {:error, :malformed}
  def parse(_params), do: :closed

  defp parse_picker(%{"tmdb_id" => tmdb_id, "tmdb_type" => tmdb_type} = params)
       when is_binary(tmdb_id) and tmdb_type in @tmdb_types do
    case Map.fetch(params, "mode") do
      :error -> {:picker, tmdb_id, tmdb_type, nil}
      {:ok, mode} -> parse_mode(tmdb_id, tmdb_type, mode)
    end
  end

  defp parse_picker(_params), do: {:error, :malformed}

  defp parse_mode(tmdb_id, tmdb_type, mode) do
    case PlanningMode.parse_mode(mode) do
      {:ok, mode} -> {:picker, tmdb_id, tmdb_type, mode}
      :error -> {:error, :malformed}
    end
  end
end
```

- [x] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/plan_query_test.exs`
Expected: all pass. If `~p` complains that the query interpolation is not verified, the project's `MediaCentaurWeb.verified_routes/0` is in `lib/media_centaur_web.ex`; the `use` line above is the standard Phoenix one and `~p"/incoming?#{map}"` is a supported form.

- [x] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/incoming_live/plan_query.ex test/media_centaur_web/live/incoming_live/plan_query_test.exs
git commit -m "feat(incoming): PlanQuery — the plan modal's address, built and parsed once"
```

---

### Task 3: One board hand-off — `open_plan/2` and every address through `PlanQuery`

No behaviour change except one: the missing-episode landing on Incoming becomes a patch instead of a navigate (decision 4). Every existing test keeps passing; one new test pins the patch.

**Files:**
- Modify: `lib/media_centaur_web/live/title_detail_host.ex` (moduledoc lines 35–37, `@callback open_plan_board` around line 123, `land_download` around line 680)
- Modify: `lib/media_centaur_web/live/title_detail_host/acquisition.ex` (imports, `apply_missing_episode_result/2`)
- Modify: `lib/media_centaur_web/live/home_live.ex:306`, `discovery_live.ex:153`, `library_live.ex:566`, `incoming_live.ex:477`
- Modify: `lib/media_centaur_web/components/detail/season_list.ex:125`
- Modify: `lib/media_centaur_web/live/incoming_live.ex` (`resume_plan` ~1542, `plan_create` ~1314, `apply_plan_modal_params` ~2617, `open_plan_targeting` ~2653)
- Test: `test/media_centaur_web/live/incoming_live_test.exs`

- [x] **Step 1: Write the failing test**

In `test/media_centaur_web/live/incoming_live_test.exs`, add a new top-level `describe` at the end of the module (before the final `end`). The module's own `setup` already stubs and configures Prowlarr; this adds the download client so the season list's gap rows are actionable. `Capabilities` is already aliased at the top of the file. The factory functions (`create_tv_series/1`, `create_season/1`, `create_episode/1`) come in through `ConnCase`; if the compiler reports them undefined, add `import MediaCentaur.TestFactory` under the `use` line.

```elixir
  describe "a missing episode of an owned series, from the title detail on Incoming" do
    setup do
      TmdbStubs.stub_series_universe_for_targeting()

      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        config
        |> Map.put(:download_client_type, "qbittorrent")
        |> Map.put(:download_client_url, "http://qbit.test")
      )

      Capabilities.save_test_result(:download_client, :ok)
      Capabilities.refresh_cache()
      :ok
    end

    # The board is Incoming's own modal: landing on it from here is a
    # patch that swaps the title detail for it, never a full navigate.
    test "under manual selection the plan's board opens by a patch", %{conn: conn} do
      series = create_tv_series(%{name: "Sample Show", tmdb_id: "246810"})

      season =
        create_season(%{
          tv_series_id: series.id,
          season_number: 1,
          episode_list: [
            %{episode_number: 1, name: "Pilot", air_date: "2020-01-01"},
            %{episode_number: 2, name: "Second Sample", air_date: "2020-01-08"}
          ]
        })

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/tv/sample-show/s01e01.mkv"
      })

      {:ok, view, _html} = live_async!(conn, ~p"/incoming?title=tv_series-246810")

      view
      |> element("[data-role='missing-episode-row'][phx-value-episode='2']")
      |> render_click()

      render_async(view, 2_000)

      assert [plan] = Plans.list_drafts()
      assert plan.approval_policy == "review"
      assert_patch(view, "/incoming?plan=#{plan.id}")
      assert has_element?(view, "#plan-modal[data-state='open']")
      refute has_element?(view, "#detail-modal[data-state='open']")
    end
  end
```

- [x] **Step 2: Run it and watch it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs --only describe:"a missing episode of an owned series, from the title detail on Incoming"`
Expected: FAIL at `assert_patch` — today the landing is a `push_navigate`, so the view redirects instead of patching (the error names a `live_redirect`).

If the failure is instead that no `missing-episode-row` renders, the gap rows are gated on the indexer being ready; confirm the module-level `setup` sets `prowlarr_url` and `Capabilities.save_test_result(:prowlarr, :ok)` (it does at lines 53–65) before continuing.

- [x] **Step 3: Generalise the host contract**

In `lib/media_centaur_web/live/title_detail_host.ex`:

Add the alias, in alphabetical position among the `MediaCentaurWeb.*` aliases:

```elixir
  alias MediaCentaurWeb.IncomingLive.PlanQuery
```

Replace the moduledoc bullet

```
  * `open_plan_board/2` — navigates to Incoming with the plan's board
    open (`push_navigate` from another page, `push_patch` on Incoming
    itself).
```

with

```
  * `open_plan/2` — opens the plan modal on Incoming with a
    `PlanQuery` query: the board of a plan, or the picker for a series
    (`push_navigate` from another page, `push_patch` on Incoming itself,
    which swaps this modal for it).
```

Replace the callback

```elixir
  @callback open_plan_board(socket :: Phoenix.LiveView.Socket.t(), plan_id :: Ecto.UUID.t()) ::
              Phoenix.LiveView.Socket.t()
```

with

```elixir
  @callback open_plan(socket :: Phoenix.LiveView.Socket.t(), query :: PlanQuery.query()) ::
              Phoenix.LiveView.Socket.t()
```

Replace `land_download`'s success clause

```elixir
  defp land_download(socket, _name, {:ok, {:ok, plan}}) do
    socket = update(socket, :modal_state, &%{&1 | open_menu: nil})
    socket.view.open_plan_board(socket, plan.id)
  end
```

with

```elixir
  defp land_download(socket, _name, {:ok, {:ok, plan}}) do
    socket = update(socket, :modal_state, &%{&1 | open_menu: nil})
    socket.view.open_plan(socket, PlanQuery.board(plan.id))
  end
```

- [x] **Step 4: The four hosts implement `open_plan/2`**

`lib/media_centaur_web/live/home_live.ex`, `discovery_live.ex`, `library_live.ex` — replace each

```elixir
  @impl TitleDetailHost
  def open_plan_board(socket, plan_id), do: push_navigate(socket, to: ~p"/incoming?plan=#{plan_id}")
```

with

```elixir
  @impl TitleDetailHost
  def open_plan(socket, query), do: push_navigate(socket, to: PlanQuery.path(query))
```

and add `alias MediaCentaurWeb.IncomingLive.PlanQuery` to each module's alias block (alphabetical among the `MediaCentaurWeb.*` aliases).

`lib/media_centaur_web/live/incoming_live.ex` — replace

```elixir
  # The board is this page's own modal: a patch swaps the title detail
  # for it (`apply_plan_modal_params/2`).
  @impl TitleDetailHost
  def open_plan_board(socket, plan_id),
    do: push_patch(socket, to: incoming_path(socket, %{"plan" => plan_id}))
```

with

```elixir
  # The plan modal is this page's own: a patch swaps the title detail
  # for it (`apply_plan_modal_params/2`).
  @impl TitleDetailHost
  def open_plan(socket, query), do: push_patch(socket, to: incoming_path(socket, query))
```

and add `PlanQuery` to the `alias MediaCentaurWeb.IncomingLive.{…}` group near the top of the module (line 118).

- [x] **Step 5: One ending for a created plan — `PlanFlow.land_plan/5`**

The missing-episode landing has two endings (manual: the board; auto: flash, stay). Task 4 gives the picker the same two. Put them in `PlanFlow`, whose moduledoc already claims to be that place, and route the missing-episode landing through it now.

In `lib/media_centaur_web/live/plan_flow.ex`, add under the moduledoc:

```elixir
  import Phoenix.LiveView, only: [put_flash: 3]

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaurWeb.IncomingLive.PlanQuery

  @type socket :: Phoenix.LiveView.Socket.t()
```

and, after `download_flash/1`:

```elixir
  @doc """
  Ends a plan a surface has just created under `mode` (spec 2026-09-23
  §7). Manual selection opens the plan's board through the host's
  `open_plan/2`. Auto-select flashes `download_flash/1` for `label` and
  leaves the surface as `close` says — the picker drops its modal, the
  title detail's gap row stays put (`& &1`).
  """
  @spec land_plan(socket(), PlanningMode.mode(), Plans.Plan.t(), String.t(), (socket() -> socket())) ::
          socket()
  def land_plan(socket, :manually_select_release, plan, _label, _close),
    do: socket.view.open_plan(socket, PlanQuery.board(plan.id))

  def land_plan(socket, :auto_select_best_release, _plan, label, close),
    do: socket |> put_flash(:info, download_flash(label)) |> close.()
```

In `lib/media_centaur_web/live/title_detail_host/acquisition.ex`:

Change the import so `push_navigate` is no longer imported (it becomes unused, which is a warning):

```elixir
  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]
```

Replace the two `apply_missing_episode_result` clauses for a planned result

```elixir
  def apply_missing_episode_result(socket, {:planned, _plan, :auto_select_best_release, label}) do
    socket |> pending(nil) |> put_flash(:info, PlanFlow.download_flash(label))
  end

  def apply_missing_episode_result(socket, {:planned, plan, _manual, _label}) do
    socket |> pending(nil) |> push_navigate(to: "/incoming?plan=#{plan.id}")
  end
```

with one:

```elixir
  def apply_missing_episode_result(socket, {:planned, plan, mode, label}) do
    socket |> pending(nil) |> PlanFlow.land_plan(mode, plan, label, & &1)
  end
```

The `@doc` above it stays true ("auto-select flashes and stays put, manual select lands on the plan's board"). In the moduledoc, change "and opens the plan's board on Incoming once it exists, through the host's `open_plan_board/2`" to "and opens the plan's board on Incoming once it exists, through the host's `open_plan/2`".

- [x] **Step 6: The season list's link is built by `PlanQuery`**

In `lib/media_centaur_web/components/detail/season_list.ex`, add the alias (alphabetical, after `MediaCentaurWeb.Components.Detail.PlayableRow`):

```elixir
  alias MediaCentaurWeb.IncomingLive.PlanQuery
```

and replace

```heex
          navigate={~p"/incoming?plan=new&tmdb_id=#{@series_tmdb_id}&tmdb_type=tv"}
```

with

```heex
          navigate={PlanQuery.path(PlanQuery.picker(@series_tmdb_id, "tv"))}
```

- [x] **Step 7: Incoming parses and builds through `PlanQuery`**

In `lib/media_centaur_web/live/incoming_live.ex`:

`resume_plan` — replace

```elixir
  def handle_event("resume_plan", %{"id" => plan_id}, socket) do
    {:noreply, push_patch(socket, to: incoming_path(socket, %{"plan" => plan_id}))}
  end
```

with

```elixir
  def handle_event("resume_plan", %{"id" => plan_id}, socket) do
    {:noreply, open_plan(socket, PlanQuery.board(plan_id))}
  end
```

`plan_create` — in the `{:ok, plan} ->` branch replace

```elixir
         |> push_patch(to: incoming_path(socket, %{"plan" => plan.id}))}
```

with

```elixir
         |> open_plan(PlanQuery.board(plan.id))}
```

`apply_plan_modal_params/2` — replace the `case Map.get(params, "plan") do` dispatch. Keep the body of today's `nil ->` branch (the refocus `then` and the big `assign`) exactly as it is; only the heads change:

```elixir
  defp apply_plan_modal_params(socket, params) do
    case PlanQuery.parse(params) do
      :closed ->
        socket
        # Closing the plan modal hands the page back to searching: refocus
        # the omnibox (client-side, pointer users only — see the
        # `omnibox:refocus` listener in app.js; keyboard/gamepad focus is
        # the input system's, ADR-053).
        |> then(fn socket ->
          if socket.assigns.plan_param, do: push_event(socket, "omnibox:refocus", %{}), else: socket
        end)
        |> assign(
          plan_param: nil,
          plan_selection: nil,
          plan_movie: nil,
          plan_board: nil,
          plan_gap_verdict: nil,
          plan_rejected: nil,
          plan_search_progress: nil,
          plan_alternatives: nil,
          plan_error: nil,
          plan_discard_armed?: false,
          plan_identity: nil,
          plan_artwork: nil,
          plan_title: nil,
          plan_release_window: nil
        )

      {:picker, tmdb_id, tmdb_type, mode} ->
        open_plan_targeting(socket, tmdb_id, tmdb_type, mode)

      {:board, plan_id} ->
        load_plan_board(socket, plan_id)

      {:error, :malformed} ->
        assign(socket, plan_param: nil, plan_stage: :error, plan_error: "Malformed plan link.")
    end
  end
```

`open_plan_targeting` — replace both clauses (the `when tmdb_type in ~w(movie tv)` one and the `_params` fallback; the fallback's body moved into the `{:error, :malformed}` branch above) with one:

```elixir
  # `mode` is carried, not yet read: Task 4 gives it a job.
  defp open_plan_targeting(socket, tmdb_id, tmdb_type, _mode) do
    param = {tmdb_id, tmdb_type}

    if socket.assigns.plan_param == param do
      socket
    else
      socket
      |> assign(
        plan_param: param,
        plan_stage: :loading,
        plan_selection: nil,
        plan_movie: nil,
        plan_board: nil,
        plan_gap_verdict: nil,
        plan_rejected: nil,
        plan_chosen: MapSet.new(),
        plan_expanded_seasons: MapSet.new(),
        plan_error: nil,
        plan_identity: matching_plan_identity(socket, tmdb_id, tmdb_type),
        plan_artwork: nil
      )
      |> start_async(:plan_targeting, fn -> load_targeting(tmdb_id, tmdb_type) end)
    end
  end
```

Update the plan-flow comment above `handle_event("plan_preset", …)`:

```elixir
  # ---------------------------------------------------------------------------
  # Plan flow (UIDR-014) — URL-driven, refresh-safe by construction. The
  # address is `PlanQuery`'s: `plan=new&tmdb_id=…&tmdb_type=…[&mode=…]`
  # opens targeting; `plan=<id>` opens the durable draft's board.
  # ---------------------------------------------------------------------------
```

- [x] **Step 8: Compile clean and run the affected suites**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors`
Expected: no warnings. A leftover `~p` sigil import in `season_list.ex` is fine (other links use it); an unused `push_navigate` import in `acquisition.ex` would fail here.

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/live/library_live_test.exs test/media_centaur_web/live/home_live_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: all pass, including the new missing-episode patch test.

- [x] **Step 9: Commit**

```bash
git add lib/media_centaur_web/live/plan_flow.ex lib/media_centaur_web/live/title_detail_host.ex lib/media_centaur_web/live/title_detail_host/acquisition.ex lib/media_centaur_web/live/home_live.ex lib/media_centaur_web/live/discovery_live.ex lib/media_centaur_web/live/library_live.ex lib/media_centaur_web/live/incoming_live.ex lib/media_centaur_web/components/detail/season_list.ex test/media_centaur_web/live/incoming_live_test.exs
git commit -m "refactor(web): one board hand-off and one plan ending — open_plan/2, PlanFlow.land_plan/5, PlanQuery"
```

---

### Task 4: The picker performs the mode the link carries

**Files:**
- Modify: `lib/media_centaur_web/live/incoming_live.ex` (mount assigns ~262, `apply_plan_modal_params` closed branch, `open_plan_targeting`, `plan_create` ~1278)
- Test: `test/media_centaur_web/live/incoming_live_test.exs` (inside `describe "plan flow — targeting → board → approve (UIDR-014)"`)

- [x] **Step 1: Write the failing tests**

Add these tests inside the `describe "plan flow — targeting → board → approve (UIDR-014)"` block of `test/media_centaur_web/live/incoming_live_test.exs`, after the test "the TV picker downloads and says nothing about the future…". `PlanningMode` must be aliased at the top of the file (`alias MediaCentaur.Settings.Preferences.PlanningMode`) if it is not already. The module-level Prowlarr stub returns no results, so an automatic plan finds nothing, parks, and never contacts a download client.

```elixir
    test "the picker's Download under auto-select creates an automatic plan, closes and flashes",
         %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} =
        live_async!(
          conn,
          ~p"/incoming?plan=new&tmdb_id=246810&tmdb_type=tv&mode=auto_select_best_release"
        )

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      assert_patch(view, "/incoming")
      refute has_element?(view, "#plan-modal[data-state='open']")
      assert render(view) =~ "Finding a release for Sample Show"
      await_supervised_tasks()

      assert [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
    end

    test "the picker's Download under manual selection creates a review plan and opens its board",
         %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} =
        live_async!(
          conn,
          ~p"/incoming?plan=new&tmdb_id=246810&tmdb_type=tv&mode=manually_select_release"
        )

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      assert [plan] = Plans.list_drafts()
      assert plan.approval_policy == "review"
      assert_patch(view, "/incoming?plan=#{plan.id}")
    end

    test "a link without a mode performs the person's default", %{conn: conn} do
      PlanningMode.set(:auto_select_best_release)
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/incoming?plan=new&tmdb_id=246810&tmdb_type=tv")

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      assert_patch(view, "/incoming")
      await_supervised_tasks()
      assert [%{approval_policy: "automatic"}] = Plans.list_drafts()
    end

    test "the movie confirm follows the mode too", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_get_movie(550, TmdbStubs.movie_detail(%{"release_date" => "2005-01-01"}))

      {:ok, view, _html} =
        live_async!(
          conn,
          ~p"/incoming?plan=new&tmdb_id=550&tmdb_type=movie&mode=auto_select_best_release"
        )

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      assert_patch(view, "/incoming")
      assert render(view) =~ "Finding a release for Sample Movie"
      await_supervised_tasks()
      assert [%{approval_policy: "automatic", tmdb_type: "movie"}] = Plans.list_drafts()
    end

    test "a mode the link cannot mean opens nothing and plans nothing", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} =
        live_async!(conn, ~p"/incoming?plan=new&tmdb_id=246810&tmdb_type=tv&mode=grab_everything")

      render_async(view, 2_000)
      refute has_element?(view, "#plan-modal[data-state='open']")
      refute has_element?(view, "button[phx-click='plan_create']")
      assert Plans.list_drafts() == []
    end
```

- [x] **Step 2: Run them and watch them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs`
Expected: the auto-select, default and movie tests fail (the plan is `review` and the view patches to the board); the manual test passes already; the malformed test passes already (Task 3 routed it to the error branch, whose `plan_param: nil` keeps the modal closed — today's behaviour, kept).

- [x] **Step 3: Hold the mode on the socket**

In `lib/media_centaur_web/live/incoming_live.ex`:

In `mount`'s assigns, after `plan_stage: :loading,` add:

```elixir
         plan_mode: nil,
```

In `apply_plan_modal_params/2`'s `:closed` branch assigns, after `plan_param: nil,` add:

```elixir
          plan_mode: nil,
```

Replace `open_plan_targeting/4` with:

```elixir
  # The mode the picker's Download performs: the link's, else the
  # person's default (spec 2026-09-23 §5). Part of the param identity so
  # re-opening the same title under another mode is a new open.
  defp open_plan_targeting(socket, tmdb_id, tmdb_type, mode) do
    param = {tmdb_id, tmdb_type, mode}

    if socket.assigns.plan_param == param do
      socket
    else
      socket
      |> assign(
        plan_param: param,
        plan_stage: :loading,
        plan_mode: mode || PlanningMode.value(),
        plan_selection: nil,
        plan_movie: nil,
        plan_board: nil,
        plan_gap_verdict: nil,
        plan_rejected: nil,
        plan_chosen: MapSet.new(),
        plan_expanded_seasons: MapSet.new(),
        plan_error: nil,
        plan_identity: matching_plan_identity(socket, tmdb_id, tmdb_type),
        plan_artwork: nil
      )
      |> start_async(:plan_targeting, fn -> load_targeting(tmdb_id, tmdb_type) end)
    end
  end
```

`PlanningMode` is already aliased in the module (line 127).

- [x] **Step 4: `plan_create` stamps the policy and ends per mode**

Add the alias (alphabetical among the `MediaCentaurWeb.Live.*` aliases):

```elixir
  alias MediaCentaurWeb.Live.PlanFlow
```

Replace the whole `handle_event("plan_create", _params, socket)` function with:

```elixir
  def handle_event("plan_create", _params, socket) do
    mode = socket.assigns.plan_mode
    opts = [approval_policy: PlanningMode.approval_policy(mode)]

    result =
      case socket.assigns.plan_stage do
        :targeting ->
          selection = socket.assigns.plan_selection
          units = PlanLogic.chosen_in_order(socket.assigns.plan_chosen, selection)

          if units == [],
            do: :noop,
            else: Plans.create_series_plan(selection, units, opts)

        :movie_confirm ->
          movie = socket.assigns.plan_movie
          if movie.in_library?, do: :noop, else: Plans.create_movie_plan(movie, opts)
      end

    case result do
      :noop ->
        {:noreply, socket}

      {:ok, plan} ->
        # The intent just materialized into a draft — the omnibox hunt is
        # over, so it resets to its resting question. (Canceling the flow
        # before this point keeps the query alive for another pick.)
        socket =
          socket
          |> assign(
            plan_drafts: load_drafts(),
            omnibox_query: "",
            omnibox_results: [],
            omnibox_searching?: false,
            omnibox_searched: nil,
            omnibox_scope: :all
          )
          |> build_view()

        # The ending follows the mode (spec 2026-09-23 §7): manual selection
        # opens the board; auto-select flashes and drops the modal, the plan
        # committing on its own when clean and parking here otherwise.
        {:noreply,
         PlanFlow.land_plan(socket, mode, plan, plan.title, &push_patch(&1, to: incoming_path(&1)))}

      {:error, reason} ->
        Log.warning(:acquisition, "plan create failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, Logic.failure_flash("create the plan", reason))}
    end
  end
```

- [x] **Step 5: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs`
Expected: all pass. The existing "plan flow" tests that create a plan without a mode still land on the board because the test database has no planning-mode row, so the default is manual.

- [x] **Step 6: Commit**

```bash
git add lib/media_centaur_web/live/incoming_live.ex test/media_centaur_web/live/incoming_live_test.exs
git commit -m "feat(incoming): the picker's Download performs the planning mode the link carries"
```

---

### Task 5: The third scope value — "Choose episodes"

**Files:**
- Modify: `lib/media_centaur_web/components/title/modal_state.ex`
- Modify: `lib/media_centaur_web/components/title/logic.ex:130-133`
- Modify: `lib/media_centaur_web/components/detail_panel.ex:543-550`
- Modify: `lib/media_centaur_web/live/title_detail_host.ex` (`"download_scope"` event ~838, `"download"` event ~851)
- Modify: `lib/media_centaur_web/live/title_detail_host/acquisition.ex` (`start_download/4`)
- Modify: `storybook/detail_panel/detail_panel.story.exs` (after the `:series_all_seasons` variation)
- Test: `test/media_centaur_web/components/title/modal_state_test.exs`, `test/media_centaur_web/components/title/logic_test.exs`, `test/media_centaur_web/live/discovery_live_test.exs`

- [x] **Step 1: Write the failing pure tests**

`test/media_centaur_web/components/title/modal_state_test.exs` — add a `describe` after the `new/2` block:

```elixir
  describe "the scope select's value" do
    test "offers the two rules and the person's own choice, in menu order" do
      assert ModalState.scope_choices() == [:first_season, :everything, :choose_episodes]
    end

    test "parses its wire form as a closed set" do
      assert ModalState.parse_scope_choice("first_season") == {:ok, :first_season}
      assert ModalState.parse_scope_choice("everything") == {:ok, :everything}
      assert ModalState.parse_scope_choice("choose_episodes") == {:ok, :choose_episodes}
      assert ModalState.parse_scope_choice("all_of_it") == :error
      assert ModalState.parse_scope_choice(nil) == :error
    end
  end
```

`test/media_centaur_web/components/title/logic_test.exs` — in `describe "planning mode and scope words"`, replace the test "each scope has its label" with:

```elixir
    test "each scope choice has its label" do
      assert Logic.download_scope_label(:first_season) == "Season 1"
      assert Logic.download_scope_label(:everything) == "All seasons"
      assert Logic.download_scope_label(:choose_episodes) == "Choose episodes"
    end
```

- [x] **Step 2: Run them and watch them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/modal_state_test.exs test/media_centaur_web/components/title/logic_test.exs`
Expected: `UndefinedFunctionError` for `ModalState.scope_choices/0` and `parse_scope_choice/1`; `FunctionClauseError` for `download_scope_label(:choose_episodes)`.

- [x] **Step 3: The type and its parser on `ModalState`**

In `lib/media_centaur_web/components/title/modal_state.ex`, after the moduledoc and before `defstruct`, add:

```elixir
  alias MediaCentaur.Acquisition.Plans.DownloadScope

  @scope_choices [:first_season, :everything, :choose_episodes]

  @typedoc """
  The scope select's value: a rule `DownloadScope` resolves to episodes,
  or `:choose_episodes` — the person picks them in the picker on Incoming,
  so the Download control opens it instead of planning (spec 2026-09-23
  §1, §3). Not a `DownloadScope.scope/0`: it resolves to nothing here.
  """
  @type scope_choice :: DownloadScope.scope() | :choose_episodes
```

In the `@type t` change `download_scope: :first_season | :everything,` to `download_scope: scope_choice(),`.

After `new/2`, add:

```elixir
  @doc "Every value the scope select offers, in menu order."
  @spec scope_choices() :: [scope_choice()]
  def scope_choices, do: @scope_choices

  @doc "The select's value from its wire form — a closed set, mapped explicitly."
  @spec parse_scope_choice(term()) :: {:ok, scope_choice()} | :error
  def parse_scope_choice("first_season"), do: {:ok, :first_season}
  def parse_scope_choice("everything"), do: {:ok, :everything}
  def parse_scope_choice("choose_episodes"), do: {:ok, :choose_episodes}
  def parse_scope_choice(_other), do: :error
```

In the moduledoc, change "which download scope is chosen" to "which scope choice the select shows".

- [x] **Step 4: The label**

In `lib/media_centaur_web/components/title/logic.ex`, replace

```elixir
  @doc "The scope select's words for a download scope (spec 2026-09-12 §1, §11)."
  @spec download_scope_label(DownloadScope.scope()) :: String.t()
  def download_scope_label(:first_season), do: "Season 1"
  def download_scope_label(:everything), do: "All seasons"
```

with

```elixir
  @doc "The scope select's words for each of its values (spec 2026-09-12 §1, §11; 2026-09-23 §1)."
  @spec download_scope_label(ModalState.scope_choice()) :: String.t()
  def download_scope_label(:first_season), do: "Season 1"
  def download_scope_label(:everything), do: "All seasons"
  def download_scope_label(:choose_episodes), do: "Choose episodes"
```

Replace the alias `alias MediaCentaur.Acquisition.Plans.DownloadScope` (line 12; that spec was its only use, and an unused alias is a warning) with, in alphabetical position among the `MediaCentaurWeb.*` aliases:

```elixir
  alias MediaCentaurWeb.Components.Title.ModalState
```

- [x] **Step 5: Run the pure tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/modal_state_test.exs test/media_centaur_web/components/title/logic_test.exs`
Expected: all pass.

- [x] **Step 6: Write the failing LiveView tests**

In `test/media_centaur_web/live/discovery_live_test.exs`, inside `describe "title detail modal"`, after the test "a series Download plans season 1 by default; the scope select widens it to all seasons", add. Add `alias MediaCentaurWeb.IncomingLive.PlanQuery` to the test module's aliases. No TMDB targeting stub is needed: choosing episodes fetches nothing here.

```elixir
    test "Choose episodes sends Download to the picker with the default mode and plans nothing here",
         %{conn: conn} do
      {:ok, _} = list(released_show(), :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      view |> element("#detail-scope") |> render_click()
      assert has_element?(view, "#detail-scope-menu #detail-scope-choose_episodes", "Choose episodes")

      view |> element("#detail-scope-choose_episodes") |> render_click()
      refute has_element?(view, "#detail-scope-menu")
      assert has_element?(view, "#detail-scope", "Choose episodes")
      # Still a download: the verb names the goal, not the step.
      assert has_element?(view, "#detail-download", "Download")

      view |> element("#detail-download") |> render_click()

      {path, _flash} = assert_redirect(view)
      assert path == PlanQuery.path(PlanQuery.picker(246_810, "tv", :manually_select_release))
      assert Plans.list_drafts() == []
    end

    test "the chevron's other mode rides to the picker with Choose episodes", %{conn: conn} do
      {:ok, _} = list(released_show(), :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      view |> element("#detail-scope") |> render_click()
      view |> element("#detail-scope-choose_episodes") |> render_click()

      view |> element("#detail-download-toggle") |> render_click()
      view |> element("#detail-download-other") |> render_click()

      {path, _flash} = assert_redirect(view)
      assert path == PlanQuery.path(PlanQuery.picker(246_810, "tv", :auto_select_best_release))
      assert Plans.list_drafts() == []
    end

    test "a scope the select does not offer is ignored", %{conn: conn} do
      {:ok, _} = list(released_show(), :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      render_hook(view, "download_scope", %{"choice" => "all_of_it"})
      assert has_element?(view, "#detail-scope", "Season 1")
    end
```

- [x] **Step 7: Run them and watch them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs`
Expected: the first two fail because `#detail-scope-choose_episodes` does not render; the third fails with a `FunctionClauseError` from the `"download_scope"` handler's `when choice in ~w(first_season everything)` guard falling through (no clause matches an unknown choice).

- [x] **Step 8: The select offers it and the host accepts it**

`lib/media_centaur_web/components/detail_panel.ex` — replace

```heex
        :for={scope <- [:first_season, :everything]}
```

with

```heex
        :for={scope <- ModalState.scope_choices()}
```

`ModalState` is the type of the `state` attr in that module; if the alias `MediaCentaurWeb.Components.Title.ModalState` is not already declared, add it.

`lib/media_centaur_web/live/title_detail_host.ex` — replace the `"download_scope"` event

```elixir
  # A closed set, mapped explicitly: `String.to_existing_atom/1` would
  # depend on whether `DownloadScope` happens to be loaded yet.
  def handle_title_event(
        "download_scope",
        %{"choice" => choice},
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      )
      when choice in ~w(first_season everything) do
    scope = if choice == "everything", do: :everything, else: :first_season
    {:halt, update(socket, :modal_state, &%{&1 | download_scope: scope, open_menu: nil})}
  end
```

with

```elixir
  # A closed set, mapped explicitly by `ModalState`: `String.to_existing_atom/1`
  # would depend on whether the atoms happen to be loaded yet. An unknown
  # choice changes nothing.
  def handle_title_event(
        "download_scope",
        %{"choice" => choice},
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      ) do
    case ModalState.parse_scope_choice(choice) do
      {:ok, scope} ->
        {:halt, update(socket, :modal_state, &%{&1 | download_scope: scope, open_menu: nil})}

      :error ->
        {:halt, socket}
    end
  end
```

In the same module's `"download"` event, replace the ending

```elixir
    # Auto-select planned and flashed: the modal closes; a manual plan is
    # pending and the modal stays for its board.
    if mode == :auto_select_best_release, do: {:halt, push_close(socket)}, else: {:halt, socket}
```

with

```elixir
    # Auto-select planned and flashed: the modal closes. A manual plan is
    # pending and the modal stays for its board. Choosing episodes has
    # already left for the picker, whichever the mode.
    if mode == :auto_select_best_release and scope != :choose_episodes,
      do: {:halt, push_close(socket)},
      else: {:halt, socket}
```

- [x] **Step 9: `start_download/4` leaves for the picker**

In `lib/media_centaur_web/live/title_detail_host/acquisition.ex`:

Add the alias (alphabetical among the `MediaCentaurWeb.*` aliases):

```elixir
  alias MediaCentaurWeb.Components.Title.ModalState
```

Replace the spec line

```elixir
  @spec start_download(socket(), Title.t(), PlanningMode.mode(), DownloadScope.scope() | nil) :: socket()
```

with

```elixir
  @spec start_download(socket(), Title.t(), PlanningMode.mode(), ModalState.scope_choice() | nil) ::
          socket()
```

and insert this clause directly after the pending-guard clause (`when not is_nil(pending), do: socket`) and before the `:auto_select_best_release` clause:

```elixir
  # Choosing episodes is the picker's job: the control leaves for it with
  # the click's mode and plans nothing here (spec 2026-09-23 §3).
  def start_download(socket, %Title{} = title, mode, :choose_episodes),
    do: socket.view.open_plan(socket, PlanQuery.picker(title.tmdb_id, "tv", mode))
```

`DownloadScope` stays aliased in that module: `scope_opts/1`'s callers still pass its values. If the compiler reports the alias unused, the `@spec` was its only use — delete the alias.

In the moduledoc, after the sentence ending "through the host's `open_plan/2`.", add: "With the scope select on *Choose episodes* the control performs neither: it opens the picker on Incoming with the click's mode, and the picker's Download makes the plan (spec 2026-09-23)."

- [x] **Step 10: Run the LiveView tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/live/incoming_live_test.exs`
Expected: all pass.

- [x] **Step 11: The story variation**

In `storybook/detail_panel/detail_panel.story.exs`, after the `:series_all_seasons` variation, add:

```elixir
      %Variation{
        id: :series_choose_episodes,
        description:
          "Choose episodes chosen: the select shows it and Download will open the picker on Incoming.",
        attributes: %{
          detail: unowned(show(), %{}),
          state: %{ModalState.new() | download_scope: :choose_episodes}
        }
      },
```

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: pass.

- [x] **Step 12: Commit**

```bash
git add lib/media_centaur_web/components/title/modal_state.ex lib/media_centaur_web/components/title/logic.ex lib/media_centaur_web/components/detail_panel.ex lib/media_centaur_web/live/title_detail_host.ex lib/media_centaur_web/live/title_detail_host/acquisition.ex storybook/detail_panel/detail_panel.story.exs test/media_centaur_web/components/title/modal_state_test.exs test/media_centaur_web/components/title/logic_test.exs test/media_centaur_web/live/discovery_live_test.exs
git commit -m "feat(title): Choose episodes — the scope select's third value sends Download to the picker"
```

---

### Task 6: Documentation

**Files:**
- Modify: `lib/media_centaur_web/live/plan_flow.ex` (moduledoc)
- Modify: `lib/media_centaur/acquisition/plans/download_scope.ex` (moduledoc)
- Modify: `docs/GLOSSARY.md` (rows Approval policy, Download scope, Planning mode)
- Modify: `docs/superpowers/specs/2026-09-12-download-button-default-action-design.md`, `docs/superpowers/specs/2026-09-13-series-gap-download-design.md` (dated amendments)
- Modify (sibling repo `../media-centaur.wiki/`): `Watchlist.md`, `Searching-and-Downloading.md`, `Browsing-Your-Library.md`

- [x] **Step 1: `PlanFlow` moduledoc**

Replace the whole moduledoc of `lib/media_centaur_web/live/plan_flow.ex` with:

```elixir
  @moduledoc """
  The ending a download gets, in one place: the flash auto-select raises,
  and the words for each way planning can fail. How a planning mode maps
  to a plan's approval policy is the setting's own
  (`Settings.Preferences.PlanningMode.approval_policy/1`).

  Three surfaces start downloads and none hosts another. The title detail
  modal (`MediaCentaurWeb.Live.TitleDetailHost`, on Home, Library,
  Discovery and Incoming) downloads a whole title by scope, and one
  missing episode of an owned series from its gap row. The picker on
  Incoming (`MediaCentaurWeb.IncomingLive`, the plan modal's targeting
  stage and movie confirm) downloads what the person chose there. A plan
  any of them has just created ends through `land_plan/5`. The scoped
  title download's auto-select path is the one exception: it hands the
  title to the supervised door (`Plans.plan_title/2`) and has no plan in
  hand, so it flashes `download_flash/1` directly.

  Deliberately not a `use` macro: it holds no state and attaches no hooks.
  The title detail keeps what it has in flight in `Title.ModalState.pending`;
  the picker creates its plan synchronously and has nothing pending.
  """
```

- [x] **Step 2: `DownloadScope` moduledoc**

In `lib/media_centaur/acquisition/plans/download_scope.ex`, after the `:everything` bullet and before "Pure; the caller…", add a paragraph:

```
  The scope select on the title detail offers a third value, *Choose
  episodes* (`Title.ModalState.scope_choice/0`), which is not a scope: it
  resolves to no units here, because the picker on Incoming resolves them
  (spec 2026-09-23 §1).
```

- [x] **Step 3: Glossary rows**

In `docs/GLOSSARY.md`:

Approval policy row — replace "the picker and Plan now as `review`" with "the picker from the planning mode the link carries, else the person's default".

Download scope row — replace the whole row with:

```
| **Download scope** | What the Download button's plan for a series covers (`Plans.DownloadScope`): `:first_season` — the lowest season numbered 1 or higher with a pickable episode, exactly those episodes; `:everything` — the picker's default, every pickable episode. Neither follows the series (ADR-066). Movies have one scope. Chosen by the scope select beside a series' Download button (`GlassMenu.menu_select`): Season 1, All seasons, or *Choose episodes* — a third select value (`Title.ModalState.scope_choice/0`), not a scope, under which Download opens the picker on Incoming with the click's planning mode instead of planning. |
```

Planning mode row — replace "the button's menu offers the other." with "the button's menu offers the other. The picker on Incoming performs the mode its link carries (`IncomingLive.PlanQuery`), else the person's default."

- [x] **Step 4: Spec amendments**

Append to `docs/superpowers/specs/2026-09-12-download-button-default-action-design.md`:

```
## Amendment (2026-09-23) — the picker is no longer unchanged

`2026-09-23-choose-episodes-scope-design.md` amends decision 21: the picker and the movie confirm on Incoming now stamp the approval policy from the planning mode their link carries (`mode` param, else the person's default) and end per mode, instead of always `review`. The scope select of decision 1 gains a third value, *Choose episodes*, under which Download opens the picker with the click's mode. The Download control's own `download_scope` event now takes `choose_episodes` as well.
```

Append to `docs/superpowers/specs/2026-09-13-series-gap-download-design.md`:

```
## Amendment (2026-09-23) — the picker performs the default planning mode

`2026-09-23-choose-episodes-scope-design.md` amends decision 11: the "Download more of this show" link's address is built by `IncomingLive.PlanQuery` and carries no mode, so the picker it opens performs the person's default planning mode — under *auto-select best release* its Download closes the modal and flashes instead of opening the board. The link is no longer the picker's only entry: an unowned series' scope select offers *Choose episodes*.
```

- [x] **Step 5: Wiki**

In `../media-centaur.wiki/Watchlist.md`:

Line 60 — replace

```
For a series, **Download** covers **Season 1** unless the select beside it says **All seasons** — every aired episode not already in your library. Neither says anything about episodes still to come: new episodes are the switches' business, and a download never changes them.
```

with

```
For a series, **Download** covers **Season 1** unless the select beside it says **All seasons** — every aired episode not already in your library — or **Choose episodes**, which opens the episode picker on Incoming so you tick exactly what you want; its own **Download** button then does what this one would have. None of them says anything about episodes still to come: new episodes are the switches' business, and a download never changes them.
```

Line 66 — replace "On a series, the select beside the button chooses **Season 1** or **All seasons**." with "On a series, the select beside the button chooses **Season 1**, **All seasons** or **Choose episodes**; the picker that last one opens performs the same mode you pressed Download with."

In `../media-centaur.wiki/Searching-and-Downloading.md`:

Line 21 — replace "**Download** for a released title you don't (which opens a **download plan** to steer first)" with "**Download** for a released title you don't (a movie or a season plans at once; **Choose episodes** on a series opens the episode picker first)".

Line 69 — after "Under *Auto-select best release* (Settings → Acquisition → Download button) a clean plan commits itself and parks here only when something needs your decision." add: "The episode picker follows the same mode: its **Download** either opens the plan's board or, under auto-select, starts the search and closes."

In `../media-centaur.wiki/Browsing-Your-Library.md`:

Line 71 — replace "opens the search picker for the whole series, with the seasons you already own greyed out." with "opens the episode picker for the whole series, with the seasons you already own greyed out; the picker's **Download** performs your default planning mode (Settings → Acquisition → Download button)."

Then:

```bash
cd ~/src/media-centaur/media-centaur.wiki
git add -A
git commit -m "wiki: Choose episodes scope; the picker performs the planning mode"
cd ~/src/media-centaur/media-centaur-app
```

Do not push the wiki until the app release that carries the feature ships.

- [x] **Step 6: Commit the app-side docs**

```bash
git add lib/media_centaur_web/live/plan_flow.ex lib/media_centaur/acquisition/plans/download_scope.ex docs/GLOSSARY.md docs/superpowers/specs/2026-09-12-download-button-default-action-design.md docs/superpowers/specs/2026-09-13-series-gap-download-design.md
git commit -m "docs: Choose episodes scope — glossary, spec amendments, surfaces named right"
```

---

### Task 7: Precommit and real-browser verification

- [x] **Step 1: Precommit**

Run (foreground, long timeout): `~/scripts/agents/agent-mix precommit`
Expected: compile with no warnings, format clean, credo clean (MC0009 sees the new story variation, MC0024 sees no attribute literals under `=~`), boundaries clean, tests green. Fix anything it reports and amend the last commit.

- [x] **Step 2: Verify the control in the running app**

The dev server is `media-centaur-dev` on `http://127.0.0.1:2160`. Its code reloader picks up the committed source; if a module fails to reload, `journalctl --user -u media-centaur-dev -n 50` says which.

Find a released series on the watchlist that the library does not own (Discovery → Watchlist). Open it and read the control:

```bash
page-shot --url "http://127.0.0.1:2160/discovery/watchlist?title=tv_series-<TMDB_ID>" --wait-ms 3000 --viewport 1920x1080
```

Read the PNG: the Download split button, the scope select reading "Season 1".

Choose the third value and press Download:

```bash
chromium-probe --with-console "http://127.0.0.1:2160/discovery/watchlist?title=tv_series-<TMDB_ID>" '
  (async () => {
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    while (!document.querySelector("[data-phx-main].phx-connected")) await wait(100);
    document.querySelector("#detail-scope").click(); await wait(300);
    document.querySelector("#detail-scope-choose_episodes").click(); await wait(300);
    const label = document.querySelector("#detail-scope").textContent.trim();
    document.querySelector("#detail-download").click(); await wait(1500);
    return { label, url: location.href, pickerOpen: !!document.querySelector("#plan-modal[data-state=open]") };
  })()
'
```

Expected: `label` contains "Choose episodes"; `url` is `/incoming?…plan=new…tmdb_id=<TMDB_ID>…tmdb_type=tv…mode=manually_select_release`; `pickerOpen` is `true`.

In the picker, press "Download N episodes" and confirm the board opens (`location.href` ends in `plan=<uuid>`). Then, under Settings → Acquisition → Download button set *Auto-select best release*, repeat from the watchlist and confirm the picker's Download closes the modal with the "Finding a release for …" flash. Set the preference back afterwards. Discard any draft plans this created on Incoming.

- [x] **Step 3: Keyboard walk**

Run `mc-nav-trace` on the title detail: RIGHT from Download reaches the chevron, then the scope trigger; SELECT opens the scope menu; DOWN walks Season 1, All seasons, Choose episodes; BACK closes it and lands on the trigger. Nothing here is new to the input system, so a difference from the pre-change trace is a regression.

- [x] **Step 4: Report**

State what precommit printed, what the browser showed for each mode, and any drafts left behind. The CHANGELOG entry is written at ship time by `/ship`.
