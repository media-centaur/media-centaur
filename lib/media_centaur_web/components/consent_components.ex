defmodule MediaCentaurWeb.ConsentComponents do
  @moduledoc """
  Stateless step components for the incident-report consent flow
  (`StatusLive.ReportModal`). Each receives current values + a `target` and
  pushes events to the owning LiveComponent. See
  docs/superpowers/specs/2026-06-01-consent-flow-design.md.
  """
  use MediaCentaurWeb, :html

  @doc "Step 1 — public-issue framing, redaction assurances, optional narrative."
  attr :narrative, :string, required: true
  attr :target, :any, required: true, doc: "the owning LiveComponent (@myself)"

  def consent_intro(assigns) do
    ~H"""
    <div class="flex flex-col gap-4" data-testid="consent-step-1">
      <p class="text-sm text-base-content/70 leading-relaxed">
        Media Centaur gathered the technical details of this problem. It will be posted
        as a <span class="font-medium text-base-content">public issue on GitHub</span>
        so it can be tracked and fixed — and you'll review and edit the exact text first.
      </p>
      <ul class="flex flex-col gap-2 text-sm">
        <li>You'll see exactly what gets posted.</li>
        <li>We've removed file paths, API keys, IP addresses, and emails.</li>
        <li>You can edit or remove anything before posting.</li>
        <li>It posts to GitHub under your account, only when you choose to.</li>
      </ul>
      <label class="flex flex-col gap-1">
        <span class="text-sm text-base-content/70">
          In your own words, what happened? <span class="text-base-content/40">(optional)</span>
        </span>
        <form
          id="consent-narrative-form"
          phx-change="set_narrative"
          phx-target={@target}
          phx-debounce="300"
        >
          <textarea
            name="value"
            rows="4"
            class="textarea textarea-bordered w-full"
            placeholder="e.g. I added a new movie and its poster never showed up…"
          >{@narrative}</textarea>
        </form>
      </label>
    </div>
    """
  end

  @doc "Step 2 — the auto-hidden note + editable title and body (exact outgoing text)."
  attr :title, :string, required: true
  attr :body, :string, required: true

  attr :target, :any, required: true, doc: "the owning LiveComponent (@myself)"

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
        <form id="consent-title-form" phx-change="set_title" phx-target={@target} phx-debounce="300">
          <input
            type="text"
            name="value"
            class="input input-bordered w-full font-mono text-xs"
            value={@title}
          />
        </form>
      </label>
      <label class="flex flex-col gap-1">
        <span class="text-sm text-base-content/70">Report</span>
        <form id="consent-body-form" phx-change="set_body" phx-target={@target} phx-debounce="300">
          <textarea
            name="value"
            rows="14"
            class="textarea textarea-bordered w-full font-mono text-xs"
          >{@body}</textarea>
        </form>
      </label>
    </div>
    """
  end

  @doc "Step 3 — public-issue restatement, consent gate, final preview."
  attr :consent, :boolean, required: true
  attr :final_text, :string, required: true
  attr :target, :any, required: true, doc: "the owning LiveComponent (@myself)"

  def consent_send(assigns) do
    ~H"""
    <div class="flex flex-col gap-4" data-testid="consent-step-3">
      <div class="glass-inset rounded-lg p-3 text-sm text-base-content/70 leading-relaxed">
        This opens a <span class="font-medium text-base-content">public GitHub issue</span>
        under your account. It contains exactly what you reviewed, including anything you
        wrote or edited. Give it one more glance — once posted, it's public.
      </div>
      <label class="flex items-start gap-2 cursor-pointer text-sm">
        <input
          type="checkbox"
          class="checkbox checkbox-sm mt-0.5"
          checked={@consent}
          phx-click="toggle_consent"
          phx-target={@target}
        />
        <span>I've reviewed this and I'm posting it publicly on GitHub.</span>
      </label>
      <details>
        <summary class="text-xs text-base-content/50 cursor-pointer">
          View exactly what will be posted
        </summary>
        <pre class="mt-2 whitespace-pre-wrap font-mono text-xs text-base-content/60">{@final_text}</pre>
      </details>
    </div>
    """
  end
end
