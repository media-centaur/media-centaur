defmodule MediaCentaurWeb.Components.SetupSteps do
  @moduledoc """
  Stateless renderers for each step in the Setup Tour wizard.

  Three components, one per step shape:

  - `binary_step/1` — mpv, ffprobe (path field + auto-detected candidates)
  - `integration_step/1` — TMDB, Prowlarr, download client (form fields + test button)
  - `media_dirs_step/1` — directory list with add/remove

  All three accept a typed `%Probe.Result{}` and emit events with
  `phx-value-id={@result.id}` so the parent LiveView routes the event by
  probe id rather than per-step handlers.

  Logic stays here as much as possible (status pills, candidate
  formatting); the LiveView handles persistence and connection tests.
  """

  use MediaCentaurWeb, :html

  alias Phoenix.LiveView.JS

  alias MediaCentaurWeb.Live.SetupLive.{Content, Probe}

  # ---------------------------------------------------------------------------
  # Shared chrome — used by all three step variants
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :content, Content, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true

  attr :form_id, :string,
    default: nil,
    doc:
      "DOM id of the step's inline `<form>`. When present, the footer Next button uses HTML5 `form=`+`type=submit` so clicking Next submits that form. When nil (welcome / summary / media_dirs), Next falls back to `phx-click=\"setup:next\"`."

  attr :optional?, :boolean,
    default: false,
    doc:
      "When true, the Skip button is rendered alongside Next so the user may bypass the step without satisfying its connection test. Critical steps (TMDB, media_dirs) set this to false so the user MUST configure them — Skip is hidden, only Next advances, and the server-side gate (`Setup.Gate`) blocks Next when the test hasn't succeeded."

  attr :blocked?, :boolean,
    default: false,
    doc:
      "Whether `Setup.Gate.check/3` currently blocks advancement. Disables the Next button so the user gets a visual signal instead of a click-then-flash. Form-submit Next buttons are only disabled for non-form steps; form-bearing steps stay clickable because submitting the form is itself the user-visible way to satisfy the gate (the server still re-checks after save)."

  slot :inner_block, required: true

  defp step_shell(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-6 max-w-2xl mx-auto" data-nav-zone="grid">
      <header class="mb-5">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h2 class="text-2xl font-bold tracking-tight">{@content.title}</h2>
            <p class="mt-1 text-sm text-base-content/60">{@content.short}</p>
          </div>
          <.status_line status={@result.status} />
        </div>
        <p :if={@result.detail} class={["mt-3 text-sm", status_text_class(@result.status)]}>
          {@result.detail}
        </p>
      </header>

      <.requirements :if={@content.requirements != []} items={@content.requirements} />

      <div class="space-y-3">
        {render_slot(@inner_block)}
      </div>

      <footer class="flex justify-between mt-6 pt-4 border-t border-base-content/10">
        <.button
          variant="dismiss"
          size="sm"
          phx-click="setup:back"
          disabled={@step_index == 1}
          data-nav-item
          tabindex="0"
        >
          Back
        </.button>
        <div class="flex gap-2">
          <.button
            :if={@optional?}
            variant="dismiss"
            size="sm"
            phx-click="setup:skip"
            data-nav-item
            tabindex="0"
          >
            Skip
          </.button>
          <.button
            :if={@form_id}
            variant="primary"
            size="sm"
            type="submit"
            form={@form_id}
            data-nav-item
            tabindex="0"
          >
            {if @step_index == @total_steps, do: "Finish", else: "Next"}
          </.button>
          <.button
            :if={is_nil(@form_id)}
            variant="primary"
            size="sm"
            phx-click="setup:next"
            disabled={@blocked?}
            data-nav-item
            tabindex="0"
          >
            {if @step_index == @total_steps, do: "Finish", else: "Next"}
          </.button>
        </div>
      </footer>
    </section>
    """
  end

  attr :items, :list,
    required: true,
    doc: "list of plain requirement strings from `Content.requirements` — a flat copy list, not a struct"

  # "What you'll need" — the one concise, actionable block per step. Replaces
  # the old what/why/need essay box (see `Content` moduledoc).
  defp requirements(assigns) do
    ~H"""
    <div class="glass-inset rounded-lg p-4 mb-5">
      <p class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-2">
        What you'll need
      </p>
      <ul class="space-y-1.5">
        <li :for={item <- @items} class="flex gap-2 text-sm text-base-content/70">
          <.icon name="hero-chevron-right-mini" class="size-4 mt-0.5 shrink-0 text-base-content/30" />
          <span class="max-w-[58ch]">{item}</span>
        </li>
      </ul>
    </div>
    """
  end

  attr :status, :atom, required: true

  # Single status indicator per step — an icon + word in the step header.
  # Replaces the old header pill *and* the big colored callout block, which
  # said the same thing twice. The step's `detail` text renders below the
  # header, tinted to match.
  defp status_line(assigns) do
    {icon, label, color} =
      case assigns.status do
        :ok -> {"hero-check-circle-mini", "Configured", "text-success"}
        :warning -> {"hero-exclamation-triangle-mini", "Partial", "text-warning"}
        :error -> {"hero-x-circle-mini", "Needs attention", "text-error"}
        :not_configured -> {"hero-minus-circle-mini", "Not configured", "text-base-content/50"}
      end

    assigns = assign(assigns, icon: icon, label: label, color: color)

    ~H"""
    <span class={["inline-flex items-center gap-1.5 text-sm font-medium shrink-0", @color]}>
      <.icon name={@icon} class="size-4" />
      {@label}
    </span>
    """
  end

  defp status_text_class(:ok), do: "text-success"
  defp status_text_class(:warning), do: "text-warning"
  defp status_text_class(:error), do: "text-error"
  defp status_text_class(:not_configured), do: "text-base-content/60"

  # ---------------------------------------------------------------------------
  # Binary step — mpv, ffprobe
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :content, Content, required: true
  attr :binary_name, :string, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true
  attr :optional?, :boolean, default: true
  attr :blocked?, :boolean, default: false

  def binary_step(assigns) do
    form_id = "setup-step-#{assigns.binary_name}-form"
    assigns = assign(assigns, :form_id, form_id)

    ~H"""
    <.step_shell
      result={@result}
      content={@content}
      step_index={@step_index}
      total_steps={@total_steps}
      form_id={@form_id}
      optional?={@optional?}
      blocked?={@blocked?}
    >
      <form
        id={@form_id}
        phx-submit="setup:save_path"
        phx-value-id={@result.id}
        class="flex gap-2 items-center"
      >
        <input
          type="text"
          name="path"
          value={@result.current_value || ""}
          placeholder={"/usr/bin/" <> @binary_name}
          class="input input-bordered input-sm flex-1 font-mono text-sm"
          data-nav-item
          tabindex="0"
        />
        <.button
          type="button"
          variant="outline"
          size="sm"
          phx-click="setup:recheck"
          phx-value-id={@result.id}
          data-nav-item
          tabindex="0"
        >
          Re-check
        </.button>
      </form>

      <div :if={candidates_to_show(@result) != []} class="space-y-2">
        <p class="text-xs uppercase tracking-wide opacity-60">
          Detected on this system:
        </p>
        <ul class="space-y-1">
          <li
            :for={candidate <- candidates_to_show(@result)}
            class="flex items-center justify-between gap-2 text-sm"
          >
            <code class="font-mono opacity-90">{candidate}</code>
            <.button
              variant="dismiss"
              size="xs"
              phx-click="setup:save_path"
              phx-value-id={@result.id}
              phx-value-path={candidate}
              data-nav-item
              tabindex="0"
            >
              Use this
            </.button>
          </li>
        </ul>
      </div>

      <div
        :if={candidates_to_show(@result) == [] and @result.status != :ok}
        class="alert alert-info text-sm"
      >
        <span>
          No <code>{@binary_name}</code>
          found on this system. Install it via your OS package manager and click <strong>Re-check</strong>.
        </span>
      </div>
    </.step_shell>
    """
  end

  # If the configured path is already the only candidate, hide the
  # "Use this" list — there's nothing to switch to.
  defp candidates_to_show(%Probe.Result{detected_candidates: nil}), do: []

  defp candidates_to_show(%Probe.Result{current_value: current, detected_candidates: [current]}), do: []

  defp candidates_to_show(%Probe.Result{detected_candidates: candidates}), do: candidates

  # ---------------------------------------------------------------------------
  # Integration step — TMDB, Prowlarr, download client
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :content, Content, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true
  attr :form_id, :string, required: true
  attr :optional?, :boolean, default: false
  attr :blocked?, :boolean, default: false
  slot :form, required: true, doc: "Settings form fields specific to this integration"

  def integration_step(assigns) do
    ~H"""
    <.step_shell
      result={@result}
      content={@content}
      step_index={@step_index}
      total_steps={@total_steps}
      form_id={@form_id}
      optional?={@optional?}
      blocked?={@blocked?}
    >
      <div class="space-y-3">
        {render_slot(@form)}
      </div>
    </.step_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Media dirs step
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :content, Content, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true
  attr :blocked?, :boolean, default: false

  def media_dirs_step(assigns) do
    ~H"""
    <.step_shell
      result={@result}
      content={@content}
      step_index={@step_index}
      total_steps={@total_steps}
      blocked?={@blocked?}
    >
      <ul :if={dirs_list(@result) != []} class="space-y-1">
        <li
          :for={dir <- dirs_list(@result)}
          class="flex items-center justify-between gap-2 p-2 rounded bg-base-content/5"
        >
          <code class="font-mono text-sm">{dir}</code>
          <.button
            variant="dismiss"
            size="xs"
            phx-click="setup:remove_media_dir"
            phx-value-dir={dir}
            data-nav-item
            tabindex="0"
          >
            Remove
          </.button>
        </li>
      </ul>

      <p :if={dirs_list(@result) == []} class="text-sm text-base-content/50 italic">
        No media directories yet — add one or more below.
      </p>

      <p :if={dirs_list(@result) != []} class="text-xs text-base-content/50">
        Add as many as you like — movies and TV can live in separate folders.
      </p>

      <form
        id="setup-add-media-dir-form"
        phx-submit={
          JS.push("setup:add_media_dir")
          |> JS.set_attribute({"value", ""}, to: "#setup-add-media-dir-form input[name='dir']")
        }
        class="flex gap-2 items-center"
      >
        <input
          type="text"
          name="dir"
          placeholder="/absolute/path/to/your/media"
          class="input input-bordered input-sm flex-1 font-mono text-sm"
          required
          data-nav-item
          tabindex="0"
        />
        <.button type="submit" variant="primary" size="sm" data-nav-item tabindex="0">
          Add
        </.button>
      </form>
    </.step_shell>
    """
  end

  defp dirs_list(%Probe.Result{current_value: nil}), do: []

  defp dirs_list(%Probe.Result{current_value: entries}) when is_list(entries) do
    Enum.map(entries, & &1["dir"])
  end

  # ---------------------------------------------------------------------------
  # Welcome step — first step in the tour, no probe
  # ---------------------------------------------------------------------------

  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true

  def welcome_step(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-6 max-w-2xl mx-auto" data-nav-zone="grid">
      <header class="mb-5">
        <h2 class="text-2xl font-bold tracking-tight">Welcome to Media Centaur</h2>
        <p class="mt-1 text-sm text-base-content/60">Let's get the basics configured.</p>
      </header>

      <p class="text-sm text-base-content/70 mb-5 max-w-[60ch]">
        This short tour points Media Centaur at your media, metadata, and player.
        Media directories and TMDB are required — the rest is optional and can be
        set up later from <span class="font-medium text-base-content/90">Settings</span>.
      </p>

      <div class="glass-inset rounded-lg p-4 mb-5">
        <p class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-2">
          What the tour covers
        </p>
        <ol class="space-y-1.5 text-sm text-base-content/70">
          <li>
            <span class="font-medium text-base-content/90">Media directories</span>
            — where your files live
          </li>
          <li>
            <span class="font-medium text-base-content/90">TMDB</span> — metadata, posters, tracking
          </li>
          <li><span class="font-medium text-base-content/90">mpv</span> — the media player</li>
          <li>
            <span class="font-medium text-base-content/90">ffprobe</span>
            <span class="text-base-content/40">(optional)</span> — embedded subtitles
          </li>
          <li>
            <span class="font-medium text-base-content/90">Prowlarr</span>
            <span class="text-base-content/40">(optional)</span> — in-app search
          </li>
          <li>
            <span class="font-medium text-base-content/90">Download client</span>
            <span class="text-base-content/40">(optional)</span> — grab progress
          </li>
        </ol>
      </div>

      <footer class="flex justify-end mt-6 pt-4 border-t border-base-content/10">
        <.button variant="primary" size="sm" phx-click="setup:next" data-nav-item tabindex="0">
          Begin
        </.button>
      </footer>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Summary step — last step in the tour, shows every probe's state
  # ---------------------------------------------------------------------------

  attr :probes, :list,
    required: true,
    doc:
      "list of `MediaCentaurWeb.Live.SetupLive.Probe.Result.t()` rows in step order. The summary step renders one row per probe; struct-typed attrs would require declaring an attr type per element which Phoenix.Component doesn't support."

  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true

  def summary_step(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-6 max-w-2xl mx-auto" data-nav-zone="grid">
      <header class="mb-5">
        <h2 class="text-2xl font-bold tracking-tight">Setup summary</h2>
        <p class="mt-1 text-sm text-base-content/60">
          {summary_headline(@probes)}
        </p>
      </header>

      <ul class="divide-y divide-base-content/10 mb-5">
        <li :for={probe <- @probes} class="py-3 flex items-start justify-between gap-3">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <.summary_glyph status={probe.status} />
              <p class="font-medium">{Content.for(probe.id).title}</p>
              <.badge :if={probe.critical?} variant="error" size="xs">Required</.badge>
            </div>
            <p :if={probe.detail} class="text-xs text-base-content/60 mt-1 ml-7">{probe.detail}</p>
          </div>
          <.button
            variant="dismiss"
            size="xs"
            patch={"/setup?step=" <> Atom.to_string(probe.id)}
            data-nav-item
            tabindex="0"
          >
            Edit
          </.button>
        </li>
      </ul>

      <footer class="flex justify-between mt-6 pt-4 border-t border-base-content/10">
        <.button variant="dismiss" size="sm" phx-click="setup:back" data-nav-item tabindex="0">
          Back
        </.button>
        <.button variant="primary" size="sm" phx-click="setup:next" data-nav-item tabindex="0">
          Finish
        </.button>
      </footer>
    </section>
    """
  end

  defp summary_headline(probes) do
    total = length(probes)
    ok = Enum.count(probes, &(&1.status == :ok))
    critical_unmet = Enum.count(probes, &(&1.critical? and &1.status != :ok))

    cond do
      ok == total -> "Everything is configured."
      critical_unmet > 0 -> "#{critical_unmet} required step(s) still incomplete."
      true -> "#{ok} of #{total} configured. The rest are optional."
    end
  end

  attr :status, :atom, required: true

  defp summary_glyph(assigns) do
    {icon, class} =
      case assigns.status do
        :ok -> {"hero-check-circle-mini", "text-success"}
        :warning -> {"hero-exclamation-triangle-mini", "text-warning"}
        :error -> {"hero-x-circle-mini", "text-error"}
        :not_configured -> {"hero-minus-circle-mini", "text-base-content/40"}
      end

    assigns = assign(assigns, icon: icon, class: class)

    ~H"""
    <.icon name={@icon} class={"size-5 shrink-0 #{@class}"} />
    """
  end
end
