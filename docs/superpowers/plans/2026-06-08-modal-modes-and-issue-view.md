# Modal dismissal modes + ephemeral Issue view — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ephemeral-vs-persistent modal distinction a single named seam (`<.modal dismiss={…}>`), migrate every hand-rolled modal onto it, and add an ephemeral "Issue view" that opens when a Status incident row is clicked.

**Architecture:** One function component `MediaCentaurWeb.Components.Modal` owns `modal-backdrop`/`modal-panel` and derives all dismissal wiring from a required `dismiss` attr (`:ephemeral` wires backdrop-click + Escape; `:persistent` wires neither). All existing modals become thin callers. A new `IssueView` component (ephemeral) renders an `ErrorReports.Bucket`; `StatusLive` opens it on row click and hands off to the persistent report wizard.

**Abstraction lineage — distill our best modal, don't reinvent:** the seam is the *canonical pattern already proven by `ModalShell` and `PursuitModal`* (our best modals), lifted intact: **always rendered in the DOM**, visibility toggled purely via `data-state="open"/"closed"` (keeps the `backdrop-filter` compositing layer warm → no first-frame blur jank), backdrop + panel split, `phx-click={%JS{}}` stop on the panel, and an inner scroll container left to the caller's slot. The seam carries forward those structural qualities; it does NOT hoist `ModalShell`-specific richness (entity backdrop image, atmosphere scrim) — that stays local to ModalShell's slot content (YAGNI until a second modal wants it). Consequence: **all modals — including the persistent wizard and the issue view — stay mounted and toggle via `open`, never `:if`-mounted on demand**, so every modal inherits the warm-compositing behavior of our best one.

**Tech Stack:** Phoenix LiveView function components, daisyUI/Tailwind, Phoenix Storybook, Credo custom checks, ExUnit (`Phoenix.LiveViewTest` + component render tests).

**Sequencing note:** The enforcing Credo check (Task 10) lands LAST. Adding it earlier would flag every not-yet-migrated modal and break `mix precommit` mid-stream.

---

## File Structure

- Create `lib/media_centaur_web/components/modal.ex` — the seam (`modal/1`).
- Modify `lib/media_centaur_web.ex` — import `Modal` into `html_helpers` so `<.modal>` is global.
- Create `storybook/core_components/modal.story.exs` — both dismiss modes.
- Modify `lib/media_centaur_web/components/track_modal.ex`, `acquisition/pursuit_modal.ex`, `modal_shell.ex` → ephemeral callers.
- Modify `lib/media_centaur_web/live/status_live/report_modal.ex` → persistent caller.
- Modify `lib/media_centaur_web/live/settings_live.ex` → three modals onto the seam.
- Create `lib/media_centaur_web/components/status_live/issue_view.ex` — ephemeral issue modal.
- Modify `lib/media_centaur_web/components/health_components.ex` — row body clickable; drop inline "Report this".
- Modify `lib/media_centaur_web/live/status_live.ex` — `select_incident`/`close_incident` + handoff; render `IssueView` in overlays.
- Create `storybook/status/issue_view.story.exs`.
- Modify `storybook/health/incident_row.story.exs` — row no longer has `on_report`.
- Create `credo_checks/modal_backdrop_via_component.ex` + test.
- Create `decisions/user-interface/2026-06-08-0NN-modal-dismissal-modes.md`.

---

## Task 1: The `<.modal>` seam

**Files:**
- Create: `lib/media_centaur_web/components/modal.ex`
- Modify: `lib/media_centaur_web.ex` (html_helpers import)
- Test: `test/media_centaur_web/components/modal_test.exs`

- [ ] **Step 1: Write failing render tests**

```elixir
# test/media_centaur_web/components/modal_test.exs
defmodule MediaCentaurWeb.Components.ModalTest do
  use MediaCentaurWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import MediaCentaurWeb.Components.Modal

  defp render_modal(assigns) do
    assigns = Map.put_new(assigns, :inner_block, fn _ -> "body" end)
    render_component(&modal/1, assigns)
  end

  test "ephemeral wires backdrop click + Escape to on_close" do
    html = render_modal(%{id: "m", open: true, dismiss: :ephemeral, on_close: "close_x"})
    assert html =~ ~s(class="modal-backdrop")
    assert html =~ ~s(phx-click="close_x")
    assert html =~ ~s(phx-window-keydown="close_x")
    assert html =~ ~s(phx-key="Escape")
  end

  test "persistent wires neither backdrop click nor Escape" do
    html = render_modal(%{id: "m", open: true, dismiss: :persistent})
    assert html =~ ~s(class="modal-backdrop")
    refute html =~ "phx-window-keydown"
    # backdrop carries no phx-click; only the panel's JS-stop remains
    refute html =~ ~s(phx-click="close_x")
  end

  test "closed sets data-state and does not fire handlers" do
    html = render_modal(%{id: "m", open: false, dismiss: :ephemeral, on_close: "close_x"})
    assert html =~ ~s(data-state="closed")
    refute html =~ ~s(phx-click="close_x")
  end

  test "size :sm uses modal-panel-sm; panel_class appends" do
    html = render_modal(%{id: "m", open: true, dismiss: :ephemeral, on_close: "x", size: :sm, panel_class: "p-6"})
    assert html =~ "modal-panel-sm"
    assert html =~ "p-6"
  end

  test "rest attrs land on the backdrop" do
    html = render_modal(%{id: "m", open: true, dismiss: :ephemeral, on_close: "x", "data-foo": "bar"})
    assert html =~ ~s(data-foo="bar")
  end
end
```

- [ ] **Step 2: Run, verify fail**

Run: `mix test test/media_centaur_web/components/modal_test.exs`
Expected: FAIL — `MediaCentaurWeb.Components.Modal` undefined.

- [ ] **Step 3: Implement the component**

```elixir
# lib/media_centaur_web/components/modal.ex
defmodule MediaCentaurWeb.Components.Modal do
  @moduledoc """
  The single modal seam. Owns `modal-backdrop`/`modal-panel` (enforced by
  Credo MC00NN — no other module may use those classes).

  The ephemeral-vs-persistent distinction is the required `dismiss` attr:

    * `:ephemeral`  — backdrop click AND Escape fire `on_close`. The default,
      lightweight pattern. Use for read-only or trivially re-openable views.
    * `:persistent` — neither backdrop click nor Escape dismisses. Use when
      dismissal would lose the user's in-progress work; the panel must supply
      explicit dismissal controls (a Cancel/Close button).

  Always rendered in the DOM; visibility is toggled via `data-state` so the
  `backdrop-filter` layer stays warm (no first-frame blur jank).
  """
  use MediaCentaurWeb, :html

  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :dismiss, :atom, values: [:ephemeral, :persistent], required: true

  attr :on_close, :string,
    default: nil,
    doc: "event fired on backdrop click + Escape. Required for :ephemeral; ignored for :persistent."

  attr :size, :atom, values: [:md, :sm], default: :md
  attr :panel_class, :string, default: nil
  attr :rest, :global, doc: "extra attrs forwarded onto the backdrop (e.g. data-* hooks)."
  slot :inner_block, required: true

  def modal(%{dismiss: :ephemeral, on_close: nil}) do
    raise ArgumentError, "<.modal dismiss={:ephemeral}> requires on_close"
  end

  def modal(assigns) do
    assigns =
      assign(assigns,
        panel_size_class: if(assigns.size == :sm, do: "modal-panel-sm", else: nil),
        close_event: assigns.dismiss == :ephemeral && assigns.open && assigns.on_close
      )

    ~H"""
    <div
      id={@id}
      class="modal-backdrop"
      data-state={if @open, do: "open", else: "closed"}
      phx-click={@close_event}
      phx-window-keydown={@close_event}
      phx-key={@dismiss == :ephemeral && "Escape"}
      {@rest}
    >
      <div class={["modal-panel", @panel_size_class, @panel_class]} phx-click={%Phoenix.LiveView.JS{}}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 4: Wire the global import**

In `lib/media_centaur_web.ex`, inside `defp html_helpers`, directly after `import MediaCentaurWeb.CoreComponents`, add:

```elixir
      import MediaCentaurWeb.Components.Modal
```

- [ ] **Step 5: Run, verify pass**

Run: `mix test test/media_centaur_web/components/modal_test.exs`
Expected: PASS (5 tests). Fix any `phx-key` rendering: when `@dismiss != :ephemeral`, the `false` value omits the attribute — that's intended.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/modal.ex lib/media_centaur_web.ex test/media_centaur_web/components/modal_test.exs
git commit -m "feat(ui): add <.modal> seam with required ephemeral/persistent dismiss mode"
```

---

## Task 2: `<.modal>` story (MC0009)

**Files:**
- Create: `storybook/core_components/modal.story.exs`

- [ ] **Step 1: Write the story**

```elixir
# storybook/core_components/modal.story.exs
defmodule MediaCentaurWeb.Storybook.CoreComponents.Modal do
  @moduledoc """
  Story for the `<.modal>` seam. The `dismiss` attr is the formalized
  ephemeral-vs-persistent choice — ephemeral closes on backdrop/Escape,
  persistent ignores both and relies on explicit in-panel controls.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Modal.modal/1
  def render_source, do: :function
  def layout, do: :one_column
  def container, do: {:iframe, style: "min-height: 360px; width: 100%;"}

  def template do
    """
    <div>
      <button type="button" class="btn btn-sm btn-primary"
        phx-click={Phoenix.LiveView.JS.push("psb-assign", value: %{open: true})} psb-code-hidden>
        Open modal
      </button>
      <.psb-variation/>
    </div>
    """
  end

  defp body(assigns) do
    ~H"""
    <div class="p-6 space-y-3">
      <h2 class="text-lg font-semibold">Panel content</h2>
      <p class="text-sm text-base-content/70">Body goes in the default slot.</p>
      <button type="button" class="btn btn-sm" phx-click="psb-assign" phx-value-open="false">Close</button>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :ephemeral_open,
        description: "Ephemeral — backdrop click and Escape both close.",
        attributes: %{id: "story-ephemeral", open: true, dismiss: :ephemeral, on_close: "psb-noop"},
        slots: [&body/1]
      },
      %Variation{
        id: :persistent_open,
        description: "Persistent — neither backdrop click nor Escape dismisses.",
        attributes: %{id: "story-persistent", open: true, dismiss: :persistent},
        slots: [&body/1]
      },
      %Variation{
        id: :small,
        description: "Small panel (confirmations / alerts).",
        attributes: %{id: "story-sm", open: true, dismiss: :ephemeral, on_close: "psb-noop", size: :sm},
        slots: [&body/1]
      }
    ]
  end
end
```

> If `slots: [&body/1]` is rejected by the storybook version, inline the markup as a `slot` string per the repo's other stories. Check an existing story with slot content first.

- [ ] **Step 2: Run storybook compile/render tests**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add storybook/core_components/modal.story.exs
git commit -m "test(storybook): story for <.modal> dismiss modes"
```

---

## Task 3: Migrate `ReportModal` → persistent

**Files:**
- Modify: `lib/media_centaur_web/live/status_live/report_modal.ex:77-97`

- [ ] **Step 1: Update the test for dropped-Escape behavior**

Find or add to `test/media_centaur_web/live/status_live_test.exs` a test that the report modal does NOT close on Escape. Add:

```elixir
test "report wizard ignores Escape (persistent)", %{conn: conn} do
  {:ok, lv, _} = live(conn, ~p"/status")
  # open via the generic report button
  lv |> element(~s([data-testid="report-a-problem"])) |> render_click()
  assert has_element?(lv, ~s([data-testid="report-modal"]))
  # Escape on the window should not close it
  lv |> element(~s([data-testid="report-modal"])) |> render_keydown(%{"key" => "Escape"})
  assert has_element?(lv, ~s([data-testid="report-modal"]))
end
```

- [ ] **Step 2: Run, verify fail**

Run: `mix test test/media_centaur_web/live/status_live_test.exs -k "ignores Escape"`
Expected: FAIL — modal still has `phx-window-keydown="report_cancel"` and closes.

- [ ] **Step 3: Replace the outer backdrop with `<.modal>`**

Replace `report_modal.ex` `render/1` body (lines 75-98) with:

```elixir
    ~H"""
    <.modal id="error-report-modal" open dismiss={:persistent} data-testid="report-modal"
            panel_class="flex flex-col max-h-[88vh]">
      <.result :if={@report_result} result={@report_result} />
      <.flow
        :if={is_nil(@report_result)}
        step={@step}
        narrative={@narrative}
        title={@title}
        body={@body}
        consent={@consent}
        myself={@myself}
      />
    </.modal>
    """
```

(`report_cancel` still bubbles to `StatusLive` from the explicit buttons; the comment about Escape on line 76 is now obsolete — delete it.)

- [ ] **Step 4: Run, verify pass**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/status_live/report_modal.ex test/media_centaur_web/live/status_live_test.exs
git commit -m "refactor(ui): report wizard uses <.modal dismiss={:persistent}>, drops Escape-to-cancel"
```

---

## Task 4: Migrate `TrackModal` → ephemeral

**Files:**
- Modify: `lib/media_centaur_web/components/track_modal.ex:96-168`

- [ ] **Step 1: Replace outer backdrop/panel with `<.modal>`**

Replace lines 97-105 (the `<div class="modal-backdrop" …>` opener and `<div class="modal-panel" …>`) so the body sits inside `<.modal>`:

```elixir
    ~H"""
    <.modal id="track-modal" open={@open} dismiss={:ephemeral} on_close="close_track_modal">
      <div class="flex flex-col flex-1 min-h-0 max-h-[80vh]">
```

and replace the two closing `</div>` for `modal-panel`/`modal-backdrop` (lines 167-168) with `</.modal>` after the existing inner `</div>`:

```elixir
      </div>
    </.modal>
    """
```

Keep the explicit close-X button (line 110-118) as-is.

- [ ] **Step 2: Run story + any track tests**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs && mix test test/media_centaur_web/live/upcoming_live_test.exs`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/media_centaur_web/components/track_modal.ex
git commit -m "refactor(ui): TrackModal uses <.modal dismiss={:ephemeral}>"
```

---

## Task 5: Migrate `PursuitModal` → ephemeral

**Files:**
- Modify: `lib/media_centaur_web/components/acquisition/pursuit_modal.ex:51-97`

- [ ] **Step 1: Replace outer backdrop/panel with `<.modal>`**

```elixir
    ~H"""
    <.modal id="pursuit-modal" open={@open} dismiss={:ephemeral} on_close={@on_close} data-pursuit-modal>
      <div class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden thin-scrollbar">
        ...existing inner content (lines 65-93)...
      </div>
    </.modal>
    """
```

- [ ] **Step 2: Run story + download tests**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs && mix test test/media_centaur_web/live/download_live_test.exs`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/media_centaur_web/components/acquisition/pursuit_modal.ex
git commit -m "refactor(ui): PursuitModal uses <.modal dismiss={:ephemeral}>"
```

---

## Task 6: Migrate `ModalShell` → ephemeral

**Files:**
- Modify: `lib/media_centaur_web/components/modal_shell.ex:77-142`

- [ ] **Step 1: Replace outer backdrop/panel with `<.modal>`**

The `data-detail-mode` / `data-detail-view` hooks ride `:rest` onto the backdrop:

```elixir
    ~H"""
    <.modal
      id="detail-modal"
      open={@open}
      dismiss={:ephemeral}
      on_close={@on_close}
      data-detail-mode={@open && "modal"}
      data-detail-view={@open && to_string(@detail_view)}
    >
      <%!-- existing scroll content (lines 97-140), minus the old modal-panel div --%>
      <div :if={@entity} class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden relative thin-scrollbar">
        ...
      </div>
    </.modal>
    """
```

- [ ] **Step 2: Run story + entity modal tests**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs && mix test test/media_centaur_web/live/library_live_test.exs`
Expected: PASS. (If `data-detail-mode`/`data-detail-view` are read by JS page behaviors, confirm they still render on `#detail-modal` via the rendered HTML in a test or `viz`-style check.)

- [ ] **Step 3: Commit**

```bash
git add lib/media_centaur_web/components/modal_shell.ex
git commit -m "refactor(ui): ModalShell uses <.modal dismiss={:ephemeral}>"
```

---

## Task 7: Migrate the three `settings_live.ex` modals

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live.ex` (~:3446 confirm dialog, ~:3614 service dialog, ~:3668 watch_dir_dialog)

- [ ] **Step 1: watch_dir_dialog → ephemeral (removes the phx-click-away)**

Replace the `<div class="modal-backdrop" …>` / `<div class="modal-panel modal-panel-sm p-6" phx-click-away=…>` wrapper (lines ~3671-3681) with:

```elixir
    <.modal id="watch-dir-dialog" open={!is_nil(@watch_dir_dialog)} dismiss={:ephemeral}
            on_close="watch_dir:close" size={:sm} panel_class="p-6">
```

and the matching closer with `</.modal>`. Delete the now-unused `phx-window-keydown`/`phx-click-away` lines.

- [ ] **Step 2: service dialog (~:3614) → ephemeral**

Replace its backdrop/panel wrapper with `<.modal id="service-dialog" open={!is_nil(@action)} dismiss={:ephemeral} on_close="service_cancel" size={:sm} panel_class="p-6">` and closer `</.modal>`. Remove the `phx-click-away`.

- [ ] **Step 3: confirm dialog (~:3446) → ephemeral**

Replace its backdrop/panel wrapper with `<.modal id="confirm-dialog" open={…existing open condition…} dismiss={:ephemeral} on_close="…existing cancel event…" size={:sm} panel_class="p-6 space-y-5">` and closer `</.modal>`. Read the surrounding lines to capture the exact open-condition and cancel event before editing.

- [ ] **Step 4: Run settings tests + storybook**

Run: `mix test test/media_centaur_web/live/settings_live_test.exs test/storybook_compile_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/settings_live.ex
git commit -m "refactor(ui): settings modals use <.modal>; removes phx-click-away deviation"
```

---

## Task 8: Incident row becomes clickable; "Report this" leaves the row

**Files:**
- Modify: `lib/media_centaur_web/components/health_components.ex:54-96` (incident_row)
- Modify: `storybook/health/incident_row.story.exs`

- [ ] **Step 1: Update the incident_row story (drop on_report)**

In `incident_row.story.exs`, the component no longer takes `on_report`. Update the moduledoc line about "Report this" and ensure variations only pass `bucket` (+ optional `on_select`/`on_dismiss`). No attribute change needed if defaults are used.

- [ ] **Step 2: Rewrite incident_row**

Replace `incident_row/1` (lines 59-96). The row body is a button firing `on_select`; the dismiss X remains and stops propagation; the inline "Report this" button is removed:

```elixir
  @doc "One incident row in the drill-in Issues section. Body opens the issue view; X dismisses."
  attr :bucket, Bucket, required: true
  attr :on_select, :string, default: "select_incident"
  attr :on_dismiss, :string, default: "dismiss_incident"

  def incident_row(assigns) do
    ~H"""
    <div id={"incident-#{@bucket.fingerprint}"} class="glass-inset rounded-lg flex items-stretch">
      <button
        type="button"
        phx-click={@on_select}
        phx-value-fingerprint={@bucket.fingerprint}
        data-nav-item
        class="flex-1 min-w-0 flex items-start gap-3 p-3 text-left cursor-pointer rounded-l-lg hover:bg-base-content/5 transition-colors"
      >
        <span class={[
          "size-2 rounded-full shrink-0 mt-1.5",
          @bucket.severity == :warning && "bg-warning",
          @bucket.severity in [:error, :critical] && "bg-error"
        ]} />
        <span class="min-w-0 flex-1">
          <span class="block text-sm truncate">{@bucket.display_title}</span>
          <span class="block text-xs text-base-content/50 mt-0.5">
            {@bucket.count}× · since {Calendar.strftime(@bucket.first_seen, "%b %-d, %H:%M")}
          </span>
        </span>
      </button>
      <.button
        variant="dismiss"
        size="xs"
        shape="square"
        aria-label="Dismiss"
        class="m-2 self-center"
        phx-click={@on_dismiss}
        phx-value-fingerprint={@bucket.fingerprint}
      >
        <.icon name="hero-x-mark-mini" class="size-4" />
      </.button>
    </div>
    """
  end
```

- [ ] **Step 3: Update `health_drill_in` to pass on_select, drop on_report**

In `health_drill_in/1` (lines 100-138): remove `attr :on_report`, add `attr :on_select, :string, default: "select_incident"`, and in the `<.incident_row>` loop replace `on_report={@on_report}` with `on_select={@on_select}`.

- [ ] **Step 4: Run health storybook + component**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/health_components.ex storybook/health/incident_row.story.exs
git commit -m "feat(status): incident row opens an issue view; report moves off the row"
```

---

## Task 9: The `IssueView` ephemeral modal + StatusLive wiring

**Files:**
- Create: `lib/media_centaur_web/components/status_live/issue_view.ex`
- Create: `storybook/status/issue_view.story.exs`
- Modify: `lib/media_centaur_web/live/status_live.ex` (assign + handlers + overlays + drill-in `on_select`)
- Modify: `test/media_centaur_web/live/status_live_test.exs`

- [ ] **Step 1: Write the IssueView component**

```elixir
# lib/media_centaur_web/components/status_live/issue_view.ex
defmodule MediaCentaurWeb.Components.StatusLive.IssueView do
  @moduledoc """
  Ephemeral modal showing everything known about one `ErrorReports.Bucket`:
  title, subsystem, severity, occurrence count/time-range, a plain-language
  subsystem description, and the raw sample log lines. Footer hands off to the
  persistent report wizard via `on_report`.
  """
  use MediaCentaurWeb, :html

  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaurWeb.StatusLive.HealthBoard

  attr :bucket, Bucket, default: nil, doc: "the selected incident, or nil when closed"
  attr :glyph, :string, default: "hero-exclamation-triangle"
  attr :subsystem_label, :string, default: ""
  attr :on_close, :string, default: "close_incident"
  attr :on_report, :string, default: "report_incident_from_issue"
  attr :on_dismiss, :string, default: "dismiss_incident"

  def issue_view(assigns) do
    ~H"""
    <.modal id="issue-view" open={!is_nil(@bucket)} dismiss={:ephemeral} on_close={@on_close}
            size={:md} panel_class="flex flex-col max-h-[85vh]">
      <div :if={@bucket} class="flex flex-col min-h-0">
        <div class="px-6 pt-5 pb-4 border-b border-base-300">
          <div class="flex items-start gap-3">
            <span class={[
              "size-2.5 rounded-full shrink-0 mt-1.5",
              @bucket.severity == :warning && "bg-warning",
              @bucket.severity in [:error, :critical] && "bg-error"
            ]} />
            <div class="min-w-0">
              <h2 class="text-lg font-semibold leading-snug">{@bucket.display_title}</h2>
              <p class="text-xs text-base-content/55 mt-1 flex items-center gap-1.5">
                <.icon name={@glyph} class="size-4" />
                {@subsystem_label} · {@bucket.count}× ·
                {Calendar.strftime(@bucket.first_seen, "%b %-d, %H:%M")}
                → {Calendar.strftime(@bucket.last_seen, "%b %-d, %H:%M")}
              </p>
            </div>
          </div>
        </div>

        <div class="px-6 py-4 flex-1 min-h-0 overflow-y-auto space-y-4">
          <p class="text-sm text-base-content/70 leading-relaxed max-w-prose">
            {HealthBoard.description(@bucket.component)}
          </p>

          <div :if={@bucket.sample_entries != []} class="space-y-1.5">
            <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Recent log lines
            </h3>
            <div class="glass-inset rounded-lg px-3 py-2 text-xs font-mono text-base-content/60 space-y-1">
              <p :for={entry <- @bucket.sample_entries}>
                <span class="text-base-content/40">
                  {Calendar.strftime(entry.timestamp, "%H:%M:%S")}
                </span>
                {entry.message}
              </p>
            </div>
          </div>
        </div>

        <div class="px-6 py-4 border-t border-base-300 flex items-center gap-2">
          <.button variant="dismiss" phx-click={@on_dismiss} phx-value-fingerprint={@bucket.fingerprint}>
            Dismiss
          </.button>
          <div class="flex-1"></div>
          <.button variant="dismiss" phx-click={@on_close}>Close</.button>
          <.button variant="primary" phx-click={@on_report} phx-value-fingerprint={@bucket.fingerprint}>
            Report this
          </.button>
        </div>
      </div>
    </.modal>
    """
  end
end
```

- [ ] **Step 2: Wire StatusLive — assign + handlers**

In `status_live.ex` mount/assigns add `selected_incident: nil`. Add handlers (near the incident handlers ~line 250):

```elixir
  def handle_event("select_incident", %{"fingerprint" => fp}, socket) do
    bucket = Enum.find(socket.assigns.error_buckets, &(&1.fingerprint == fp))
    {:noreply, assign(socket, :selected_incident, bucket)}
  end

  def handle_event("close_incident", _params, socket) do
    {:noreply, assign(socket, :selected_incident, nil)}
  end

  def handle_event("report_incident_from_issue", %{"fingerprint" => fp} = params, socket) do
    {:noreply,
     socket
     |> assign(:selected_incident, nil)
     |> then(&elem(handle_event("open_error_report_modal", params, &1), 1))}
  end
```

> The `report_incident_from_issue` handler closes the issue view, then reuses the existing `open_error_report_modal/2` logic with the same `fingerprint` param to open the persistent wizard. Verify `open_error_report_modal` reads `params["fingerprint"]` (it does, status_live.ex:268).

- [ ] **Step 3: Render IssueView in overlays + pass on_select to drill-in**

In `render/1`, inside `<:overlays>` (after the ReportModal live_component, ~line 480). **Render it unconditionally — no `:if`** — so it stays mounted and toggles via `data-state`, matching our best modal (ModalShell/PursuitModal). The component already guards its inner content with `:if={@bucket}`, so a nil bucket renders a closed, empty shell:

```elixir
        <IssueView.issue_view
          :if={@selected_incident}
          bucket={@selected_incident}
          glyph={incident_glyph(@board, @selected_incident)}
          subsystem_label={incident_label(@board, @selected_incident)}
        />
```

Wait — to keep it always-mounted, the `glyph`/`label` lookups must tolerate a nil bucket. Render it with a guarded helper instead:

```elixir
        <IssueView.issue_view
          bucket={@selected_incident}
          glyph={@selected_incident && incident_glyph(@board, @selected_incident)}
          subsystem_label={@selected_incident && incident_label(@board, @selected_incident)}
        />
```

and add private helpers that resolve a `SubsystemView` from a bucket's component with a safe fallback:

```elixir
  defp incident_glyph(board, bucket), do: (drill_in_view(board, bucket.component) || %{}).glyph || "hero-exclamation-triangle"
  defp incident_label(board, bucket), do: (drill_in_view(board, bucket.component) || %{}).label || ""
```

> If `drill_in_view/2` already raises on unknown components, give it a nil-returning sibling or guard at the call site. Verify before editing.

Add `alias MediaCentaurWeb.Components.StatusLive.IssueView` near the top (with the other aliases ~line 25). The `<.health_drill_in>` call (line 508) already defaults `on_select` to `"select_incident"`, so no change needed there unless you want it explicit; keep `on_report` removed.

> **ReportModal stays `:if`-mounted (deliberate exception):** it's a stateful `live_component` whose wizard step/edits would persist across opens if always-mounted, requiring an explicit reset path on each open. Always-mounting it is out of scope here; the warm-compositing win matters most for the fast-toggling browse modals (ModalShell) and the issue view, which this plan does keep always-mounted.

> `drill_in_view/2` must tolerate the selected incident's component. Confirm it returns a `SubsystemView` with `.glyph`/`.label` for any bucket component; if it can return nil, guard with a fallback glyph/label.

- [ ] **Step 4: Write the failing LiveView test**

```elixir
test "clicking an incident opens the issue view; Report this hands off to the wizard", %{conn: conn} do
  # seed an incident for a subsystem, then:
  {:ok, lv, _} = live(conn, ~p"/status?subsystem=pipeline")
  lv |> element(~s(#incident-#{fingerprint} button)) |> render_click()
  assert has_element?(lv, "#issue-view[data-state=open]")
  lv |> element(~s(#issue-view button), "Report this") |> render_click()
  refute has_element?(lv, "#issue-view[data-state=open]")
  assert has_element?(lv, ~s([data-testid="report-modal"]))
end

test "issue view closes on Escape (ephemeral)", %{conn: conn} do
  {:ok, lv, _} = live(conn, ~p"/status?subsystem=pipeline")
  lv |> element(~s(#incident-#{fingerprint} button)) |> render_click()
  assert has_element?(lv, "#issue-view[data-state=open]")
  lv |> element("#issue-view") |> render_keydown(%{"key" => "Escape"})
  assert has_element?(lv, "#issue-view[data-state=closed]")
end
```

> Reuse the test's existing incident-seeding helper (look for how `dismiss_incident` / `open_error_report_modal` tests build buckets — likely a `MediaCentaur.ErrorReports` insert or a PubSub broadcast). Bind `fingerprint` from that fixture.

- [ ] **Step 5: Run, verify red→green**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: initially FAIL (handlers/markup absent), PASS after Steps 1-3.

- [ ] **Step 6: IssueView story**

```elixir
# storybook/status/issue_view.story.exs
defmodule MediaCentaurWeb.Storybook.Status.IssueView do
  @moduledoc "Story for the ephemeral incident Issue view."
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ErrorReports.Bucket

  def function, do: &MediaCentaurWeb.Components.StatusLive.IssueView.issue_view/1
  def render_source, do: :function
  def layout, do: :one_column
  def container, do: {:iframe, style: "min-height: 520px; width: 100%;"}

  defp bucket(severity, samples) do
    %Bucket{
      fingerprint: "fp-#{severity}",
      component: :pipeline,
      normalized_message: "image download failed",
      display_title: "Image downloads failing for 11 items",
      severity: severity,
      count: 11,
      first_seen: ~U[2026-06-01 14:02:00Z],
      last_seen: ~U[2026-06-01 15:00:00Z],
      sample_entries: samples
    }
  end

  defp samples do
    [
      %{timestamp: ~U[2026-06-01 14:02:00Z], message: "GET poster 503 (attempt 1)"},
      %{timestamp: ~U[2026-06-01 14:31:00Z], message: "GET poster 503 (attempt 2)"}
    ]
  end

  def variations do
    [
      %Variation{id: :closed, attributes: %{bucket: nil}},
      %Variation{id: :error_with_logs,
        attributes: %{bucket: bucket(:error, samples()), subsystem_label: "Image Pipeline", glyph: "hero-photo"}},
      %Variation{id: :warning_no_logs,
        attributes: %{bucket: bucket(:warning, []), subsystem_label: "Image Pipeline", glyph: "hero-photo"}}
    ]
  end
end
```

- [ ] **Step 7: Run storybook + full status tests**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs test/media_centaur_web/live/status_live_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/media_centaur_web/components/status_live/issue_view.ex storybook/status/issue_view.story.exs lib/media_centaur_web/live/status_live.ex test/media_centaur_web/live/status_live_test.exs
git commit -m "feat(status): ephemeral issue view on incident click, with report handoff"
```

---

## Task 10: Enforce the seam — Credo check

**Files:**
- Create: `credo_checks/modal_backdrop_via_component.ex`
- Test: `test/credo_checks/modal_backdrop_via_component_test.exs`
- Modify: `.credo.exs` (register the check)

- [ ] **Step 1: Write the check test**

```elixir
# test/credo_checks/modal_backdrop_via_component_test.exs
defmodule MediaCentaur.Credo.Checks.ModalBackdropViaComponentTest do
  use Credo.Test.Case
  alias MediaCentaur.Credo.Checks.ModalBackdropViaComponent

  test "flags modal-backdrop literal outside modal.ex" do
    """
    defmodule Foo do
      def render(assigns), do: ~H"<div class=\\"modal-backdrop\\"></div>"
    end
    """
    |> to_source_file("lib/media_centaur_web/components/foo.ex")
    |> run_check(ModalBackdropViaComponent)
    |> assert_issue()
  end

  test "allows modal-backdrop inside modal.ex" do
    """
    defmodule MediaCentaurWeb.Components.Modal do
      def modal(assigns), do: ~H"<div class=\\"modal-backdrop\\"></div>"
    end
    """
    |> to_source_file("lib/media_centaur_web/components/modal.ex")
    |> run_check(ModalBackdropViaComponent)
    |> refute_issues()
  end
end
```

- [ ] **Step 2: Run, verify fail**

Run: `mix test test/credo_checks/modal_backdrop_via_component_test.exs`
Expected: FAIL — check module undefined.

- [ ] **Step 3: Implement the check** (mirror `modal_panel_no_click_away.ex` structure)

```elixir
# credo_checks/modal_backdrop_via_component.ex
defmodule MediaCentaur.Credo.Checks.ModalBackdropViaComponent do
  use Credo.Check,
    id: "MC0017",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      The `modal-backdrop` / `modal-panel` classes may only appear in
      `MediaCentaurWeb.Components.Modal` (`lib/.../components/modal.ex`).
      Every modal must go through the `<.modal>` seam so the ephemeral vs
      persistent dismissal behavior is declared via the required `dismiss`
      attr and can never be half-wired.

          # correct
          <.modal id="x" open={@open} dismiss={:ephemeral} on_close="close_x"> ... </.modal>
      """
    ]

  @allowed_suffix "components/modal.ex"

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if allowed?(filename) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        if String.contains?(line, "modal-backdrop") do
          [issue_for(issue_meta, line_no)]
        else
          []
        end
      end)
    end
  end

  defp allowed?(filename) do
    String.ends_with?(filename, @allowed_suffix) or
      String.ends_with?(filename, "modal_backdrop_via_component_test.exs") or
      String.ends_with?(filename, "modal_panel_no_click_away.ex") or
      String.ends_with?(filename, "modal_panel_no_click_away_test.exs")
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "`modal-backdrop` may only be used in components/modal.ex — route this modal through `<.modal>`.",
      trigger: "modal-backdrop",
      line_no: line_no
    )
  end
end
```

> Pick the next free MC00NN id — grep `credo_checks/` for the highest existing id and increment. The `MC0017` above is a guess; verify.

- [ ] **Step 4: Register in `.credo.exs`**

Add `{MediaCentaur.Credo.Checks.ModalBackdropViaComponent, []}` to the `checks` list (alongside `ModalPanelNoClickAway`).

- [ ] **Step 5: Run check test + full credo**

Run: `mix test test/credo_checks/modal_backdrop_via_component_test.exs && mix credo --strict`
Expected: PASS, and credo reports zero `modal-backdrop` violations (proves the migration is complete). If credo flags a stray modal, migrate it onto `<.modal>` before proceeding.

- [ ] **Step 6: Commit**

```bash
git add credo_checks/modal_backdrop_via_component.ex test/credo_checks/modal_backdrop_via_component_test.exs .credo.exs
git commit -m "feat(credo): MC00NN enforces modal-backdrop only via <.modal> seam"
```

---

## Task 11: ADR

**Files:**
- Create: `decisions/user-interface/2026-06-08-0NN-modal-dismissal-modes.md`

- [ ] **Step 1: Write the ADR** (MADR 4.0 lean; pick the next free per-category number from `decisions/user-interface/`)

Cover: context (two implicit modal behaviors), decision (single `<.modal>` seam, required `dismiss`, persistent ignores Escape+backdrop, enforced by MC00NN), consequences (one place to change modal behavior; new modals must name their mode; the report wizard no longer closes on Escape).

- [ ] **Step 2: Update the decisions index** per `decisions/README.md` convention.

- [ ] **Step 3: Commit**

```bash
git add decisions/user-interface/ decisions/README.md
git commit -m "docs(adr): record modal dismissal modes decision"
```

---

## Task 12: Full precommit + wiki

- [ ] **Step 1: Run precommit**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit`
Expected: clean (format, credo, boundaries, sobelow, deps.audit, test all pass). Fix anything reported.

- [ ] **Step 2: Wiki** — the issue view is a new user-visible flow on the Status page. Add a short note to the relevant *Using Media Centaur* / Troubleshooting wiki page (`~/src/media-centaur/media-centaur.wiki`) describing "click an issue to inspect it, then Report this." Commit + push the wiki.

- [ ] **Step 3: Final commit if any precommit auto-rewrites landed.**

---

## Self-Review

- **Spec coverage:** Part 1 (seam + required mode + migration) → Tasks 1,3-7,10,11. Part 2 (issue view + row change + handoff) → Tasks 8-9. Enforcement/ADR/stories → Tasks 2,9,10,11. Persistent-drops-Escape → Task 3. MC0006 deviation removal → Task 7. ✓
- **Type consistency:** `Bucket` fields (`fingerprint`, `component`, `severity`, `count`, `first_seen`, `last_seen`, `sample_entries` with `%{timestamp, message}`) match across IssueView, story, and tests. `dismiss` values `:ephemeral|:persistent` consistent. Events: `select_incident`, `close_incident`, `report_incident_from_issue`, `dismiss_incident` consistent between component defaults, drill-in, and StatusLive handlers. ✓
- **Open verifications flagged inline:** next-free Credo id; `drill_in_view/2` tolerating any bucket component; storybook slot syntax; the test's incident-seeding helper.
