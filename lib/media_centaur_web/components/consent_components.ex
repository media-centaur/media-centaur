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
          phx-debounce="300"
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

  attr :target, :any,
    required: true,
    doc: "the owning LiveComponent (@myself)",
    doc: "the owning LiveComponent (@myself)"

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
          phx-debounce="300"
          phx-target={@target}
        />
      </label>
      <label class="flex flex-col gap-1">
        <span class="text-sm text-base-content/70">Report</span>
        <textarea
          rows="14"
          class="textarea textarea-bordered w-full font-mono text-xs"
          phx-keyup="set_body"
          phx-debounce="300"
          phx-target={@target}
        >{@body}</textarea>
      </label>
    </div>
    """
  end

  @doc "Step 3 — private-inbox restatement, consent gate, final preview."
  attr :consent, :boolean, required: true
  attr :final_text, :string, required: true
  attr :target, :any, required: true, doc: "the owning LiveComponent (@myself)"

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
        <summary class="text-xs text-base-content/50 cursor-pointer">
          View exactly what will be sent
        </summary>
        <pre class="mt-2 whitespace-pre-wrap font-mono text-xs text-base-content/60">{@final_text}</pre>
      </details>
    </div>
    """
  end
end
