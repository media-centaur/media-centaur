defmodule MediaCentaurWeb.Live.MediaSearch do
  @moduledoc """
  The media search a page hosts (UIDR-014, amended 2026-11-01): the
  omnibox's TMDB title search, "What do you want to watch?", whose
  results answer flat in the page as `Title.Row`s that open the title
  detail. One trait for the page that carries the box, Discovery (the
  *choose* stage, UIDR-057; Incoming hosted it too until the campaign's
  cutover), so the search stays one implementation whoever hosts it.

  `use MediaCentaurWeb.Live.MediaSearch` registers an `on_mount` that seeds
  the search's assigns (`clear/1`) and attaches three hooks:

  | Hook | Does |
  |---|---|
  | `:handle_event` | `omnibox_change` (debounced typing: one `TitleSearch.search/1` per settled query of two characters or more, superseding the one in flight), `omnibox_clear` (the one dismissal, refocusing a pointer user's box), `omnibox_scope` (the upcoming / released chips) — halting |
  | `:handle_async` | `:omnibox_search` landing: the newest query's first twenty rows, with the library's refs and the titles' social activity for the rows' markers and glyphs; a stale answer is dropped |
  | `:handle_info` | a friend's activity arriving or leaving re-reads the rows' social activity, then continues so the page's own clause runs |

  The host renders `Acquisition.MediaOmnibox` (media mode) and
  `Acquisition.MediaResults` from the assigns, decides what recedes while
  `owns_page?/1` holds, gives `page_facts/3` the landed snapshots through
  `results/1`, and keeps `:title_rungs` (`Watchlist.rungs/0`) for the
  rows' markers. A started download calls `clear/1`: the hunt is over.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, cancel_async: 3, push_event: 3, start_async: 3]

  alias MediaCentaur.Activities
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TMDB.TitleSearch
  alias MediaCentaurWeb.Components.Acquisition.MediaResults

  @type socket :: Phoenix.LiveView.Socket.t()

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.MediaSearch, :default}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> clear()
      |> attach_hook(:media_search_events, :handle_event, &handle_search_event/3)
      |> attach_hook(:media_search_async, :handle_async, &handle_search_async/3)
      |> attach_hook(:media_search_pubsub, :handle_info, &handle_search_info/2)

    {:cont, socket}
  end

  @doc "The search at rest: an empty query owns nothing, so the page's own content is back."
  @spec clear(socket()) :: socket()
  def clear(socket) do
    assign(socket,
      omnibox_query: "",
      omnibox_results: [],
      omnibox_searching?: false,
      omnibox_searched: nil,
      omnibox_scope: :all,
      in_library_refs: MapSet.new(),
      social_activity_by_ref: %{}
    )
  end

  @doc "Whether the typed query owns the page — `MediaResults.active_query?/1`, the results section's own gate. Takes the socket or its assigns."
  @spec owns_page?(socket() | map()) :: boolean()
  def owns_page?(%{assigns: assigns}), do: owns_page?(assigns)
  def owns_page?(%{omnibox_query: query}), do: MediaResults.active_query?(query)

  @doc "The landed results: the snapshots the page alone holds, for `page_facts/3`."
  @spec results(socket()) :: [Title.t()]
  def results(socket), do: socket.assigns.omnibox_results

  @doc false
  def handle_search_event("omnibox_change", %{"query" => query}, socket) do
    trimmed = String.trim(query)
    socket = assign(socket, omnibox_query: query)

    cond do
      String.length(trimmed) < 2 ->
        {:halt, assign(socket, omnibox_results: [], omnibox_searching?: false, omnibox_searched: nil)}

      # TMDB citizenship: a re-fire of the same effective query (trailing
      # space, blur/focus echo) never searches again — each debounce fire
      # costs one API call (multi), up to three when the query carries a
      # trailing year (movie + tv, plus the year-less fallback).
      trimmed == socket.assigns.omnibox_searched ->
        {:halt, socket}

      true ->
        {:halt,
         socket
         |> assign(omnibox_searching?: true, omnibox_searched: trimmed)
         |> cancel_async(:omnibox_search, :superseded)
         |> start_async(:omnibox_search, fn -> {query, TitleSearch.search(trimmed)} end)}
    end
  end

  # The flat results section's one reset — clearing the query is the only
  # dismissal (results are page content, not an overlay). The refocus puts
  # pointer users straight into the next search; the client-side input
  # wipe rides the button's JS.dispatch (see MediaResults).
  def handle_search_event("omnibox_clear", _params, socket),
    do: {:halt, socket |> clear() |> push_event("omnibox:refocus", %{})}

  # The upcoming/released chips between the box and the rows. Clicking the
  # active chip toggles back to everything; the scope survives query
  # refinements and resets with the query.
  def handle_search_event("omnibox_scope", %{"scope" => scope}, socket)
      when scope in ~w(upcoming released) do
    scope = String.to_existing_atom(scope)
    current = socket.assigns.omnibox_scope
    {:halt, assign(socket, omnibox_scope: if(current == scope, do: :all, else: scope))}
  end

  def handle_search_event(_event, _params, socket), do: {:cont, socket}

  @doc false
  def handle_search_async(:omnibox_search, {:ok, {query, results}}, socket) do
    # Stale guard: only the newest query's results land.
    if query == socket.assigns.omnibox_query do
      # One TMDB page, relevance-ranked — the list scrolls; depth past 20
      # is a query-refinement problem, not a pagination one.
      rows = Enum.take(results, 20)
      refs = Enum.map(rows, &{&1.tmdb_id, &1.media_type})

      {:halt,
       assign(socket,
         omnibox_results: rows,
         omnibox_searching?: false,
         in_library_refs: refs |> ExternalIds.tmdb_owners() |> Map.keys() |> MapSet.new(),
         social_activity_by_ref: Activities.activity_for(refs)
       )}
    else
      {:halt, socket}
    end
  end

  def handle_search_async(:omnibox_search, {:exit, _reason}, socket),
    do: {:halt, assign(socket, omnibox_searching?: false)}

  def handle_search_async(_name, _result, socket), do: {:cont, socket}

  @doc false
  def handle_search_info({tag, _event}, socket)
      when tag in [:activity_received, :activity_sent, :activity_deleted] do
    refs = Enum.map(socket.assigns.omnibox_results, &{&1.tmdb_id, &1.media_type})
    {:cont, assign(socket, social_activity_by_ref: Activities.activity_for(refs))}
  end

  def handle_search_info(_message, socket), do: {:cont, socket}
end
