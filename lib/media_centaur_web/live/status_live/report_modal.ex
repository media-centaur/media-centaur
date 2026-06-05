defmodule MediaCentaurWeb.StatusLive.ReportModal do
  @moduledoc """
  Guided 3-step, incident-anchored consent flow for submitting an error report:
  (1) what happened + optional narrative, (2) review & edit the exact outgoing
  text, (3) consent + send. Owns its step/edit/consent state; submits via
  `ErrorReports.submit_payload/2` (copy-fallback on no-token/offline).
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
    <%!-- report_cancel intentionally bubbles to the parent StatusLive (no phx-target) to close the modal --%>
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
    </div>
    """
  end

  # --- result view (sent / fallback) ---
  attr :result, :any,
    required: true,
    doc: "{:ok, url} | {:fallback, text} from ErrorReports.submit_payload/2"

  defp result(assigns) do
    ~H"""
    <div :if={match?({:ok, _}, @result)} class="p-6 flex flex-col gap-3">
      <h2 class="text-lg font-semibold">Report sent</h2>
      <p class="text-sm text-base-content/70">Thanks — this has been sent to the development team.</p>
      <a href={elem(@result, 1)} target="_blank" rel="noopener" class="link text-sm">
        View the report
      </a>
      <.button variant="dismiss" phx-click="report_cancel">Close</.button>
    </div>
    <div :if={match?({:fallback, _}, @result)} class="p-6 flex flex-col gap-3">
      <h2 class="text-lg font-semibold">Copy this report</h2>
      <p class="text-sm text-base-content/70">
        We couldn't send it automatically. Copy the text below and send it to the developer.
      </p>
      <textarea
        data-testid="report-fallback"
        readonly
        rows="12"
        class="textarea textarea-bordered w-full font-mono text-xs"
      >{elem(@result, 1)}</textarea>
      <.button variant="dismiss" phx-click="report_cancel">Close</.button>
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
        Send to the developer
      </.button>
    </div>
    """
  end
end
