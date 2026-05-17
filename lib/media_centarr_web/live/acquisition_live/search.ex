defmodule MediaCentarrWeb.AcquisitionLive.Search do
  @moduledoc """
  Search zone of the unified Downloads page — Prowlarr brace-expansion
  query form, expansion preview, group rendering, and the bulk-grab
  footer. Pure function component; all events bubble to the parent
  `AcquisitionLive` (`submit_search`, `query_change`, `toggle_group`,
  `select_result`, `retry_search`, `retry_all_timeouts`, `grab_selected`).
  """
  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [button: 1, icon: 1]

  alias MediaCentarr.Search.Quality
  alias MediaCentarr.Search.SearchSession
  alias MediaCentarrWeb.AcquisitionLive.Logic

  attr :session, SearchSession, required: true
  attr :any_loading?, :boolean, required: true

  attr :timeout_terms, :list,
    required: true,
    doc: "List of group-term strings whose Prowlarr request timed out — eligible for bulk retry."

  def search_zone(assigns) do
    ~H"""
    <section data-nav-zone="search" class="glass-surface rounded-xl p-4 space-y-3">
      <form
        phx-change="query_change"
        phx-submit="submit_search"
        onsubmit="this.querySelector('button[type=submit]').focus()"
        class="flex gap-3 items-end"
      >
        <div class="flex-1">
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Query
          </label>
          <input
            type="text"
            name="query"
            value={@session.query}
            class="input input-bordered w-full font-mono text-sm"
            placeholder="Title S01E{01-10}"
            autofocus
            phx-debounce="200"
            data-nav-item
            data-captures-keys
            tabindex="0"
            onkeydown="if (event.key === 'Escape') { event.preventDefault(); this.form.querySelector('button[type=submit]').focus() }"
          />
        </div>
        <.button
          type="submit"
          variant="secondary"
          disabled={expansion_blocked?(@session.expansion_preview)}
          data-nav-item
          tabindex="0"
        >
          <span :if={@any_loading?} class="loading loading-spinner loading-sm"></span>
          <.icon :if={!@any_loading?} name="hero-magnifying-glass" class="size-4" /> Search
        </.button>
      </form>

      <div class="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs">
        <span class="text-base-content/40">Syntax:</span>
        <span class="flex items-center gap-2">
          <span class="text-base-content/50">List</span>
          <code class="font-mono px-2 py-0.5 rounded bg-base-content/10 text-base-content/70">
            {"{a,b,c}"}
          </code>
        </span>
        <span class="flex items-center gap-2">
          <span class="text-base-content/50">Range</span>
          <code class="font-mono px-2 py-0.5 rounded bg-base-content/10 text-base-content/70">
            {"{00-09}"}
          </code>
        </span>
        <span class="text-base-content/30">— each expansion runs as its own search</span>
      </div>

      <p class={["text-xs", expansion_color(@session.expansion_preview)]}>
        {expansion_text(@session.expansion_preview)}
      </p>
    </section>

    <div
      :if={@session.grab_message}
      class={[
        "glass-inset rounded-lg px-4 py-3 text-sm flex items-center gap-2",
        grab_message_color(@session.grab_message)
      ]}
    >
      <.icon name={grab_message_icon(@session.grab_message)} class="size-4 shrink-0" />
      {grab_message_text(@session.grab_message)}
    </div>

    <section :if={@session.groups != []} data-nav-zone="grid" class="space-y-3">
      <div :for={group <- @session.groups} class="space-y-1">
        <.group_header group={group} />
        <.group_actions :if={action_visible?(group)} group={group} />
        <.group_alternatives
          :if={group.expanded? && group.results != []}
          group={group}
          session={@session}
        />
      </div>
      <.results_footer
        any_loading?={@any_loading?}
        timeout_terms={@timeout_terms}
        session={@session}
      />
    </section>
    """
  end

  attr :group, :map,
    required: true,
    doc: "One `SearchSession.group()` map — `term/status/results/expanded?/featured` shape; no struct."

  defp group_header(assigns) do
    ~H"""
    <button
      type="button"
      class="glass-surface rounded-lg w-full px-4 py-3 flex items-center gap-3 text-left hover:bg-base-content/5"
      phx-click="toggle_group"
      phx-value-term={@group.term}
      data-nav-item
      tabindex="0"
    >
      <.icon
        name={if @group.expanded?, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
        class="size-4 shrink-0 text-base-content/40"
      />
      <span class="text-xs font-medium text-base-content/50 w-32 shrink-0 truncate">
        {@group.term}
      </span>
      <.group_status_summary group={@group} />
    </button>
    """
  end

  attr :group, :map,
    required: true,
    doc: "One `SearchSession.group()` map — `term/status/results/expanded?/featured` shape; no struct."

  defp group_status_summary(%{group: %{status: :loading}} = assigns) do
    ~H"""
    <span class="loading loading-spinner loading-xs text-base-content/40"></span>
    <span class="flex-1 text-sm text-base-content/40">Searching…</span>
    """
  end

  defp group_status_summary(%{group: %{status: {:failed, _reason}}} = assigns) do
    ~H"""
    <span class="flex-1 text-sm text-error/70">
      {Logic.format_search_error(elem(@group.status, 1))}
    </span>
    """
  end

  defp group_status_summary(%{group: %{status: :abandoned}} = assigns) do
    ~H"""
    <span class="flex-1 text-sm text-base-content/40">
      Search was interrupted — Retry to resume
    </span>
    """
  end

  defp group_status_summary(%{group: %{status: :ready, results: []}} = assigns) do
    ~H"""
    <span class="flex-1 text-sm text-base-content/40">No results</span>
    """
  end

  defp group_status_summary(%{group: %{status: :ready, results: [_ | _]}} = assigns) do
    ~H"""
    <span class={["text-xs font-bold w-10 shrink-0", quality_color(@group.featured.quality)]}>
      {Quality.label(@group.featured.quality)}
    </span>
    <span class="flex-1 min-w-0 text-sm truncate" title={@group.featured.title}>
      {@group.featured.title}
    </span>
    <span
      :if={@group.featured.size_bytes}
      class="text-xs tabular-nums shrink-0 text-base-content/60"
    >
      {format_bytes(@group.featured.size_bytes)}
    </span>
    <span
      :if={@group.featured.seeders}
      class={["text-xs tabular-nums shrink-0", seeder_color(@group.featured.seeders)]}
    >
      {@group.featured.seeders}S
    </span>
    """
  end

  attr :group, :map,
    required: true,
    doc: "One `SearchSession.group()` map — `term/status/results/expanded?/featured` shape; no struct."

  defp group_actions(assigns) do
    ~H"""
    <div class="pl-44 flex items-center gap-2">
      <.button
        variant="risky"
        size="xs"
        phx-click="retry_search"
        phx-value-term={@group.term}
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-arrow-path-mini" class="size-3" /> Retry
      </.button>
      <.button
        :if={match?({:failed, _}, @group.status)}
        variant="secondary"
        size="xs"
        patch="/settings?section=acquisition"
        data-nav-item
        tabindex="0"
      >
        Open Prowlarr settings <.icon name="hero-chevron-right-mini" class="size-3" />
      </.button>
    </div>
    """
  end

  attr :group, :map,
    required: true,
    doc: "One `SearchSession.group()` map — `term/status/results/expanded?/featured` shape; no struct."

  attr :session, SearchSession, required: true

  defp group_alternatives(assigns) do
    ~H"""
    <div class="ml-6 space-y-1">
      <button
        :for={result <- @group.results}
        type="button"
        class={[
          "glass-surface rounded-lg w-full px-4 py-2 flex items-center gap-3 text-left text-sm",
          selected?(@session.selections, @group.term, result.guid) && "bg-primary/10",
          !selected?(@session.selections, @group.term, result.guid) && "hover:bg-base-content/5"
        ]}
        phx-click="select_result"
        phx-value-term={@group.term}
        phx-value-guid={result.guid}
        data-nav-item
        tabindex="0"
      >
        <.icon
          name={
            if selected?(@session.selections, @group.term, result.guid),
              do: "hero-check-circle-mini",
              else: "hero-minus-circle-mini"
          }
          class={selection_icon_class(@session.selections, @group.term, result.guid)}
        />
        <span class={["text-xs font-bold w-10 shrink-0", quality_color(result.quality)]}>
          {Quality.label(result.quality)}
        </span>
        <span class="flex-1 min-w-0 truncate" title={result.title}>{result.title}</span>
        <span class="flex items-center gap-3 shrink-0 text-xs text-base-content/50">
          <span :if={result.size_bytes} class="tabular-nums">{format_bytes(result.size_bytes)}</span>
          <span :if={result.seeders} class={["tabular-nums", seeder_color(result.seeders)]}>
            {result.seeders}S
          </span>
          <span class="max-w-24 truncate">{result.indexer_name}</span>
        </span>
      </button>
    </div>
    """
  end

  attr :any_loading?, :boolean, required: true

  attr :timeout_terms, :list,
    required: true,
    doc: "List of group-term strings whose Prowlarr request timed out — eligible for bulk retry."

  attr :session, SearchSession, required: true

  defp results_footer(assigns) do
    ~H"""
    <div class="flex justify-end items-center gap-2">
      <.button
        :if={!@any_loading? && @timeout_terms != []}
        variant="risky"
        phx-click="retry_all_timeouts"
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-arrow-path-mini" class="size-4" /> Retry {length(@timeout_terms)} timeouts
      </.button>
      <.button
        variant="action"
        phx-click="grab_selected"
        disabled={@session.grabbing? || map_size(@session.selections) == 0}
        data-nav-item
        tabindex="0"
      >
        <span :if={@session.grabbing?} class="loading loading-spinner loading-sm"></span>
        <.icon :if={!@session.grabbing?} name="hero-arrow-down-tray-mini" class="size-4" />
        Grab {map_size(@session.selections)} selected
      </.button>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Template helpers
  # ---------------------------------------------------------------------------

  defp action_visible?(group), do: match?({:failed, _}, group.status) or group.status == :abandoned

  defp selected?(selections, term, guid), do: Map.get(selections, term) == guid

  defp selection_icon_class(selections, term, guid) do
    if selected?(selections, term, guid) do
      "size-4 shrink-0 text-primary"
    else
      "size-4 shrink-0 text-base-content/30"
    end
  end

  defp expansion_blocked?({:error, _}), do: true
  defp expansion_blocked?(:idle), do: true
  defp expansion_blocked?(_), do: false

  defp expansion_text(:idle), do: "Type a title and press Enter to search."
  defp expansion_text({:ok, 1}), do: "1 query — press Enter to search."
  defp expansion_text({:ok, n}), do: "#{n} queries in parallel — press Enter to search."
  defp expansion_text({:error, :invalid_syntax}), do: "Invalid brace syntax — see examples above."

  defp expansion_color({:error, _}), do: "text-error"
  defp expansion_color(_), do: "text-base-content/50"

  defp grab_message_color({:ok, _}), do: "text-success"
  defp grab_message_color({:partial, _}), do: "text-warning"
  defp grab_message_color({:error, _}), do: "text-error"

  defp grab_message_icon({:ok, _}), do: "hero-check-circle-mini"
  defp grab_message_icon({:partial, _}), do: "hero-exclamation-triangle-mini"
  defp grab_message_icon({:error, _}), do: "hero-x-circle-mini"

  defp grab_message_text({_, text}), do: text

  defp quality_color(:uhd_4k), do: "text-success"
  defp quality_color(:hd_1080p), do: "text-info"
  defp quality_color(nil), do: "text-base-content/40"

  defp seeder_color(n) when n >= 10, do: "text-success"
  defp seeder_color(n) when n >= 3, do: "text-warning"
  defp seeder_color(_), do: "text-error"

  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{round(bytes / 1_048_576)} MB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"
end
