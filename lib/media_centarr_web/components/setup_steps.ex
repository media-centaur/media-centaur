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

  alias MediaCentarrWeb.Live.SetupLive.Probe

  # ---------------------------------------------------------------------------
  # Shared chrome — used by all three step variants
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :title, :string, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true
  slot :inner_block, required: true

  defp step_shell(assigns) do
    ~H"""
    <section class="card glass-surface p-6 max-w-2xl mx-auto">
      <header class="flex items-baseline justify-between mb-4">
        <div>
          <p class="text-xs uppercase tracking-wide opacity-60">
            Step {@step_index} of {@total_steps}
          </p>
          <h2 class="text-2xl font-semibold mt-1">{@title}</h2>
        </div>
        <.status_pill status={@result.status} />
      </header>

      <p :if={@result.detail} class="text-sm opacity-80 mb-4">
        {@result.detail}
      </p>

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

  # ---------------------------------------------------------------------------
  # Binary step — mpv, ffprobe
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :title, :string, required: true
  attr :binary_name, :string, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true

  def binary_step(assigns) do
    ~H"""
    <.step_shell
      result={@result}
      title={@title}
      step_index={@step_index}
      total_steps={@total_steps}
    >
      <form
        phx-submit="setup:save_path"
        phx-value-id={@result.id}
        class="flex gap-2 items-stretch"
      >
        <input
          type="text"
          name="path"
          value={@result.current_value || ""}
          placeholder={"/usr/bin/" <> @binary_name}
          class="input input-bordered flex-1 font-mono text-sm"
        />
        <.button type="submit" variant="primary" size="sm">Save</.button>
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
          found on this system. Install it via your OS package manager and click "Re-check".
        </span>
      </div>

      <.button
        variant="dismiss"
        size="sm"
        class="self-start"
        phx-click="setup:recheck"
        phx-value-id={@result.id}
      >
        Re-check
      </.button>
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
  attr :title, :string, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true
  slot :form, required: true, doc: "Settings form fields specific to this integration"

  def integration_step(assigns) do
    ~H"""
    <.step_shell
      result={@result}
      title={@title}
      step_index={@step_index}
      total_steps={@total_steps}
    >
      <div class="space-y-3">
        {render_slot(@form)}
      </div>

      <.button
        variant="dismiss"
        size="sm"
        class="self-start"
        phx-click="setup:test_connection"
        phx-value-id={@result.id}
      >
        Test connection
      </.button>
    </.step_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Watch dirs step
  # ---------------------------------------------------------------------------

  attr :result, Probe.Result, required: true
  attr :title, :string, required: true
  attr :step_index, :integer, required: true
  attr :total_steps, :integer, required: true

  def watch_dirs_step(assigns) do
    ~H"""
    <.step_shell
      result={@result}
      title={@title}
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

      <form phx-submit="setup:add_watch_dir" class="flex gap-2 items-stretch">
        <input
          type="text"
          name="dir"
          placeholder="/mnt/media/movies"
          class="input input-bordered flex-1 font-mono text-sm"
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
end
