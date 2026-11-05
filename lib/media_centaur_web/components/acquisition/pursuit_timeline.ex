defmodule MediaCentaurWeb.Components.Acquisition.PursuitTimeline do
  @moduledoc """
  History: the pursuit's events as runs, newest first (`ViewModels.Timeline`).

  The newest six runs are always drawn. Everything older sits behind one
  disclosure — "Show the full log" — owned by the page's `DisclosureState`
  under `history-log-<pursuit id>`, and inside it a page of runs at a time:
  the host's `shown` counts the pages Show more has added beyond the first
  (`Timeline.page/0` each). The DOM therefore holds a bounded number of
  rows however long the history is (UIDR-056).

  A run's row: the summary with its count when more than one, the episodes
  the events named, the release, the client's words, and the newest time
  (the span and count as its tip). Every row is a nav item, so keyboard
  and gamepad walk the history and the modal scrolls it into view; Show
  more returns the cursor to the row it came from (`data-nav-return-focus`).
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Disclosure
  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias MediaCentaur.Acquisition.ViewModels.Timeline
  alias MediaCentaur.Acquisition.ViewModels.Timeline.Run
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Acquisition.PursuitStyle
  alias MediaCentaurWeb.Live.DisclosureState

  attr :vm, Timeline, required: true
  attr :shown, :integer, default: 0, doc: "older runs revealed by Show more, beyond the first page."
  attr :disclosures, MapSet, default: MapSet.new(), doc: "the page's `DisclosureState`."
  attr :on_show_more, :string, default: "show_more_history"

  def timeline(assigns) do
    log_id = "history-log-#{assigns.vm.pursuit_id}"
    visible = Timeline.page() + assigns.shown
    remaining = max(length(assigns.vm.rest) - visible, 0)

    assigns =
      assign(assigns,
        log_id: log_id,
        log_open?: DisclosureState.open?(assigns.disclosures, log_id),
        log_rows: Enum.take(assigns.vm.rest, visible),
        remaining: remaining
      )

    ~H"""
    <%!-- Flat section inside the modal panel. See `pursuit_header.ex`
          for the rationale. --%>
    <div data-nav-zone="pursuit_history" class="space-y-3">
      <div class="flex items-baseline justify-between gap-3">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/55">History</h3>
        <span :if={@vm.total_events > 0} class="text-xs text-base-content/60 tabular-nums">
          {@vm.total_events} {if @vm.total_events == 1, do: "event", else: "events"}
        </span>
      </div>

      <div :if={@vm.recent == []} class="text-sm text-base-content/55">No events yet.</div>

      <ol :if={@vm.recent != []} class="space-y-3">
        <.run_row
          :for={{run, index} <- Enum.with_index(@vm.recent)}
          id={"history-#{@vm.pursuit_id}-recent-#{index}"}
          run={run}
        />
      </ol>

      <.disclosure
        :if={@vm.rest != []}
        id={@log_id}
        open={@log_open?}
        variant={:quiet}
        label={"Show the full log — #{@vm.total_events} events in #{@vm.total_runs} rows"}
      >
        <ol class="space-y-3 pt-2">
          <.run_row
            :for={{run, index} <- Enum.with_index(@log_rows)}
            id={"history-#{@vm.pursuit_id}-log-#{index}"}
            run={run}
          />
        </ol>
        <div :if={@remaining > 0} class="pt-3">
          <.button
            variant="neutral"
            size="sm"
            phx-click={@on_show_more}
            data-nav-item
            data-nav-return-focus
            tabindex="0"
          >
            Show more ({@remaining} more)
          </.button>
        </div>
      </.disclosure>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :run, Run, required: true

  defp run_row(assigns) do
    ~H"""
    <li id={@id} class="flex items-start gap-3 rounded-md" data-nav-item tabindex="0">
      <span class={"mt-1 block size-2 rounded-full flex-shrink-0 #{PursuitStyle.severity_dot_class(@run.entry.severity)}"} />
      <div class="min-w-0 flex-1">
        <div class={"text-sm #{PursuitStyle.severity_text_class(@run.entry.severity)}"}>
          {@run.entry.summary}
          <span :if={@run.count > 1} class="ml-1.5 text-xs text-base-content/55 tabular-nums">
            ×{@run.count}
          </span>
        </div>
        <div :if={@run.subjects != []} class="text-xs text-base-content/60">
          {subjects_label(@run.subjects)}
        </div>
        <div
          :if={@run.release}
          class="text-xs font-mono text-base-content/55 truncate"
          data-tip={@run.release}
        >
          {@run.release}
        </div>
        <div
          :if={@run.entry.detail}
          class="text-xs text-base-content/55 truncate"
          data-tip={@run.entry.detail}
        >
          {@run.entry.detail}
        </div>
        <div class="text-xs text-base-content/55 mt-0.5" data-tip={time_tip(@run)}>
          {Format.relative_ago(@run.last_at)}
        </div>
      </div>
    </li>
    """
  end

  # Up to three episodes by name; more read as a count.
  defp subjects_label(subjects) when length(subjects) <= 3, do: Enum.join(subjects, ", ")
  defp subjects_label(subjects), do: "#{length(subjects)} episodes"

  defp time_tip(%Run{count: 1, last_at: at}), do: format_time(at)

  defp time_tip(%Run{count: count, first_at: first, last_at: last}),
    do: "#{format_time(first)} – #{format_time(last)} · #{count} events"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
