# Consent Flow (Phase 4 M2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the interim single-screen report modal with a guided 3-step, incident-anchored consent flow whose middle step lets the user edit the exact redacted text that will be sent.

**Architecture:** Split *building* a report payload from *submitting* one (`submit_payload/2`); add a pure `assemble_body/2` that prepends an optional user narrative. The `/status` report modal becomes a self-contained 3-step `LiveComponent` (your report → editable attached context → consent + send) that owns its transient state, composes three stateless step function-components (each storied), builds the payload from the single anchoring incident, and submits via `submit_payload/2` with the existing copy-fallback. Visual reference: `mockups/observability/consent-final-3step/index.html`.

**Tech Stack:** Elixir, Phoenix LiveView (LiveComponent + function components), Phoenix Storybook, ExUnit. Design system per the `user-interface` skill (glass surfaces, `<.button>`, always-in-DOM `modal-panel`, color only for severity).

**Spec:** `docs/superpowers/specs/2026-06-01-consent-flow-design.md`

---

## File Structure

- **Modify** `lib/media_centaur/error_reports.ex` — add `submit_payload/2` and `assemble_body/2`; refactor `submit_report/2` to `build |> submit_payload`.
- **Create** `lib/media_centaur_web/components/consent_components.ex` — three stateless step function-components (`consent_intro/1`, `consent_review/1`, `consent_send/1`) + a shared step-indicator. Typed attrs (MC0008).
- **Create** `storybook/status/consent_intro.story.exs`, `consent_review.story.exs`, `consent_send.story.exs` — one per component (MC0009).
- **Rewrite** `lib/media_centaur_web/live/status_live/report_modal.ex` — 3-step `LiveComponent` owning `{step, narrative, title, body, consent, report_result}`; composes the step components; submits via `submit_payload/2`.
- **Modify** `lib/media_centaur_web/live/status_live.ex` — `open_error_report_modal` captures `fingerprint` → `report_bucket` (fallback: top bucket); pass single `bucket` to the modal; drop the parent `report_confirm`/`select` handling (now owned by the modal); keep `report_cancel`.
- **Modify** `test/media_centaur/error_reports/report_submission_test.exs` — `assemble_body/2` + `submit_payload/2` tests.
- **Modify** `test/media_centaur_web/live/status_live/reporting_test.exs` and `report_modal_test.exs` — 3-step flow.

---

## Task 1: `assemble_body/2` — pure narrative + context assembly

**Files:**
- Modify: `lib/media_centaur/error_reports.ex`
- Test: `test/media_centaur/error_reports/report_submission_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `report_submission_test.exs` (inside the module, new describe):

```elixir
describe "assemble_body/2" do
  test "prepends a narrative section when the narrative is present" do
    body = ErrorReports.assemble_body("it froze when I hit play", "## Error\nboom")
    assert body =~ "## What happened (in the user's words)"
    assert body =~ "it froze when I hit play"
    assert body =~ "## Error\nboom"
    # narrative comes before the technical body
    assert :binary.match(body, "What happened") < :binary.match(body, "## Error")
  end

  test "returns the technical body unchanged when the narrative is blank" do
    assert ErrorReports.assemble_body("", "## Error\nboom") == "## Error\nboom"
    assert ErrorReports.assemble_body("   ", "## Error\nboom") == "## Error\nboom"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/error_reports/report_submission_test.exs -v`
Expected: FAIL — `function ErrorReports.assemble_body/2 is undefined`.

- [ ] **Step 3: Implement `assemble_body/2`**

In `lib/media_centaur/error_reports.ex`, add (near `submit_report`):

```elixir
@doc """
Assembles the final report body: the user's narrative (if any) as a leading
section, then the (possibly edited) technical body.
"""
@spec assemble_body(String.t(), String.t()) :: String.t()
def assemble_body(narrative, technical_body) do
  case String.trim(narrative || "") do
    "" -> technical_body
    text -> "## What happened (in the user's words)\n\n" <> text <> "\n\n" <> technical_body
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/media_centaur/error_reports/report_submission_test.exs -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/error_reports.ex test/media_centaur/error_reports/report_submission_test.exs
git commit -m "feat(error-reports): assemble_body/2 — narrative + technical body"
```

---

## Task 2: `submit_payload/2` — submit an already-built/edited payload

**Files:**
- Modify: `lib/media_centaur/error_reports.ex`
- Test: `test/media_centaur/error_reports/report_submission_test.exs`

- [ ] **Step 1: Write the failing test**

The file already defines stub transports `OkTransport` / `FailTransport` and a `bucket/0` helper. Add:

```elixir
describe "submit_payload/2" do
  test "submits an already-built payload as-is" do
    payload = %{title: "T", body: "edited body", labels: ["incident"]}
    assert {:ok, "https://github.com/owner/reports/issues/42"} =
             ErrorReports.submit_payload(payload, transport: OkTransport)
  end

  test "falls back to the payload's own text on transport failure" do
    payload = %{title: "T", body: "edited body", labels: ["incident"]}
    assert {:fallback, bundle} = ErrorReports.submit_payload(payload, transport: FailTransport)
    assert bundle =~ "T"
    assert bundle =~ "edited body"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/error_reports/report_submission_test.exs -v`
Expected: FAIL — `function ErrorReports.submit_payload/2 is undefined`.

- [ ] **Step 3: Refactor `submit_report` onto `submit_payload`**

In `lib/media_centaur/error_reports.ex`, replace the existing `submit_report/2` body and add `submit_payload/2`:

```elixir
@spec submit_report(__MODULE__.Bucket.t(), keyword()) :: {:ok, String.t()} | {:fallback, String.t()}
def submit_report(bucket, opts \\ []) do
  bucket
  |> ReportPayload.build(EnvMetadata.collect())
  |> submit_payload(opts)
end

@doc """
Submits an already-built (possibly user-edited) payload via the configured
transport. `{:ok, url}` on success; `{:fallback, bundle}` (the payload's own
title + body, for the user to copy) on any transport error.
"""
@spec submit_payload(ReportPayload.t() | map(), keyword()) :: {:ok, String.t()} | {:fallback, String.t()}
def submit_payload(payload, opts \\ []) do
  transport = opts[:transport] || configured_transport()

  case transport.submit(payload, opts) do
    {:ok, url} -> {:ok, url}
    {:error, _reason} -> {:fallback, payload.title <> "\n\n" <> payload.body}
  end
end
```

(`configured_transport/0` already exists. If `ReportPayload` has no `@type t`, use `map()` in the spec.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centaur/error_reports/report_submission_test.exs -v`
Expected: PASS (including the pre-existing `submit_report/2` tests, now routed through `submit_payload`).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/error_reports.ex test/media_centaur/error_reports/report_submission_test.exs
git commit -m "feat(error-reports): submit_payload/2; submit_report builds then submits"
```

---

## Task 3: Step function-components + Storybook stories

**Files:**
- Create: `lib/media_centaur_web/components/consent_components.ex`
- Create: `storybook/status/consent_intro.story.exs`, `storybook/status/consent_review.story.exs`, `storybook/status/consent_send.story.exs`

These are **stateless** display components — all state (current value of narrative/title/body/consent, current step) is passed in as attrs; events are pushed to the parent `LiveComponent` via `target`. This keeps them storyable (MC0009) and the logic out of markup (ADR-030).

- [ ] **Step 1: Create the components module**

`lib/media_centaur_web/components/consent_components.ex`:

```elixir
defmodule MediaCentaurWeb.ConsentComponents do
  @moduledoc """
  Stateless step components for the incident-report consent flow
  (`StatusLive.ReportModal`). Each receives current values + a `target` and
  pushes events to the owning LiveComponent. See
  docs/superpowers/specs/2026-06-01-consent-flow-design.md.
  """
  use MediaCentaurWeb, :html

  @doc "Step 1 — friendly explanation, the four promises, optional narrative."
  attr :narrative, :string, required: true
  attr :target, :any, required: true, doc: "the owning LiveComponent (@myself)"

  def consent_intro(assigns) do
    ~H"""
    <div class="flex flex-col gap-4" data-testid="consent-step-1">
      <p class="text-sm text-base-content/70 leading-relaxed">
        Media Centaur noticed this problem and gathered some technical details.
        You'll review everything before it sends — and nothing leaves your machine
        until you say so.
      </p>
      <ul class="flex flex-col gap-2 text-sm">
        <li>You'll see exactly what gets sent.</li>
        <li>You can edit or remove anything.</li>
        <li>Only the core dev team can see it — it's never posted publicly.</li>
        <li>Nothing sends without your OK.</li>
      </ul>
      <label class="flex flex-col gap-1">
        <span class="text-sm text-base-content/70">
          In your own words, what happened? <span class="text-base-content/40">(optional)</span>
        </span>
        <textarea
          rows="4"
          class="textarea textarea-bordered w-full"
          phx-keyup="set_narrative"
          phx-target={@target}
          placeholder="e.g. I added a new movie and its poster never showed up…"
        >{@narrative}</textarea>
      </label>
    </div>
    """
  end

  @doc "Step 2 — the auto-hidden note + editable title and body (exact outgoing text)."
  attr :title, :string, required: true
  attr :body, :string, required: true
  attr :target, :any, required: true

  def consent_review(assigns) do
    ~H"""
    <div class="flex flex-col gap-4" data-testid="consent-step-2">
      <div class="alert alert-warning text-sm">
        <span>
          We've already hidden file paths, keys, IP addresses, and emails. Please
          glance for anything else personal — a private title, a username — and edit
          it out below. This is exactly what will be sent.
        </span>
      </div>
      <label class="flex flex-col gap-1">
        <span class="text-sm text-base-content/70">Title</span>
        <input
          type="text"
          class="input input-bordered w-full font-mono text-xs"
          value={@title}
          phx-keyup="set_title"
          phx-target={@target}
        />
      </label>
      <label class="flex flex-col gap-1">
        <span class="text-sm text-base-content/70">Report</span>
        <textarea
          rows="14"
          class="textarea textarea-bordered w-full font-mono text-xs"
          phx-keyup="set_body"
          phx-target={@target}
        >{@body}</textarea>
      </label>
    </div>
    """
  end

  @doc "Step 3 — private-inbox restatement, consent gate, final preview."
  attr :consent, :boolean, required: true
  attr :final_text, :string, required: true
  attr :target, :any, required: true

  def consent_send(assigns) do
    ~H"""
    <div class="flex flex-col gap-4" data-testid="consent-step-3">
      <div class="glass-inset rounded-lg p-3 text-sm text-base-content/70 leading-relaxed">
        This report goes to a <span class="font-medium text-base-content">private inbox only the
        core Media Centaur dev team can read</span> — it is not posted to any public page. It
        contains exactly what you reviewed, including anything you wrote or edited.
      </div>
      <label class="flex items-start gap-2 cursor-pointer text-sm">
        <input
          type="checkbox"
          class="checkbox checkbox-sm mt-0.5"
          checked={@consent}
          phx-click="toggle_consent"
          phx-target={@target}
        />
        <span>I've reviewed this and agree to send it to the development team.</span>
      </label>
      <details>
        <summary class="text-xs text-base-content/50 cursor-pointer">View exactly what will be sent</summary>
        <pre class="mt-2 whitespace-pre-wrap font-mono text-xs text-base-content/60">{@final_text}</pre>
      </details>
    </div>
    """
  end
end
```

- [ ] **Step 2: Add `ConsentComponents` to the web imports**

In `lib/media_centaur_web.ex`, find the `html_helpers/0` quote block that imports component modules (alongside `CoreComponents`) and add `import MediaCentaurWeb.ConsentComponents`. (Grep: `grep -n "import MediaCentaurWeb" lib/media_centaur_web.ex`.)

- [ ] **Step 3: Create the three stories**

`storybook/status/consent_intro.story.exs` (the repo namespace is `MediaCentaurWeb.Storybook.*`):

```elixir
defmodule MediaCentaurWeb.Storybook.Status.ConsentIntro do
  use PhoenixStorybook.Story, :component
  def function, do: &MediaCentaurWeb.ConsentComponents.consent_intro/1

  def variations do
    [
      %PhoenixStorybook.Stories.Variation{
        id: :empty,
        attributes: %{narrative: "", target: "report-modal-component"}
      },
      %PhoenixStorybook.Stories.Variation{
        id: :with_text,
        attributes: %{narrative: "It froze when I pressed play.", target: "report-modal-component"}
      }
    ]
  end
end
```

`storybook/status/consent_review.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Status.ConsentReview do
  use PhoenixStorybook.Story, :component
  def function, do: &MediaCentaurWeb.ConsentComponents.consent_review/1

  def variations do
    [
      %PhoenixStorybook.Stories.Variation{
        id: :default,
        attributes: %{
          title: "[Pipeline] image download failed",
          body: "## Environment\nApp: media-centaur 0.77.7\n\n## Error\nFingerprint: abc123\n",
          target: "report-modal-component"
        }
      }
    ]
  end
end
```

`storybook/status/consent_send.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Status.ConsentSend do
  use PhoenixStorybook.Story, :component
  def function, do: &MediaCentaurWeb.ConsentComponents.consent_send/1

  def variations do
    [
      %PhoenixStorybook.Stories.Variation{
        id: :unchecked,
        attributes: %{consent: false, final_text: "[Pipeline] image download failed\n\n## Error\n…", target: "report-modal-component"}
      },
      %PhoenixStorybook.Stories.Variation{
        id: :checked,
        attributes: %{consent: true, final_text: "[Pipeline] image download failed\n\n## Error\n…", target: "report-modal-component"}
      }
    ]
  end
end
```

- [ ] **Step 4: Verify components compile + stories render**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS (the three new stories compile + render).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/consent_components.ex lib/media_centaur_web.ex storybook/status/consent_*.story.exs
git commit -m "feat(status): consent-flow step components + stories"
```

---

## Task 4: Rewrite `ReportModal` as a 3-step LiveComponent

**Files:**
- Rewrite: `lib/media_centaur_web/live/status_live/report_modal.ex`
- Test: `test/media_centaur_web/live/status_live/report_modal_test.exs` (Task 6)

The component receives a single `bucket` (the anchoring incident) + builds the redacted payload once on `update`, seeding `title`/`body`. It owns `step`/`narrative`/`title`/`body`/`consent`/`report_result`. On send it submits `%{title, body: assemble_body(narrative, body), labels: [...]}` via `submit_payload/2`. `report_cancel` still bubbles to the parent (close).

- [ ] **Step 1: Write the new component**

Replace the whole file:

```elixir
defmodule MediaCentaurWeb.StatusLive.ReportModal do
  @moduledoc """
  Guided 3-step, incident-anchored consent flow for submitting an error report:
  (1) what happened + optional narrative, (2) review & edit the exact outgoing
  text, (3) consent + send. Owns its step/edit/consent state; submits via
  `ErrorReports.submit_payload/2` (copy-fallback on no-token/offline).
  Spec: docs/superpowers/specs/2026-06-01-consent-flow-design.md.
  """
  use MediaCentaurWeb, :live_component

  alias MediaCentaur.ErrorReports
  alias MediaCentaur.ErrorReports.{EnvMetadata, ReportPayload}

  # Same labels ReportPayload.build/2 uses, so submitted issues stay consistent.
  @labels ["incident", "auto-reported"]

  @impl true
  def update(%{bucket: bucket} = assigns, socket) do
    payload = ReportPayload.build(bucket, EnvMetadata.collect())

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:step, fn -> 1 end)
     |> assign_new(:narrative, fn -> "" end)
     |> assign_new(:title, fn -> payload.title end)
     |> assign_new(:body, fn -> payload.body end)
     |> assign_new(:consent, fn -> false end)
     |> assign_new(:report_result, fn -> nil end)}
  end

  @impl true
  def handle_event("next", _p, socket), do: {:noreply, update(socket, :step, &min(&1 + 1, 3))}
  def handle_event("back", _p, socket), do: {:noreply, update(socket, :step, &max(&1 - 1, 1))}
  def handle_event("set_narrative", %{"value" => v}, socket), do: {:noreply, assign(socket, :narrative, v)}
  def handle_event("set_title", %{"value" => v}, socket), do: {:noreply, assign(socket, :title, v)}
  def handle_event("set_body", %{"value" => v}, socket), do: {:noreply, assign(socket, :body, v)}
  def handle_event("toggle_consent", _p, socket), do: {:noreply, assign(socket, :consent, not socket.assigns.consent)}

  def handle_event("send", _p, socket) do
    payload = %{
      title: socket.assigns.title,
      body: ErrorReports.assemble_body(socket.assigns.narrative, socket.assigns.body),
      labels: @labels
    }

    {:noreply, assign(socket, :report_result, ErrorReports.submit_payload(payload))}
  end

  # report_cancel is NOT handled here — it bubbles to StatusLive (no target: @myself) to close the modal.

  defp final_text(assigns) do
    body = ErrorReports.assemble_body(assigns.narrative, assigns.body)
    assigns.title <> "\n\n" <> body
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="error-report-modal"
      class="modal-backdrop"
      data-state="open"
      data-testid="report-modal"
      phx-window-keydown="report_cancel"
      phx-key="Escape"
    >
      <div class="modal-panel flex flex-col max-h-[88vh]" phx-click={%Phoenix.LiveView.JS{}}>
        <.result :if={@report_result} result={@report_result} />
        <.flow :if={is_nil(@report_result)} {assigns} />
      </div>
    </div>
    """
  end

  # --- result view (sent / fallback) ---
  attr :result, :any, required: true
  defp result(assigns) do
    ~H"""
    <div :if={match?({:ok, _}, @result)} class="p-6 flex flex-col gap-3">
      <h2 class="text-lg font-semibold">Report sent</h2>
      <p class="text-sm text-base-content/70">Thanks — this has been sent to the development team.</p>
      <a href={elem(@result, 1)} target="_blank" rel="noopener" class="link text-sm">View the report</a>
      <.button variant="dismiss" phx-click="report_cancel">Close</.button>
    </div>
    <div :if={match?({:fallback, _}, @result)} class="p-6 flex flex-col gap-3">
      <h2 class="text-lg font-semibold">Copy this report</h2>
      <p class="text-sm text-base-content/70">
        We couldn't send it automatically. Copy the text below and send it to the developer.
      </p>
      <textarea data-testid="report-fallback" readonly rows="12"
        class="textarea textarea-bordered w-full font-mono text-xs">{elem(@result, 1)}</textarea>
      <.button variant="dismiss" phx-click="report_cancel">Close</.button>
    </div>
    """
  end

  # --- the 3-step flow ---
  defp flow(assigns) do
    assigns = assign(assigns, :final_text, final_text(assigns))

    ~H"""
    <div class="px-6 pt-5 pb-3">
      <h2 class="text-base font-semibold">Report this problem to the developer</h2>
      <p class="text-xs text-base-content/50 mt-0.5">Step {@step} of 3</p>
    </div>

    <div class="px-6 flex-1 min-h-0 overflow-y-auto">
      <.consent_intro :if={@step == 1} narrative={@narrative} target={@myself} />
      <.consent_review :if={@step == 2} title={@title} body={@body} target={@myself} />
      <.consent_send :if={@step == 3} consent={@consent} final_text={@final_text} target={@myself} />
    </div>

    <div class="px-6 pt-4 pb-6 flex items-center gap-2 border-t border-base-300">
      <a href="#" class="link link-hover text-sm text-base-content/60" phx-click="report_cancel">No, don't send</a>
      <div class="flex-1"></div>
      <.button :if={@step > 1} variant="dismiss" phx-click={JS.push("back", target: @myself)}>Back</.button>
      <.button :if={@step < 3} variant="primary" phx-click={JS.push("next", target: @myself)}>Next</.button>
      <.button :if={@step == 3} variant="primary" disabled={not @consent}
        phx-click={JS.push("send", target: @myself)}>Send to the developer</.button>
    </div>
    """
  end
end
```

- [ ] **Step 2: Compile**

Run: `mix compile --warnings-as-errors`
Expected: clean (no warnings).

- [ ] **Step 3: Commit**

```bash
git add lib/media_centaur_web/live/status_live/report_modal.ex
git commit -m "feat(status): 3-step consent-flow report modal (LiveComponent)"
```

---

## Task 5: Incident-anchor the modal in StatusLive

**Files:**
- Modify: `lib/media_centaur_web/live/status_live.ex`

`incident_row`'s "Report this" already sends `phx-value-fingerprint`. Capture it; pass the single anchoring bucket to the modal; remove the now-unused parent `report_confirm`/`select` handling.

- [ ] **Step 1: Capture the fingerprint on open + assign the bucket**

Replace the `open_error_report_modal` handler (currently `lib/.../status_live.ex:167`):

```elixir
@impl true
def handle_event("open_error_report_modal", params, socket) do
  bucket =
    case params["fingerprint"] do
      nil -> List.first(socket.assigns.error_buckets)
      fp -> Enum.find(socket.assigns.error_buckets, List.first(socket.assigns.error_buckets), &(&1.fingerprint == fp))
    end

  {:noreply, assign(socket, show_report_modal: not is_nil(bucket), report_bucket: bucket, report_result: nil)}
end
```

- [ ] **Step 2: Remove the old parent `report_confirm` handler**

Delete the `handle_event("report_confirm", %{"fingerprint" => fingerprint}, socket)` clause (currently `:177`) — submission now lives in the modal. Keep `report_cancel`.

- [ ] **Step 3: Default the new assign + pass the single bucket**

In the mount/reset assigns (near `:99`), add `|> assign(report_bucket: nil)`. In the `<.live_component>` invocation (currently `:338`), change `buckets={@error_buckets}` to `bucket={@report_bucket}` (drop `report_result={@report_result}` — the modal owns its result now; remove the `report_result` assign if nothing else uses it — grep first).

- [ ] **Step 4: Compile**

Run: `mix compile --warnings-as-errors`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/status_live.ex
git commit -m "feat(status): anchor the report modal to a single incident"
```

---

## Task 6: LiveView flow tests

**Files:**
- Modify: `test/media_centaur_web/live/status_live/reporting_test.exs`
- Modify: `test/media_centaur_web/live/status_live/report_modal_test.exs`

- [ ] **Step 1: Rewrite the reporting flow test**

Replace `reporting_test.exs`'s single test with a 3-step walk (no token in test → fallback):

```elixir
test "walks the 3-step flow and submits via submit_payload (copy-fallback, no token)", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/status")
  _bucket = seed_bucket("fp-pipeline-error")
  render(view)

  # Open anchored to the seeded incident.
  render_click(view, "open_error_report_modal", %{"fingerprint" => "fp-pipeline-error"})
  assert has_element?(view, "[data-testid=consent-step-1]")

  # Optional narrative, then forward to review + send.
  modal = element(view, "[data-testid=report-modal]")
  render_hook(element(view, "#report-modal-component"), "set_narrative", %{"value" => "froze on play"})
  render_click(view, "next", %{}) || render_click(element(view, "#report-modal-component"), "next", %{})
  assert has_element?(view, "[data-testid=consent-step-2]")
  render_click(element(view, "#report-modal-component"), "next", %{})
  assert has_element?(view, "[data-testid=consent-step-3]")

  # Consent + send → fallback bundle includes the narrative section + the title.
  render_click(element(view, "#report-modal-component"), "toggle_consent", %{})
  html = render_click(element(view, "#report-modal-component"), "send", %{})
  assert html =~ "What happened (in the user&#39;s words)" or html =~ "What happened (in the user's words)"
  assert has_element?(view, "[data-testid=report-fallback]")
  _ = modal
end
```

(LiveComponent events target the component id `#report-modal-component`. If `render_click/3` on the component element is awkward, use `view |> with_target("#report-modal-component") |> render_click("next", %{})`. Adjust to whichever the test lib version supports; the assertion targets are the `data-testid`s.)

- [ ] **Step 2: Run + adjust until green**

Run: `mix test test/media_centaur_web/live/status_live/reporting_test.exs -v`
Expected: PASS — modal opens on step 1, advances to 2 then 3, send produces the fallback textarea whose text contains the narrative section.

- [ ] **Step 3: Update `report_modal_test.exs`**

Update its two behavioural tests: "opens the modal" still asserts `[data-testid=report-modal]` after clicking "Report errors"; replace the old confirm/select assertions with stepping to step 3 + `send` → `[data-testid=report-fallback]`. (Same targeting approach as Step 1.)

- [ ] **Step 4: Run**

Run: `mix test test/media_centaur_web/live/status_live/ -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/media_centaur_web/live/status_live/reporting_test.exs test/media_centaur_web/live/status_live/report_modal_test.exs
git commit -m "test(status): 3-step consent flow → copy-fallback"
```

---

## Task 7: Full gate + campaign reconcile

- [ ] **Step 1: Run the full precommit**

Run: `mix precommit`
Expected: exit 0 — format, Credo (incl. MC0008/MC0009 on the new components/stories), boundaries, sobelow, deps.audit, full Elixir + JS suites green. Fix anything it reports.

- [ ] **Step 2: Reconcile the campaign**

In `campaigns/observability-dashboard.md`, mark M2 done (the guided consent flow shipped) and set the next milestone (M3 — per-subsystem Activity widgets + storage fold + section removal). Bump `last_updated`.

- [ ] **Step 3: Commit**

```bash
git add campaigns/observability-dashboard.md
git commit -m "docs(campaign): Phase 4 M2 (consent flow) shipped"
```

---

## Notes for the implementer

- **Design system:** match `mockups/observability/consent-final-3step/index.html` for layout/feel, but use the real `<.button>` variants, `modal-backdrop`/`modal-panel`, `glass-inset`, and daisyUI form classes (already used above). No console aesthetic, no chip palette; color only on the severity/warning cues.
- **`phx-keyup` vs `phx-change`:** the editable fields use `phx-keyup` to keep component state current without a form wrapper. If keystroke churn is a concern, switch to a `<form phx-change=...>` wrapping all step fields and a single `handle_event("validate", params, ...)` — but keyup is fine for a low-frequency modal.
- **No new network in tests:** the LiveView tests rely on no token being configured (test default) → `submit_payload` returns `{:fallback, _}`. Do not add a token in test config.
