defmodule MediaCentaurWeb.Components.TrackModal do
  @moduledoc """
  Modal for tracking new shows and movies via TMDB search.

  Always present in the DOM (like ModalShell). Toggled via
  `data-state="open"/"closed"` — no first-frame blur jank.
  """
  use MediaCentaurWeb, :html

  attr :open, :boolean, default: false
  attr :suggestions, :list, default: []
  attr :suggestions_loading, :boolean, default: false
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: []
  attr :search_loading, :boolean, default: false
  attr :scope_item, :map, default: nil
  attr :collection_item, :map, default: nil

  def track_modal(assigns) do
    ~H"""
    <div
      id="track-modal"
      class="modal-backdrop"
      data-state={if @open, do: "open", else: "closed"}
      phx-window-keydown={@open && "close_track_modal"}
      phx-key="Escape"
    >
      <div class="modal-panel" phx-click-away={@open && "close_track_modal"}>
        <div class="flex flex-col flex-1 min-h-0 max-h-[80vh]">
          <%!-- Header --%>
          <div class="flex items-center justify-between px-5 py-4 border-b border-base-content/10">
            <h2 class="text-lg font-semibold">Track New Show</h2>
            <button
              phx-click="close_track_modal"
              class="btn btn-ghost btn-circle btn-sm"
              aria-label="Close"
            >
              <.icon name="hero-x-mark-mini" class="size-5" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto p-5 space-y-5">
            <%!-- Suggestions section --%>
            <.suggestions_section
              suggestions={@suggestions}
              loading={@suggestions_loading}
            />

            <%!-- Search bar --%>
            <div>
              <form phx-change="track_search" phx-submit="track_search">
                <input
                  id="track-search-input"
                  type="text"
                  name="query"
                  value={@search_query}
                  placeholder="Search movies & shows…"
                  class="input input-bordered w-full"
                  autocomplete="off"
                  phx-debounce="300"
                />
              </form>
            </div>

            <%!-- Search results --%>
            <div :if={@search_loading} class="flex justify-center py-4">
              <span class="loading loading-spinner loading-sm text-base-content/50"></span>
            </div>

            <div :if={@search_results != []} class="space-y-2">
              <.search_result
                :for={result <- @search_results}
                result={result}
                scope_item={@scope_item}
                collection_item={@collection_item}
              />
            </div>

            <div
              :if={@search_query != "" && @search_results == [] && !@search_loading}
              class="text-center text-base-content/40 py-4"
            >
              No results found
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Suggestions ---

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true

  defp suggestions_section(%{suggestions: [], loading: false} = assigns) do
    ~H"""
    """
  end

  defp suggestions_section(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium text-base-content/60 mb-3">Suggested from your library</h3>
      <div :if={@loading} class="flex justify-center py-4">
        <span class="loading loading-spinner loading-sm text-base-content/50"></span>
      </div>
      <div :if={!@loading} class="flex gap-3 overflow-x-auto pb-2">
        <.suggestion_card :for={suggestion <- @suggestions} suggestion={suggestion} />
      </div>
    </div>
    """
  end

  attr :suggestion, :map, required: true

  defp suggestion_card(assigns) do
    ~H"""
    <button
      phx-click="track_suggestion"
      phx-value-tmdb-id={@suggestion.tmdb_id}
      phx-value-tv-series-id={@suggestion.tv_series_id}
      phx-value-name={@suggestion.name}
      class="flex-shrink-0 w-28 group cursor-pointer text-left"
    >
      <div class="aspect-[2/3] rounded-lg bg-base-300 overflow-hidden mb-2 ring-1 ring-base-content/10 group-hover:ring-primary/40 transition-all">
        <div class="w-full h-full flex items-center justify-center text-base-content/20">
          <.icon name="hero-tv-mini" class="size-8" />
        </div>
      </div>
      <p class="text-xs font-medium truncate">{@suggestion.name}</p>
      <p class="text-xs text-primary/70 group-hover:text-primary transition-colors">+ Track</p>
    </button>
    """
  end

  # --- Search Results ---

  attr :result, :map, required: true
  attr :scope_item, :map, default: nil
  attr :collection_item, :map, default: nil

  defp search_result(assigns) do
    type_label = if assigns.result.media_type == :movie, do: "Movie", else: "TV"

    assigns = assign(assigns, :type_label, type_label)

    ~H"""
    <div class="rounded-lg border border-base-content/10 overflow-hidden">
      <div class="flex items-center gap-3 p-3">
        <%!-- Poster thumbnail --%>
        <div class="flex-shrink-0 w-10 h-14 rounded bg-base-300 overflow-hidden flex items-center justify-center">
          <.icon
            name={if @result.media_type == :movie, do: "hero-film-mini", else: "hero-tv-mini"}
            class="size-5 text-base-content/20"
          />
        </div>

        <%!-- Title + meta --%>
        <div class="flex-1 min-w-0">
          <p class="font-medium truncate">{@result.name}</p>
          <div class="flex items-center gap-2 text-xs text-base-content/50">
            <span class={[
              "px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase",
              if(@result.media_type == :movie,
                do: "bg-warning/15 text-warning",
                else: "bg-info/15 text-info"
              )
            ]}>
              {@type_label}
            </span>
            <span :if={@result.year}>{@result.year}</span>
          </div>
        </div>

        <%!-- Action --%>
        <div class="flex-shrink-0">
          <span :if={@result.already_tracked} class="text-xs text-success/70 font-medium">
            Tracking
          </span>
          <button
            :if={!@result.already_tracked}
            phx-click="select_search_result"
            phx-value-tmdb-id={@result.tmdb_id}
            phx-value-media-type={@result.media_type}
            phx-value-name={@result.name}
            phx-value-poster-path={@result.poster_path}
            class="btn btn-soft btn-primary btn-xs"
          >
            Track
          </button>
        </div>
      </div>

      <%!-- Inline TV scope picker --%>
      <.tv_scope_picker
        :if={@scope_item && @scope_item.tmdb_id == @result.tmdb_id}
        item={@scope_item}
      />

      <%!-- Inline collection prompt --%>
      <.collection_prompt
        :if={@collection_item && @collection_item.tmdb_id == @result.tmdb_id}
        item={@collection_item}
      />
    </div>
    """
  end

  # --- TV Scope Picker ---

  attr :item, :map, required: true

  defp tv_scope_picker(assigns) do
    ~H"""
    <div class="border-t border-base-content/10 bg-base-200/30 p-3 space-y-3">
      <p class="text-sm font-medium">Track from…</p>
      <form phx-submit="confirm_track" class="space-y-2">
        <input type="hidden" name="tmdb_id" value={@item.tmdb_id} />
        <input type="hidden" name="media_type" value="tv_series" />
        <input type="hidden" name="name" value={@item.name} />
        <input type="hidden" name="poster_path" value={@item.poster_path} />

        <label class="flex items-center gap-2 text-sm cursor-pointer">
          <input type="radio" name="scope" value="all" class="radio radio-sm radio-primary" checked />
          <span>All upcoming episodes</span>
        </label>

        <label class="flex items-center gap-2 text-sm cursor-pointer">
          <input type="radio" name="scope" value="custom" class="radio radio-sm radio-primary" />
          <span>From season</span>
          <input
            type="number"
            name="start_season"
            value="1"
            min="1"
            class="input input-bordered input-xs w-16"
          />
          <span>episode</span>
          <input
            type="number"
            name="start_episode"
            value="1"
            min="1"
            class="input input-bordered input-xs w-16"
          />
        </label>

        <div class="pt-1">
          <button type="submit" class="btn btn-soft btn-primary btn-sm">
            Confirm
          </button>
        </div>
      </form>
    </div>
    """
  end

  # --- Collection Prompt ---

  attr :item, :map, required: true

  defp collection_prompt(assigns) do
    ~H"""
    <div class="border-t border-base-content/10 bg-base-200/30 p-3 space-y-3">
      <p class="text-sm font-medium">This movie is part of a collection</p>
      <div class="flex gap-2">
        <button
          phx-click="confirm_track"
          phx-value-tmdb-id={@item.tmdb_id}
          phx-value-media-type="movie"
          phx-value-name={@item.name}
          phx-value-poster-path={@item.poster_path}
          phx-value-scope="movie_only"
          class="btn btn-soft btn-primary btn-sm"
        >
          Just this movie
        </button>
        <button
          phx-click="confirm_track"
          phx-value-tmdb-id={@item.collection_id}
          phx-value-media-type="movie"
          phx-value-name={@item.collection_name}
          phx-value-poster-path={@item.poster_path}
          phx-value-scope="collection"
          class="btn btn-soft btn-info btn-sm"
        >
          Whole collection
        </button>
      </div>
    </div>
    """
  end
end
