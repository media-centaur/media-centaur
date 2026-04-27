defmodule MediaCentarrWeb.HomeLive do
  @moduledoc """
  Cinematic landing page — the app's root route (`/`).

  Composes data from Library, ReleaseTracking, and WatchHistory contexts:
  hero card + Continue Watching + Coming Up This Week + Recently Added +
  Watched Recently. Pure assembly lives in `MediaCentarrWeb.HomeLive.Logic`
  per ADR-030.
  """
  use MediaCentarrWeb, :live_view

  alias MediaCentarr.{Library, ReleaseTracking, WatchHistory}

  alias MediaCentarrWeb.Components.{
    ComingUpRow,
    ContinueWatchingRow,
    HeroCard,
    PosterRow
  }

  alias MediaCentarrWeb.HomeLive.Logic

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Library.subscribe()
      ReleaseTracking.subscribe()
      WatchHistory.subscribe()
    end

    {:ok, assign_all(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/" full_width>
      <div class="space-y-8 py-2">
        <HeroCard.hero_card item={@hero} />

        <section :if={@continue_items != []}>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-lg font-semibold">Continue Watching</h2>
            <.link navigate="/library" class="text-sm text-base-content/60 hover:text-primary">
              See all →
            </.link>
          </div>
          <ContinueWatchingRow.continue_watching_row items={@continue_items} />
        </section>

        <section :if={@coming_up_items != []}>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-lg font-semibold">Coming Up This Week</h2>
            <.link navigate="/upcoming" class="text-sm text-base-content/60 hover:text-primary">
              See all →
            </.link>
          </div>
          <ComingUpRow.coming_up_row items={@coming_up_items} />
        </section>

        <section :if={@recently_added != []}>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-lg font-semibold">Recently Added</h2>
            <.link navigate="/library" class="text-sm text-base-content/60 hover:text-primary">
              See all →
            </.link>
          </div>
          <PosterRow.poster_row items={@recently_added} />
        </section>

        <section :if={@watched_recently != []}>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-lg font-semibold">Watched Recently</h2>
            <.link navigate="/history" class="text-sm text-base-content/60 hover:text-primary">
              See all →
            </.link>
          </div>
          <PosterRow.poster_row items={@watched_recently} />
        </section>

        <%!-- Empty state if everything is empty --%>
        <div
          :if={
            @hero == nil and @continue_items == [] and @coming_up_items == [] and
              @recently_added == [] and @watched_recently == []
          }
          class="text-center py-16 text-base-content/50"
        >
          <p>Your home page will populate as you add media and watch.</p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_params(%{"zone" => zone} = params, _uri, socket) do
    forward_params = Map.delete(params, "zone")
    query = if forward_params == %{}, do: "", else: "?" <> URI.encode_query(forward_params)

    destination =
      case zone do
        "upcoming" -> "/upcoming"
        "library" -> "/library"
        _ -> nil
      end

    if destination do
      {:noreply, push_navigate(socket, to: destination <> query)}
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:entities_changed, _ids}, socket), do: {:noreply, assign_all(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp assign_all(socket) do
    today = Date.utc_today()

    progress = load_progress()
    coming_up = load_coming_up(today)
    recently_added = load_recently_added()
    watched_recently = load_watched_recently()
    hero_candidates = load_hero_candidates()

    socket
    |> assign(:hero, Logic.hero_card_item(Logic.select_hero(hero_candidates, today)))
    |> assign(:continue_items, Logic.continue_watching_items(progress))
    |> assign(:coming_up_items, Logic.coming_up_items(coming_up, today))
    |> assign(:recently_added, Logic.recently_added_items(recently_added))
    |> assign(:watched_recently, Logic.watched_recently_items(watched_recently))
  end

  # --- Data loaders ---
  # Each loader returns a list of plain maps in the shape Logic expects.
  # Loaders returning [] are intentional stubs — see WIRE(4.6) comments.

  defp load_progress, do: Library.list_in_progress(limit: 12)

  defp load_coming_up(today) do
    {monday, sunday} = Logic.coming_up_window(today)
    ReleaseTracking.list_releases_between(monday, sunday, limit: 8)
  end

  defp load_recently_added, do: Library.list_recently_added(limit: 16)

  defp load_watched_recently do
    # WatchHistory.recent_events/1 returns Event structs with :title,
    # :movie_id, :episode_id, :video_object_id. Map to the shape
    # Logic.watched_recently_items/1 expects: %{entity_id, entity_name, year, poster_url}.
    # year and poster_url are not available on WatchHistory.Event — left nil
    # for now; Task 4.6 may enrich these if needed.
    Enum.map(WatchHistory.recent_events(16), fn event ->
      %{
        entity_id: event.movie_id || event.episode_id || event.video_object_id,
        entity_name: event.title,
        year: nil,
        poster_url: nil
      }
    end)
  end

  defp load_hero_candidates, do: Library.list_hero_candidates(limit: 12)
end
