defmodule MediaCentaurWeb.DownloadsLive.Search do
  @moduledoc """
  Release search on the Downloads page (UIDR-014, amended 2026-11-02):
  the field at the top of the page and the results zone below it.

  `search_box/1` is the page's one search, its own field since the
  cutover (campaign `discovery.md`, M14): the brace-expansion query form
  — monospace input, Enter the only submit path, the in-input X that
  dismisses the session — over the syntax line with the expansion
  preview. It is the `omnibox` nav zone, so the Downloads behaviour's
  CLEAR (`downloads_behavior.js`) finds it by its input's id.

  `search_zone/1` renders what the session found: grab feedback, the
  groups, the bulk-grab footer. Pure function components; every event
  bubbles to the page (`query_change`, `submit_search`, `clear_search`,
  `toggle_group`, `select_result`, `retry_search`, `retry_all_timeouts`,
  `grab_selected`).
  """
  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]
  import MediaCentaurWeb.Components.Disclosure

  alias MediaCentaurWeb.Components.Acquisition.ReleaseFacts
  alias MediaCentaurWeb.DownloadsLive.SearchSession
  alias MediaCentaurWeb.DownloadsLive.Logic
  alias Phoenix.LiveView.JS

  attr :session, SearchSession, required: true
  attr :any_loading?, :boolean, required: true

  def search_box(assigns) do
    ~H"""
    <%!-- The field floats on the page as its front door, centred (on a
          media-center-wide screen a left-hugging column strands the right
          half). No submit button: Enter is the only submit path (HTML
          implicit submission, single-field form). A disabled submit button
          once silently swallowed Enter here; buttonless makes that bug
          class unrepresentable. submit_search guards empty and invalid
          queries server-side. --%>
    <section data-nav-zone="omnibox" class="mx-auto w-full max-w-2xl space-y-3">
      <form
        id="release-omnibox-form"
        phx-change="query_change"
        phx-submit="submit_search"
        autocomplete="off"
      >
        <div class="relative">
          <.icon
            name="hero-command-line-mini"
            class="size-5 text-base-content/50 absolute left-4 top-1/2 -translate-y-1/2 z-10 pointer-events-none"
          />
          <input
            id="omnibox-release-input"
            type="text"
            name="query"
            value={@session.query}
            class="input w-full pl-12 pr-12 font-mono text-sm h-[52px] rounded-xl"
            placeholder="Title S01E{01-10}"
            phx-debounce="200"
            phx-hook="MouseAutofocus"
            data-nav-item
            tabindex="0"
          />
          <%!-- The spinner yields the far-right slot to the X whenever a
                query is present (the X exists exactly then). --%>
          <span
            :if={@any_loading?}
            class={[
              "loading loading-spinner loading-sm absolute top-1/2 -translate-y-1/2 text-base-content/40",
              (@session.query != "" && "right-12") || "right-4"
            ]}
          ></span>
          <%!-- The input is cleared client-side too (the app.js
                omnibox:clear-input listener): LiveView never overwrites a
                focused input's value, so the server-side reset alone would
                leave stale text in the box. --%>
          <.button
            :if={@session.query != ""}
            id="omnibox-release-clear"
            type="button"
            variant="dismiss"
            size="sm"
            shape="circle"
            class="absolute right-2 top-1/2 -translate-y-1/2 z-10 text-base-content/55"
            phx-click={
              JS.dispatch("omnibox:clear-input", to: "#omnibox-release-input")
              |> JS.push("clear_search")
            }
            aria-label="Clear search"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-x-mark-mini" class="size-5" />
          </.button>
        </div>
      </form>

      <p class="flex flex-wrap items-center justify-center gap-x-3 text-xs text-base-content/55">
        <span>Syntax:</span>
        <code class="font-mono px-1.5 py-0.5 rounded bg-base-content/10 text-base-content/60">
          {"{a,b,c}"}
        </code>
        <code class="font-mono px-1.5 py-0.5 rounded bg-base-content/10 text-base-content/60">
          {"{00-09}"}
        </code>
        <span class={Logic.expansion_color(@session.expansion_preview)}>
          {Logic.expansion_text(@session.expansion_preview)}
        </span>
      </p>
    </section>
    """
  end

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
        <.button
          type="button"
          variant="dismiss"
          size="xs"
          phx-click="clear_search"
          data-nav-item
          tabindex="0"
        >
          Clear search
        </.button>
      </div>
      <div
        :for={group <- @session.groups}
        id={"search-group-#{:erlang.phash2(group.term)}"}
        class="space-y-1"
      >
        <%!-- Host-owned: SearchSession keeps a group's expansion across
              navigation, refresh and reconnect. --%>
        <.disclosure
          id={"search-results-#{:erlang.phash2(group.term)}"}
          open={group.expanded?}
          event="toggle_group"
          phx-value-term={group.term}
          variant={:bare}
          head_class="scrim-surface rounded-lg w-full px-4 py-3 flex items-center gap-3 text-left hover:brightness-110 transition-[filter]"
          caret_class="size-4 text-base-content/40"
          body_class="mt-1"
        >
          <:head>
            <span class="text-xs font-medium text-base-content/55 w-32 shrink-0 truncate">
              {group.term}
            </span>
            <.group_status_summary group={group} />
          </:head>
          <.group_alternatives :if={group.results != []} group={group} session={@session} />
        </.disclosure>
        <.group_actions :if={action_visible?(group)} group={group} />
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

  defp group_status_summary(%{group: %{status: :loading}} = assigns) do
    ~H"""
    <span class="loading loading-spinner loading-xs text-base-content/40"></span>
    <span class="flex-1 text-sm text-base-content/55">Searching…</span>
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
    <span class="flex-1 text-sm text-base-content/55">
      Search was interrupted — Retry to resume
    </span>
    """
  end

  defp group_status_summary(%{group: %{status: :ready, results: []}} = assigns) do
    ~H"""
    <span class="flex-1 text-sm text-base-content/55">No results</span>
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
        id={"search-result-#{:erlang.phash2({@group.term, result.guid})}"}
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
