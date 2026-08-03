defmodule MediaCentaurWeb.Components.Incoming.Ledger do
  @moduledoc """
  The History archive — the History tab's whole content, always open:
  lifecycle filter chips (`set_history_filter`, `:all` leading and
  default), title/release search (`set_history_search`), and the
  grouped terminal rows in the quiet ledger vocabulary. No glimpse and
  no disclosure — the zone tab already did the quieting the old
  shared-page treatment existed for. No section header either: the tab
  says History.

  Rows arrive pre-bucketed into date sections (`HistoryLogic.
  section_entries/2` — Today / Yesterday / This week / month names) so
  a long archive scans by time landmark. Rows speak outcome-first:
  severity dot, title (episode clusters as a `toggle_pursuit_group`
  disclosure, members within), the composite "N of M" chip where it
  exists, one colored outcome word, relative time. The status
  *sentence* renders only where it informs — failures and partials
  carry their diagnostics; "Landed"/"Cancelled" need no elaboration.
  Clicking a row opens the pursuit modal (`select_pursuit`), same
  contract as the In-flight cards.

  The archive renders a bounded window; when the archive holds more,
  a quiet Show older row (`history_show_older`) widens it. Storage
  sits as the ambient foot line, reusing
  `DownloadStorage.calm_summary/1`. An empty archive renders the
  filter-specific honest answer (`HistoryLogic.empty_state/1`) under
  the chips — the chips stay so widening the filter stays possible.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [badge: 1, button: 1, icon: 1]

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Acquisition.DownloadStorage
  alias MediaCentaurWeb.IncomingLive.HistoryLogic

  attr :sections, :list,
    default: [],
    doc:
      "Date-bucketed archive entries (`HistoryLogic.section_entries/2` shape): " <>
        "`{label, entries}` where each entry is `{:single, PursuitRow.t()}` or " <>
        "`{:group, %{title, state, awaiting?, count, verb, severity, vms, expanded?}}`."

  attr :filter, :atom,
    default: :all,
    doc: "Lifecycle filter (see `HistoryLogic.filter_atoms/0`) — `:all` is the tab's face."

  attr :search, :string, default: "", doc: "Title/release search needle."

  attr :has_older?, :boolean,
    default: false,
    doc: "The archive holds rows past the window — renders the Show older row."

  attr :storage_drives, :list,
    default: [],
    doc:
      "Media-dir drive maps (`Storage.measure_all/0` shape) — the foot line renders `DownloadStorage.calm_summary/1` when it has one to give."

  def ledger(assigns) do
    assigns = assign(assigns, :storage_summary, DownloadStorage.calm_summary(assigns.storage_drives))

    ~H"""
    <%!-- Centered at a readable measure, like the agenda: quiet rows are
          scanned title→outcome, and a full-bleed row puts a thousand
          pixels of nothing between the two. --%>
    <section
      data-component="incoming-ledger"
      data-nav-zone="ledger"
      class="mx-auto w-full max-w-4xl space-y-3"
    >
      <div class="flex flex-wrap items-center gap-2">
        <button
          :for={filter_atom <- HistoryLogic.filter_atoms()}
          phx-click="set_history_filter"
          phx-value-filter={Atom.to_string(filter_atom)}
          class={[
            "btn btn-sm",
            @filter == filter_atom && "btn-primary",
            @filter != filter_atom && "btn-ghost"
          ]}
          data-nav-item
          tabindex="0"
        >
          {HistoryLogic.filter_label(filter_atom)}
        </button>

        <form phx-change="set_history_search" class="ml-auto">
          <input
            type="search"
            name="search"
            value={@search}
            placeholder="Filter by title or release…"
            class="input input-bordered input-sm w-64"
            data-nav-item
            tabindex="0"
          />
        </form>
      </div>

      <div
        :if={@sections == []}
        class="scrim-surface rounded-xl px-4 py-6 text-center text-sm text-base-content/40"
      >
        {HistoryLogic.empty_state(@filter)}
      </div>

      <div :if={@sections != []} class="space-y-4">
        <div :for={{label, entries} <- @sections}>
          <h3 class="pb-1 text-xs font-medium uppercase tracking-wider text-base-content/40">
            {label}
          </h3>
          <%= for entry <- entries do %>
            <%= case entry do %>
              <% {:single, vm} -> %>
                <.history_row vm={vm} />
              <% {:group, data} -> %>
                <.history_group data={data} />
            <% end %>
          <% end %>
        </div>

        <div :if={@has_older?} class="flex justify-center pt-1">
          <.button
            variant="dismiss"
            size="sm"
            phx-click="history_show_older"
            data-nav-item
            tabindex="0"
          >
            Show older
          </.button>
        </div>
      </div>

      <div :if={@storage_summary} class="flex items-center justify-end px-1">
        <span class="inline-flex items-center gap-1.5 text-xs text-base-content/35">
          <.icon name="hero-circle-stack-mini" class="size-3.5" /> {@storage_summary}
        </span>
      </div>
    </section>
    """
  end

  attr :vm, PursuitRow, required: true
  attr :indent, :boolean, default: false, doc: "Group member — inset under its disclosure row."

  defp history_row(assigns) do
    ~H"""
    <div
      id={"history-row-#{@vm.id}"}
      class={[
        "grid cursor-pointer grid-cols-[10px_minmax(0,1fr)_auto_auto] items-baseline gap-3 rounded px-1 py-1.5 text-sm text-base-content/80 transition-colors hover:bg-base-content/[0.04]",
        @indent && "ml-6"
      ]}
      role="button"
      data-pursuit-id={@vm.id}
      phx-click="select_pursuit"
      phx-value-id={@vm.id}
      data-nav-item
      tabindex="0"
    >
      <span class={["size-[7px] self-center rounded-full", dot_class(@vm.state)]} />
      <span class="min-w-0 truncate">
        {display_title(@vm)}
        <span
          :if={@vm.door == :query}
          class="ml-2 text-[10px] uppercase tracking-wider text-base-content/30"
        >
          release search
        </span>
        <.badge :if={@vm.units_wanted > 1} variant="ghost" class="ml-2 tabular-nums">
          {@vm.units_satisfied} of {@vm.units_wanted}
        </.badge>
        <%!-- The sentence only where it informs — failures and partials
              carry diagnostics; Landed/Cancelled already said it. --%>
        <span :if={@vm.state in [:exhausted, :partial]} class="ml-2 text-xs text-base-content/50">
          {@vm.status.verb} — {@vm.status.description}
        </span>
      </span>
      <span class={["whitespace-nowrap text-xs", outcome_class(@vm.state)]}>
        {outcome_label(@vm.state)}
      </span>
      <span class="min-w-20 whitespace-nowrap text-right text-xs text-base-content/35">
        {when_label(@vm)}
      </span>
    </div>
    """
  end

  attr :data, :map,
    required: true,
    doc: "One `Logic.group_pursuit_rows/2` group — title/state/awaiting?/count/vms/expanded?."

  # An episode cluster: same quiet grid as a row, with the disclosure
  # chevron in the dot column and the newest member's time on the right —
  # the same instant `HistoryLogic.section_entries/2` buckets it by.
  defp history_group(assigns) do
    assigns = assign(assigns, :latest, HistoryLogic.latest_time(assigns.data.vms))

    ~H"""
    <div
      class="grid cursor-pointer grid-cols-[10px_minmax(0,1fr)_auto_auto_auto] items-baseline gap-3 rounded px-1 py-1.5 text-sm text-base-content/80 transition-colors hover:bg-base-content/[0.04]"
      role="button"
      phx-click="toggle_pursuit_group"
      phx-value-title={@data.title}
      phx-value-state={Atom.to_string(@data.state)}
      phx-value-awaiting={to_string(@data.awaiting?)}
      data-nav-item
      tabindex="0"
    >
      <.icon
        name={if @data.expanded?, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
        class="size-3.5 self-center text-base-content/40"
      />
      <span class="min-w-0 truncate">{@data.title}</span>
      <span class="whitespace-nowrap text-xs tabular-nums text-base-content/50">
        {@data.count} {episode_word(@data.count)}
      </span>
      <span class={["whitespace-nowrap text-xs", outcome_class(@data.state)]}>
        {outcome_label(@data.state)}
      </span>
      <span class="min-w-20 whitespace-nowrap text-right text-xs text-base-content/35">
        {if @latest, do: Format.relative_ago(@latest)}
      </span>
    </div>
    <div :if={@data.expanded?}>
      <.history_row :for={vm <- @data.vms} vm={vm} indent />
    </div>
    """
  end

  defp episode_word(1), do: "episode"
  defp episode_word(_count), do: "episodes"

  defp dot_class(:satisfied), do: "bg-success"
  defp dot_class(:partial), do: "bg-warning"
  defp dot_class(:exhausted), do: "bg-error"
  defp dot_class(_state), do: "bg-base-content/25"

  defp outcome_label(:satisfied), do: "Landed"
  defp outcome_label(:partial), do: "Partly landed"
  defp outcome_label(:exhausted), do: "Failed"
  defp outcome_label(:cancelled), do: "Cancelled"
  defp outcome_label(state), do: Phoenix.Naming.humanize(state)

  defp outcome_class(:satisfied), do: "text-success/85"
  defp outcome_class(:partial), do: "text-warning/90"
  defp outcome_class(:exhausted), do: "text-error/90"
  defp outcome_class(_state), do: "text-base-content/35"

  defp when_label(%PursuitRow{updated_at: %DateTime{} = at}), do: Format.relative_ago(at)
  defp when_label(%PursuitRow{}), do: nil

  defp display_title(%PursuitRow{title: title, season_number: season, episode_number: episode}) do
    case Format.episode_label(season, episode) do
      "" -> title
      label -> "#{title} #{label}"
    end
  end
end
