# Updates Status Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beautify the Updates status tile and surface per-version improvements — "What's new" for the available update plus inline-expandable per-version notes in history — by reusing the existing `ReleaseNotes` renderer and embedding `CHANGELOG.md` at compile time.

**Architecture:** A small compile-time `Changelog` splitter exposes each version's markdown body from the embedded `CHANGELOG.md`. The `self_update_widget` reuses `MediaCentaurWeb.Live.SettingsLive.ReleaseNotes` to render both the available-update body and per-version history bodies (native `<details>` disclosure — Activity widgets are stateless). `StatusLive` enriches history entries with their notes body.

**Tech Stack:** Elixir (compile-time `@external_resource`), Phoenix LiveView, Phoenix Storybook, daisyUI/Tailwind, ExUnit.

---

## Background facts (verified — do not re-derive)

- The Updates widget `self_update_widget/1` is already registered and rendered at `/status?subsystem=self_update`. Its attrs: `version, status, latest_release, last_check_at, now, check_enabled?, interval_minutes, auto_install?, apply_phase, apply_progress, history`. It already has private helpers `history_row_id/1`, `history_date/1`, `apply_active?/1`, and aliases `MediaCentaurWeb.Live.SettingsLive.SystemSection`.
- `MediaCentaurWeb.Live.SettingsLive.ReleaseNotes` is a Phoenix.Component in the `MediaCentaurWeb` boundary with `release_notes/1` (attrs `body` (string), `class` (string, default nil)) and a public `parse/1`. It renders CHANGELOG-shaped markdown (`##`/`###` headings, `-`/`*` lists, `**bold**`, `` `code` ``).
- `status` classification atoms: `:idle | :checking | :up_to_date | :update_available | :ahead_of_release | {:error, reason}`. `SystemSection.update_status_tone/1` → `:neutral|:success|:info|:warning|:error`; `SystemSection.tone_class/1` → CSS class; `SystemSection.update_status_label/2`. (All already used by the current widget.)
- `latest_release` map shape: `%{version, tag, published_at, html_url, body}` (`version` = tag without `v`).
- `MediaCentaur.SelfUpdate.upgrade_history/0` → `[%{version: String.t(), recorded_at: DateTime.t()}]`, newest-first. `StatusLive.assign_self_update/1` sets `self_update_history: SelfUpdate.upgrade_history()`; `activity_bundle/1` passes `history: assigns.self_update_history`.
- `MediaCentaur.SelfUpdate` `use Boundary, exports: [UpdateChecker]` (lib/media_centaur/self_update.ex).
- `CHANGELOG.md` (repo root) headers are exactly `## vX.Y.Z — DATE` with an em-dash `—` (U+2014) and spaces, e.g. `## v0.86.1 — 2026-06-09`. A `# Changelog` + prose preamble precedes the first version header.
- Story file: `storybook/status/self_update_widget.story.exs`.
- Status tests use `live_async!/2` and `~p"/status?subsystem=self_update"`.

---

## Task 1: Changelog splitter

**Files:**
- Create: `lib/media_centaur/self_update/changelog.ex`
- Test: `test/media_centaur/self_update/changelog_test.exs`
- Modify: `lib/media_centaur/self_update.ex`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.SelfUpdate.ChangelogTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.SelfUpdate.Changelog

  @fixture """
  # Changelog

  Some preamble prose that must be ignored.

  ## v0.2.0 — 2026-06-09

  ### Improved

  **Second headline.** Second body.

  ## v0.1.0 — 2026-06-01

  ### Fixed

  **First headline.** First body.
  """

  describe "split/1" do
    test "splits versions newest-first with date and body, dropping the preamble" do
      assert [
               %{version: "0.2.0", date: "2026-06-09", body: body2},
               %{version: "0.1.0", date: "2026-06-01", body: body1}
             ] = Changelog.split(@fixture)

      assert body2 =~ "### Improved"
      assert body2 =~ "**Second headline.** Second body."
      refute body2 =~ "v0.1.0"
      assert body1 =~ "**First headline.** First body."
    end

    test "off-format input degrades to an empty list rather than crashing" do
      assert Changelog.split("no version headers here\njust text") == []
    end
  end

  describe "for_version/1 and all/0 over the embedded CHANGELOG" do
    test "all/0 returns a non-empty list of well-formed entries" do
      entries = Changelog.all()
      assert is_list(entries) and entries != []
      assert Enum.all?(entries, &match?(%{version: _, date: _, body: _}, &1))
    end

    test "for_version returns a body for a known version and nil for an unknown one" do
      %{version: known} = hd(Changelog.all())
      assert is_binary(Changelog.for_version(known))
      assert Changelog.for_version("0.0.0-nonexistent") == nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/self_update/changelog_test.exs`
Expected: FAIL — `Changelog` undefined.

- [ ] **Step 3: Implement the module**

```elixir
defmodule MediaCentaur.SelfUpdate.Changelog do
  @moduledoc """
  Per-version release notes embedded from the project `CHANGELOG.md` at compile
  time, for the Updates status tile. `split/1` is the pure splitter (changelog
  markdown → per-version chunks); `all/0` / `for_version/1` / `recent/1` operate
  over the embedded file. Newer-than-build updates are NOT here — those use the
  GitHub release body (`latest_release.body`). Each entry's `body` is raw
  markdown rendered by `MediaCentaurWeb.Live.SettingsLive.ReleaseNotes`.
  """
  @external_resource "CHANGELOG.md"
  @raw File.read!("CHANGELOG.md")

  # Matches a single changelog version header line, e.g. "## v0.86.1 — 2026-06-09".
  @version_header ~r/^##\s+v(?<version>\d+\.\d+\.\d+)\s+—\s+(?<date>\d{4}-\d{2}-\d{2})\s*$/

  @type entry :: %{version: String.t(), date: String.t(), body: String.t()}

  @doc "All embedded changelog entries, newest-first."
  @spec all() :: [entry()]
  def all, do: split(@raw)

  @doc "The N most recent embedded entries."
  @spec recent(non_neg_integer()) :: [entry()]
  def recent(n) when is_integer(n) and n >= 0, do: Enum.take(all(), n)

  @doc "The raw markdown body for `version`, or nil when absent."
  @spec for_version(String.t()) :: String.t() | nil
  def for_version(version) when is_binary(version) do
    case Enum.find(all(), &(&1.version == version)) do
      %{body: body} -> body
      nil -> nil
    end
  end

  @doc "Splits changelog markdown into per-version entries (newest-first as written)."
  @spec split(String.t()) :: [entry()]
  def split(markdown) when is_binary(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      case Regex.named_captures(@version_header, line) do
        %{"version" => version, "date" => date} ->
          [%{version: version, date: date, body_lines: []} | acc]

        nil ->
          case acc do
            [%{body_lines: lines} = current | rest] -> [%{current | body_lines: [line | lines]} | rest]
            [] -> acc
          end
      end
    end)
    |> Enum.map(fn %{version: version, date: date, body_lines: lines} ->
      body = lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()
      %{version: version, date: date, body: body}
    end)
    |> Enum.reverse()
  end
end
```

- [ ] **Step 4: Export from the SelfUpdate boundary**

In `lib/media_centaur/self_update.ex`, change `exports: [UpdateChecker]` to:

```elixir
    exports: [Changelog, UpdateChecker]
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/media_centaur/self_update/changelog_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 6: Compile clean**

Run: `mix compile --warnings-as-errors`
Expected: no warnings, no boundary violations.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur/self_update/changelog.ex test/media_centaur/self_update/changelog_test.exs lib/media_centaur/self_update.ex
git commit -m "feat(self-update): compile-time CHANGELOG splitter for per-version notes"
```

---

## Task 2: Beautify the widget + reuse ReleaseNotes + story

The widget reads each history entry's notes via `Map.get(entry, :notes_body)`, so it stays safe before Task 3 supplies that key (entries without it render as plain rows). Verified in isolation via storybook.

**Files:**
- Modify: `lib/media_centaur_web/components/activity_widget_components.ex`
- Modify: `storybook/status/self_update_widget.story.exs`

- [ ] **Step 1: Alias ReleaseNotes**

Near the other aliases at the top of `activity_widget_components.ex` (the module already `alias`es `MediaCentaurWeb.Live.SettingsLive.SystemSection`), add:

```elixir
  alias MediaCentaurWeb.Live.SettingsLive.ReleaseNotes
```

- [ ] **Step 2: Replace the `self_update_widget/1` body**

Replace the entire `~H"""..."""` template inside `def self_update_widget(assigns) do` with the version below. (Keep the attr block above the function and the private helpers below it unchanged.)

```elixir
    ~H"""
    <div class="card glass-surface" data-testid="self-update-widget">
      <div class="card-body">
        <%!-- Header: title + running version --%>
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Updates</h2>
          <span class="text-sm font-mono text-base-content/60">v{@version}</span>
        </div>

        <p class={["text-sm", SystemSection.tone_class(SystemSection.update_status_tone(@status))]}>
          {SystemSection.update_status_label(@status, @latest_release)}
        </p>

        <%!-- What's new in the available update (reuses the Settings renderer) --%>
        <div
          :if={@status == :update_available && @latest_release}
          class="mt-3 border-t border-base-content/10 pt-3"
          data-component="whats-new"
        >
          <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-2">
            What's new in v{Map.get(@latest_release, :version, "")}
          </h3>
          <ReleaseNotes.release_notes body={Map.get(@latest_release, :body, "")} class="text-xs" />
        </div>

        <%!-- Check cadence + automatic install --%>
        <div class="mt-3 text-xs text-base-content/50 space-y-0.5">
          <p>{SystemSection.last_checked_label(@last_check_at, @now)}</p>
          <p>
            <.settings_link section="updates">
              {SystemSection.update_schedule_label(
                @check_enabled?,
                @interval_minutes,
                @last_check_at,
                @now
              )}
            </.settings_link>
          </p>
          <.settings_link section="updates" class="gap-2">
            <span class="text-base-content/50">Automatic install</span>
            <span class={if @auto_install?, do: "text-success", else: "text-base-content/40"}>
              {if @auto_install?, do: "on", else: "off"}
            </span>
          </.settings_link>
        </div>

        <%!-- History: recent versions, each expandable to its improvements --%>
        <div
          :if={@history != []}
          class="mt-3 border-t border-base-content/10 pt-3"
          data-component="update-history"
        >
          <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-1">
            History
          </h3>
          <ul class="space-y-1">
            <li :for={entry <- @history} id={history_row_id(entry)}>
              <details :if={Map.get(entry, :notes_body)} class="group">
                <summary class="flex items-center justify-between text-xs cursor-pointer list-none py-0.5">
                  <span class="flex items-center gap-1.5">
                    <.icon
                      name="hero-chevron-right-mini"
                      class="size-3.5 shrink-0 text-base-content/40 transition-transform group-open:rotate-90"
                    />
                    <span class="font-mono text-base-content/70">v{entry.version}</span>
                  </span>
                  <span class="text-base-content/40">{history_date(entry.recorded_at)}</span>
                </summary>
                <div class="mt-1.5 mb-2 pl-5">
                  <ReleaseNotes.release_notes body={Map.get(entry, :notes_body)} class="text-xs" />
                </div>
              </details>
              <div
                :if={!Map.get(entry, :notes_body)}
                class="flex items-center justify-between text-xs pl-5 py-0.5"
              >
                <span class="font-mono text-base-content/70">v{entry.version}</span>
                <span class="text-base-content/40">{history_date(entry.recorded_at)}</span>
              </div>
            </li>
          </ul>
        </div>

        <%!-- Apply progress (unchanged) --%>
        <div :if={apply_active?(@apply_phase)} class="mt-3 space-y-1" data-component="apply-progress">
          <div class="flex items-center justify-between text-xs">
            <span class="text-base-content/70">{SystemSection.apply_phase_label(@apply_phase)}</span>
            <span :if={@apply_progress} class="font-mono text-base-content/50">
              {@apply_progress}%
            </span>
          </div>
          <div class="h-[3px] bg-base-content/10 rounded-full overflow-hidden">
            <div
              class="progress-fill h-full bg-primary rounded-full"
              style={"width: #{@apply_progress || 0}%"}
            >
            </div>
          </div>
        </div>

        <p :if={@apply_phase == :failed} class="mt-3 text-xs text-error" data-component="apply-failed">
          {SystemSection.apply_phase_label(:failed)} — see
          <.settings_link section="updates">Settings → Updates</.settings_link>.
        </p>
      </div>
    </div>
    """
```

- [ ] **Step 3: Update the `history` attr doc**

The `attr :history, :list` block above the function documents the entry shape. Update its `doc:` to note the optional notes body:

```elixir
  attr :history, :list,
    default: [],
    doc:
      "upgrade history, newest-first: [%{version, recorded_at, notes_body}] — notes_body is the version's CHANGELOG markdown (Changelog.for_version/1) or nil"
```

- [ ] **Step 4: Update the story**

Replace `variations/0` in `storybook/status/self_update_widget.story.exs` so every variation supplies a `history` whose entries include `notes_body`, plus an `:update_available` variation carrying `latest_release.body`. Keep whatever non-history attrs the existing variations already pass (read the file first); only the snippets below must be present. Example variation set:

```elixir
  def variations do
    now = ~U[2026-06-09 12:00:00Z]

    history = [
      %{
        version: "0.86.1",
        recorded_at: ~U[2026-06-09 09:00:00Z],
        notes_body: "### Fixed\n\n**The Watcher tile no longer blanks the Status page.** It degrades gracefully during a restart."
      },
      %{version: "0.86.0", recorded_at: ~U[2026-06-08 09:00:00Z], notes_body: nil}
    ]

    base = %{
      version: "0.86.1",
      last_check_at: {:ok, ~U[2026-06-09 11:55:00Z]},
      now: now,
      check_enabled?: true,
      interval_minutes: 360,
      auto_install?: false,
      apply_phase: nil,
      apply_progress: nil,
      history: history
    }

    [
      %Variation{
        id: :up_to_date,
        attributes: Map.merge(base, %{status: :up_to_date, latest_release: nil})
      },
      %Variation{
        id: :update_available,
        attributes:
          Map.merge(base, %{
            status: :update_available,
            latest_release: %{
              version: "0.87.0",
              tag: "v0.87.0",
              published_at: now,
              html_url: "https://example.com",
              body:
                "### Improved\n\n**The Updates tile now shows what each release brings.** Expand any version to read its notes."
            }
          })
      }
    ]
  end
```

> Read the existing story first — if it passes additional attrs you must keep them. The `self_update_widget` requires `version, status, last_check_at, now, check_enabled?, interval_minutes, auto_install?, history` and reads optional `latest_release`, `apply_phase`, `apply_progress`.

- [ ] **Step 5: Compile + render**

Run: `mix compile --warnings-as-errors`
Run: `mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS — the self_update story compiles and all variations render (the `update_available` variation exercises `ReleaseNotes` for the body; the `up_to_date` variation exercises a history `<details>` with notes + a plain row).

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/activity_widget_components.ex storybook/status/self_update_widget.story.exs
git commit -m "feat(status): beautify Updates tile — what's-new + per-version expandable history"
```

---

## Task 3: Enrich history in StatusLive

**Files:**
- Modify: `lib/media_centaur_web/live/status_live.ex`
- Test: `test/media_centaur_web/live/status_live_test.exs`

- [ ] **Step 1: Write the test**

Add to `test/media_centaur_web/live/status_live_test.exs` a `describe "updates activity widget"`. This is a non-flaky regression guard that the history enrich (`Changelog.for_version/1` over real boot history) doesn't crash the drill-in render — it does NOT depend on volatile boot-history content (that env varies). The note-attaching/rendering behaviour is covered by the Changelog unit tests (Task 1) and the storybook variations (Task 2).

```elixir
  describe "updates activity widget" do
    test "self_update drill-in renders after the history enrich", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status?subsystem=self_update")
      assert html =~ "Updates"
    end
  end
```

- [ ] **Step 2: Run test to verify it passes (and stays green through the enrich)**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: PASS now (drill-in already renders), and it must STAY green after Step 4 — the point of this guard is that the enrich doesn't raise (e.g. on a history entry whose version isn't in the CHANGELOG → `notes_body: nil`, which the widget tolerates).

- [ ] **Step 3: Alias Changelog**

In `lib/media_centaur_web/live/status_live.ex` alias block, add (skip if present):

```elixir
  alias MediaCentaur.SelfUpdate.Changelog
```

- [ ] **Step 4: Enrich history in `assign_self_update/1`**

Find `assign_self_update/1` (~status_live.ex:148). Change the `self_update_history:` assignment from `SelfUpdate.upgrade_history()` to the enriched, capped form:

```elixir
      self_update_history: recent_update_history(),
```

and add the private helper near it:

```elixir
  # Recent upgrade history (newest-first, capped) with each version's CHANGELOG
  # notes attached for the Updates tile's inline-expandable detail. Versions with
  # no changelog match carry notes_body: nil and render as a plain row.
  defp recent_update_history do
    SelfUpdate.upgrade_history()
    |> Enum.take(5)
    |> Enum.map(fn entry -> Map.put(entry, :notes_body, Changelog.for_version(entry.version)) end)
  end
```

> The widget already tolerates entries with/without `:notes_body` (it uses `Map.get/2`), so this change only adds the notes and the recent-5 cap.

- [ ] **Step 5: Run the test (green)**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: PASS — new test + all pre-existing tests in the file.

- [ ] **Step 6: Compile clean**

Run: `mix compile --warnings-as-errors`
Expected: no warnings, no boundary violations (web → `MediaCentaur.SelfUpdate.Changelog` is now exported).

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/live/status_live.ex test/media_centaur_web/live/status_live_test.exs
git commit -m "feat(status): attach per-version CHANGELOG notes to Updates history"
```

---

## Task 4: Full precommit + self-screenshot + wiki

- [ ] **Step 1: Run precommit**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit`
Expected: format, Credo (incl. MC0009), boundaries, sobelow/deps.audit, full suite all green.

> If Credo flags "nested modules could be aliased" for `MediaCentaur.SelfUpdate.Changelog` in status_live.ex, the Step 3 alias already covers it — use the short `Changelog`. Known intermittent SQLite flake → re-run the file with `--repeat-until-failure 50` to confirm pre-existing.

- [ ] **Step 2: Self-capture (don't ask the user)**

If the dev server on :1080 is up: `~/scripts/agents/viz-screenshot --url 'http://localhost:1080/status?subsystem=self_update' --viewport 1700x1300 --wait-ms 3000 -o /tmp/updates-now.png`, Read it, and sanity-check (header pill, what's-new block when an update is available, history rows expand). If :1080 is down, note it and rely on the storybook variations. (Per auto-memory `reference-responsive-ui-screenshot`.)

- [ ] **Step 3: Wiki sync**

The Updates status tile now shows "what's new" for the available update and per-version improvements in history.

```sh
cd ~/src/media-centaur/media-centaur.wiki
# note the Updates tile now previews the available update's notes and expands each
# installed version to its improvements.
git add -A && git commit -m "wiki: Updates status tile now shows per-version release notes" && git push
```

> If the wiki page is unclear, grep for "status"/"update"; if none, record as a follow-up rather than blocking.

---

## Notes / scope cuts

- **No new markdown parser/renderer** — `ReleaseNotes` is reused for the available-update body and every history body.
- **No runtime file read / per-version GitHub fetch** — installed versions come from the compile-time embed; the available (newer) update uses the already-fetched `latest_release.body`.
- **No LiveView interaction state** — inline expand is native `<details>` (Activity widgets are stateless pure renders).
- History capped to the most recent 5 booted versions.
- Spec: `docs/superpowers/specs/2026-06-09-updates-status-enrichment-design.md`. Persona: auto-memory `project-status-page-persona`.
```
