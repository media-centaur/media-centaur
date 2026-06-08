defmodule MediaCentaurWeb.StatusLive.ReportModal do
  @moduledoc """
  Guided 3-step, incident-anchored consent flow for submitting an error report:
  (1) what happened + optional narrative, (2) review & edit the exact outgoing
  text, (3) consent + send. Owns its step/edit/consent state. On send,
  `ErrorReports.finalize_report/1` produces the redacted text plus a prefilled
  public GitHub new-issue URL; the user copies the report and posts the issue
  under their own GitHub account (no network call here).
  Spec: docs/superpowers/specs/2026-06-01-consent-flow-design.md.
  """
  use MediaCentaurWeb, :live_component

  import MediaCentaurWeb.ConsentComponents

  alias MediaCentaur.ErrorReports

  # Same labels ReportPayload.build/2 uses, so submitted issues stay consistent.
  @labels ["incident", "auto-reported"]

  @impl true
  def update(%{payload: payload} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:step, fn -> 1 end)
     |> assign_new(:narrative, fn -> "" end)
     |> assign_new(:title, fn -> payload.title end)
     |> assign_new(:body, fn -> payload.body end)
     |> assign_new(:consent, fn -> false end)
     |> assign_new(:snapshot, fn -> Map.get(assigns, :snapshot) end)
     |> assign_new(:report_result, fn -> nil end)}
  end

  @impl true
  def handle_event("next", _p, socket), do: {:noreply, update(socket, :step, &min(&1 + 1, 3))}
  def handle_event("back", _p, socket), do: {:noreply, update(socket, :step, &max(&1 - 1, 1))}

  def handle_event("set_narrative", %{"value" => v}, socket),
    do: {:noreply, assign(socket, :narrative, v)}

  def handle_event("set_title", %{"value" => v}, socket), do: {:noreply, assign(socket, :title, v)}
  def handle_event("set_body", %{"value" => v}, socket), do: {:noreply, assign(socket, :body, v)}

  def handle_event("toggle_consent", _p, socket),
    do: {:noreply, assign(socket, :consent, not socket.assigns.consent)}

  def handle_event("send", _p, %{assigns: %{consent: false}} = socket), do: {:noreply, socket}

  def handle_event("send", _p, socket) do
    assembled = %{
      title: socket.assigns.title,
      body: ErrorReports.assemble_body(socket.assigns.narrative, socket.assigns.body),
      labels: @labels
    }

    if snapshot = socket.assigns.snapshot do
      ErrorReports.persist_user_incident(%{
        user_description: socket.assigns.narrative,
        snapshot: snapshot
      })
    end

    {:noreply, assign(socket, :report_result, ErrorReports.finalize_report(assembled))}
  end

  # report_cancel is NOT handled here — it bubbles to StatusLive (no target: @myself) to close the modal.

  defp final_text(assigns) do
    body = ErrorReports.assemble_body(assigns.narrative, assigns.body)
    assigns.title <> "\n\n" <> body
  end

  @impl true
  def render(assigns) do
    # Panel content only — the persistent `<.modal>` wrapper lives in StatusLive's
    # overlays (a stateful component needs a single static root tag, which a
    # function-component call is not). report_cancel bubbles to StatusLive
    # (no phx-target) from the explicit "No, don't send" / "Close" buttons.
    ~H"""
    <div class="flex flex-col min-h-0">
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
    </div>
    """
  end

  # --- result view (copy + open public GitHub issue) ---
  attr :result, :map,
    required: true,
    doc: "%{title, body, issue_url} from ErrorReports.finalize_report/1"

  defp result(assigns) do
    ~H"""
    <div class="p-6 flex flex-col gap-3">
      <h2 class="text-lg font-semibold">Post this report to GitHub</h2>
      <p class="text-sm text-base-content/70">
        This opens a <span class="font-medium">public issue</span> under your GitHub account.
        Copy the report, open the issue, and paste it in.
      </p>
      <textarea
        data-testid="report-fallback"
        readonly
        rows="12"
        class="textarea textarea-bordered w-full font-mono text-xs"
      >{@result.body}</textarea>
      <div class="flex items-center gap-2">
        <.button
          id="report-copy"
          variant="neutral"
          size="sm"
          phx-hook="CopyButton"
          data-copy-text={@result.body}
        >
          Copy report
        </.button>
        <.button variant="primary" size="sm" href={@result.issue_url} target="_blank" rel="noopener">
          Open GitHub issue
        </.button>
        <div class="flex-1"></div>
        <.button variant="dismiss" phx-click="report_cancel">Close</.button>
      </div>
    </div>
    """
  end

  # --- the 3-step flow ---
  attr :step, :integer, required: true
  attr :narrative, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true
  attr :consent, :boolean, required: true
  attr :myself, :any, required: true, doc: "the owning LiveComponent (@myself)"

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
      <button
        type="button"
        class="link link-hover text-sm text-base-content/60"
        phx-click="report_cancel"
      >
        No, don't send
      </button>
      <div class="flex-1"></div>
      <.button :if={@step > 1} variant="dismiss" phx-click={JS.push("back", target: @myself)}>
        Back
      </.button>
      <.button :if={@step < 3} variant="primary" phx-click={JS.push("next", target: @myself)}>
        Next
      </.button>
      <.button
        :if={@step == 3}
        variant="primary"
        disabled={not @consent}
        phx-click={JS.push("send", target: @myself)}
      >
        Review & post to GitHub
      </.button>
    </div>
    """
  end
end
