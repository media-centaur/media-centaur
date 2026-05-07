defmodule MediaCentarrWeb.Components.SetupSteps do
  @moduledoc """
  Stateless renderers for each step in the Setup Tour wizard.

  Three components, one per step shape:

  - `binary_step/1` — mpv, ffprobe (path field + auto-detected candidates)
  - `integration_step/1` — TMDB, Prowlarr, download client (form fields + test button)
  - `watch_dirs_step/1` — directory list with add/remove

  All three accept a typed `%Probe.Result{}` and emit events with
  `phx-value-id={@result.id}` so the parent LiveView routes the event by
  probe id rather than per-step handlers.

  Logic stays here as much as possible (status pills, candidate
  formatting); the LiveView handles persistence and connection tests.
  """

  use MediaCentarrWeb, :html

  alias MediaCentarrWeb.Live.SetupLive.{Content, Probe}

  # ---------------------------------------------------------------------------
  # Shared chrome — used by all three step variants
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :content, Content, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true
  slot :inner_block, required: true

  defp step_shell(assigns) do
    ~H"""
    <section class="card glass-surface p-6 max-w-2xl mx-auto">
      <header class="mb-4">
        <div class="flex items-baseline justify-between gap-3 mb-2">
          <p class="text-xs uppercase tracking-wide opacity-60">
            Step {@step_index} of {@total_steps}
          </p>
          <.status_pill status={@result.status} />
        </div>
        <h2 class="text-2xl font-semibold">{@content.title}</h2>
        <p class="text-sm opacity-70 mt-1">{@content.short}</p>
      </header>

      <div class="space-y-3 text-sm mb-5 p-4 rounded bg-base-content/5">
        <div>
          <p class="font-semibold mb-1">What this is</p>
          <p class="opacity-80">{@content.what}</p>
        </div>
        <div>
          <p class="font-semibold mb-1">Why it matters</p>
          <p class="opacity-80">{@content.why}</p>
        </div>
        <div>
          <p class="font-semibold mb-1">What you'll need</p>
          <ul class="list-disc list-inside opacity-80 space-y-1">
            <li :for={req <- @content.requirements}>{req}</li>
          </ul>
        </div>
      </div>

      <.status_callout result={@result} />

      <div class="space-y-3">
        {render_slot(@inner_block)}
      </div>

      <footer class="flex justify-between mt-6 pt-4 border-t border-base-content/10">
        <.button
          variant="dismiss"
          size="sm"
          phx-click="setup:back"
          disabled={@step_index == 1}
        >
          Back
        </.button>
        <div class="flex gap-2">
          <.button variant="dismiss" size="sm" phx-click="setup:skip">
            Skip
          </.button>
          <.button variant="primary" size="sm" phx-click="setup:next">
            {if @step_index == @total_steps, do: "Finish", else: "Next"}
          </.button>
        </div>
      </footer>
    </section>
    """
  end

  attr :status, :atom, required: true

  defp status_pill(assigns) do
    {label, variant} =
      case assigns.status do
        :ok -> {"OK", "success"}
        :warning -> {"Warning", "warning"}
        :error -> {"Error", "error"}
        :not_configured -> {"Not configured", "ghost"}
      end

    assigns = assign(assigns, label: label, variant: variant)

    ~H"""
    <.badge variant={@variant}>{@label}</.badge>
    """
  end

  attr :result, Probe.Result, required: true

  # Big, color-coded callout block immediately above the step's
  # form/inputs. Makes met/unmet state obvious at a glance — the small
  # header pill is for at-a-glance scanning, this one is for clarity.
  defp status_callout(assigns) do
    {glyph, headline, classes} =
      case assigns.result.status do
        :ok ->
          {"✓", "This step is configured.", "border-success/40 bg-success/10 text-success"}

        :warning ->
          {"!", "Partially configured.", "border-warning/40 bg-warning/10 text-warning"}

        :error ->
          {"✗", "This step needs attention.", "border-error/40 bg-error/10 text-error"}

        :not_configured ->
          {"…", "Not yet configured.", "border-base-content/20 bg-base-content/5 opacity-90"}
      end

    assigns = assign(assigns, glyph: glyph, headline: headline, classes: classes)

    ~H"""
    <div class={["mb-4 p-3 rounded-lg border flex items-start gap-3", @classes]}>
      <span class="text-xl font-bold leading-none mt-0.5">{@glyph}</span>
      <div class="flex-1 min-w-0">
        <p class="font-semibold">{@headline}</p>
        <p :if={@result.detail} class="text-sm opacity-90 mt-0.5">{@result.detail}</p>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Binary step — mpv, ffprobe
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :content, Content, required: true
  attr :binary_name, :string, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true

  def binary_step(assigns) do
    ~H"""
    <.step_shell
      result={@result}
      content={@content}
      step_index={@step_index}
      total_steps={@total_steps}
    >
      <form
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
        />
        <.button type="submit" variant="primary" size="sm">
          {save_label(@result)}
        </.button>
        <.button
          variant="outline"
          size="sm"
          phx-click="setup:recheck"
          phx-value-id={@result.id}
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

  # Save vs Update — communicates whether the user is creating new
  # state or modifying existing state.
  defp save_label(%Probe.Result{current_value: nil}), do: "Save"
  defp save_label(%Probe.Result{current_value: ""}), do: "Save"
  defp save_label(%Probe.Result{}), do: "Update"

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
  slot :form, required: true, doc: "Settings form fields specific to this integration"

  def integration_step(assigns) do
    ~H"""
    <.step_shell
      result={@result}
      content={@content}
      step_index={@step_index}
      total_steps={@total_steps}
    >
      <div class="space-y-3">
        {render_slot(@form)}
      </div>
    </.step_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Watch dirs step
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :content, Content, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true

  def watch_dirs_step(assigns) do
    ~H"""
    <.step_shell
      result={@result}
      content={@content}
      step_index={@step_index}
      total_steps={@total_steps}
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
            phx-click="setup:remove_watch_dir"
            phx-value-dir={dir}
          >
            Remove
          </.button>
        </li>
      </ul>

      <p :if={dirs_list(@result) == []} class="text-sm opacity-70 italic">
        No watch directories yet — add one below.
      </p>

      <form phx-submit="setup:add_watch_dir" class="flex gap-2 items-center">
        <input
          type="text"
          name="dir"
          placeholder="/mnt/media/movies"
          class="input input-bordered input-sm flex-1 font-mono text-sm"
          required
        />
        <.button type="submit" variant="primary" size="sm">Add</.button>
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
    <section class="card glass-surface p-6 max-w-2xl mx-auto">
      <header class="mb-4">
        <p class="text-xs uppercase tracking-wide opacity-60">
          Step {@step_index} of {@total_steps}
        </p>
        <h2 class="text-2xl font-semibold mt-1">Welcome to Media Centarr</h2>
        <p class="text-sm opacity-70 mt-1">Let's get the basics configured.</p>
      </header>

      <div class="space-y-4 text-sm mb-5">
        <p class="opacity-80">
          Media Centarr identifies the videos in your library, fetches metadata and artwork from TMDB, plays files in mpv, and (optionally) coordinates downloads through Prowlarr. This short tour walks you through each piece.
        </p>

        <div class="p-4 rounded bg-base-content/5">
          <p class="font-semibold mb-2">What this tour covers</p>
          <ol class="list-decimal list-inside opacity-80 space-y-1">
            <li><span class="font-medium">Watch directories</span> — where your video files live.</li>
            <li><span class="font-medium">TMDB</span> — metadata, posters, release tracking.</li>
            <li><span class="font-medium">mpv</span> — the media player.</li>
            <li><span class="font-medium">ffprobe</span> — embedded subtitle detection.</li>
            <li>
              <span class="font-medium">Prowlarr</span> <span class="opacity-60">(optional)</span>
              — in-app indexer search.
            </li>
            <li>
              <span class="font-medium">Download client</span>
              <span class="opacity-60">(optional)</span> — track grab progress.
            </li>
            <li>
              <span class="font-medium">Summary</span> — review what's done and what's still missing.
            </li>
          </ol>
        </div>

        <p class="opacity-80">
          Every step is skippable. You can finish the tour with anything still unconfigured and come back later via <span class="font-medium">Settings → Overview → Run setup tour</span>.
        </p>
      </div>

      <footer class="flex justify-end mt-6 pt-4 border-t border-base-content/10">
        <.button variant="primary" size="sm" phx-click="setup:next">
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
      "list of `MediaCentarrWeb.Live.SetupLive.Probe.Result.t()` rows in step order. The summary step renders one row per probe; struct-typed attrs would require declaring an attr type per element which Phoenix.Component doesn't support."

  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true

  def summary_step(assigns) do
    ~H"""
    <section class="card glass-surface p-6 max-w-2xl mx-auto">
      <header class="mb-4">
        <p class="text-xs uppercase tracking-wide opacity-60">
          Step {@step_index} of {@total_steps}
        </p>
        <h2 class="text-2xl font-semibold mt-1">Setup summary</h2>
        <p class="text-sm opacity-70 mt-1">
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
            <p :if={probe.detail} class="text-xs opacity-70 mt-1 ml-6">{probe.detail}</p>
          </div>
          <.button
            variant="dismiss"
            size="xs"
            patch={"/setup?step=" <> Atom.to_string(probe.id)}
          >
            Edit
          </.button>
        </li>
      </ul>

      <footer class="flex justify-between mt-6 pt-4 border-t border-base-content/10">
        <.button variant="dismiss" size="sm" phx-click="setup:back">
          Back
        </.button>
        <.button variant="primary" size="sm" phx-click="setup:next">
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
    {char, class} =
      case assigns.status do
        :ok -> {"✓", "text-success"}
        :warning -> {"!", "text-warning"}
        :error -> {"✗", "text-error"}
        :not_configured -> {"—", "opacity-50"}
      end

    assigns = assign(assigns, char: char, class: class)

    ~H"""
    <span class={["font-bold", @class]}>{@char}</span>
    """
  end
end
