defmodule MediaCentaurWeb.IncomingLive.Search do
  @moduledoc """
  Release-search results zone of the Downloads page — grab feedback,
  group rendering, and the bulk-grab footer. **Headless since
  UIDR-014**: the query form, syntax hint, and expansion preview live
  in the omnibox hero (`MediaOmnibox`, release mode); this component
  renders what the session found. Pure function component; all events
  bubble to the parent `IncomingLive` (`toggle_group`,
  `select_result`, `retry_search`, `retry_all_timeouts`,
  `grab_selected`).
  """
  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]

  alias MediaCentaurWeb.Components.Acquisition.ReleaseFacts
  alias MediaCentaurWeb.IncomingLive.SearchSession
  alias MediaCentaurWeb.IncomingLive.Logic

  attr :session, SearchSession, required: true
  attr :any_loading?, :boolean, required: true

  attr :timeout_terms, :list,
    required: true,
    doc: "List of group-term strings whose Prowlarr request timed out — eligible for bulk retry."

  def search_zone(assigns) do
    ~H"""
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
      <div class="flex justify-end">
        <button
          type="button"
          class="text-xs text-base-content/30 transition-colors hover:text-base-content/60"
          phx-click="clear_search"
          data-nav-item
          tabindex="0"
        >
          Clear search
        </button>
      </div>
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
      class="scrim-surface rounded-lg w-full px-4 py-3 flex items-center gap-3 text-left hover:brightness-110 transition-[filter]"
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
    <ReleaseFacts.release_facts entry={
      %ReleaseFacts.Entry{
        title: @group.featured.title,
        quality: @group.featured.quality,
        size_bytes: @group.featured.size_bytes,
        seeders: @group.featured.seeders
      }
    } />
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
        <ReleaseFacts.release_facts entry={
          %ReleaseFacts.Entry{
            title: result.title,
            quality: result.quality,
            size_bytes: result.size_bytes,
            seeders: result.seeders,
            indexer: result.indexer_name
          }
        } />
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

  defp grab_message_color({:ok, _}), do: "text-success"
  defp grab_message_color({:partial, _}), do: "text-warning"
  defp grab_message_color({:error, _}), do: "text-error"

  defp grab_message_icon({:ok, _}), do: "hero-check-circle-mini"
  defp grab_message_icon({:partial, _}), do: "hero-exclamation-triangle-mini"
  defp grab_message_icon({:error, _}), do: "hero-x-circle-mini"

  defp grab_message_text({_, text}), do: text
end
