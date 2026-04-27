defmodule MediaCentarrWeb.HomeLive do
  @moduledoc """
  Cinematic landing page — the app's root route (`/`).

  Composes data from Library, ReleaseTracking, and WatchHistory contexts:
  hero card + Continue Watching + Coming Up This Week + Recently Added +
  Heavy Rotation. Pure assembly lives in `MediaCentarrWeb.HomeLive.Logic`
  per ADR-030.
  """
  use MediaCentarrWeb, :live_view

  alias MediaCentarr.{Acquisition, Capabilities, Library, ReleaseTracking, WatchHistory}

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

    {:ok, socket |> assign(reload_timer: nil) |> assign_all()}
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

        <section :if={@heavy_rotation != []}>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-lg font-semibold">Heavy Rotation</h2>
            <.link navigate="/history" class="text-sm text-base-content/60 hover:text-primary">
              See all →
            </.link>
          </div>
          <PosterRow.poster_row items={@heavy_rotation} />
        </section>

        <%!-- Empty state if everything is empty --%>
        <div
          :if={
            @hero == nil and @continue_items == [] and @coming_up_items == [] and
              @recently_added == [] and @heavy_rotation == []
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
  def handle_info({:entities_changed, _ids}, socket) do
    {:noreply, debounce(socket, :reload_timer, :reload_home, 500)}
  end

  def handle_info(:reload_home, socket) do
    {:noreply, assign_all(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp assign_all(socket) do
    today = Date.utc_today()

    progress = load_progress()
    coming_up = load_coming_up(today)
    recently_added = load_recently_added()
    {rewatches, entity_lookup} = load_heavy_rotation()
    hero_candidates = load_hero_candidates()

    socket
    |> assign(:hero, Logic.hero_card_item(Logic.select_hero(hero_candidates, today)))
    |> assign(:continue_items, Logic.continue_watching_items(progress))
    |> assign(:coming_up_items, Logic.coming_up_items(coming_up, today))
    |> assign(:recently_added, Logic.recently_added_items(recently_added))
    |> assign(:heavy_rotation, Logic.heavy_rotation_items(rewatches, entity_lookup))
  end

  # --- Data loaders ---
  # Each loader returns a list of plain maps in the shape Logic expects.
  # Loaders returning [] are intentional stubs — see WIRE(4.6) comments.

  defp load_progress, do: Library.list_in_progress(limit: 4)

  defp load_coming_up(today) do
    {monday, sunday} = Logic.coming_up_window(today)
    releases = ReleaseTracking.list_releases_between(monday, sunday, limit: 8)

    grab_statuses =
      if Capabilities.prowlarr_ready?() do
        keys = Enum.map(releases, &release_grab_key/1)
        Acquisition.statuses_for_releases(keys)
      else
        %{}
      end

    Enum.map(releases, fn release ->
      key = release_grab_key(release)

      status =
        case Map.get(grab_statuses, key) do
          nil -> :scheduled
          grab -> grab_status_atom(grab.status)
        end

      Map.put(release, :status, status)
    end)
  end

  defp release_grab_key(release) do
    {to_string(release.item.tmdb_id), to_string(release.item.media_type), release.season_number,
     release.episode_number}
  end

  defp grab_status_atom("grabbed"), do: :grabbed
  defp grab_status_atom("searching"), do: :searching
  defp grab_status_atom("snoozed"), do: :pending
  defp grab_status_atom(_), do: :scheduled

  defp load_recently_added, do: Library.list_recently_added(limit: 16)

  defp load_heavy_rotation do
    rewatches = WatchHistory.top_rewatches(min: 2, limit: 8)
    refs = Enum.map(rewatches, fn rewatch -> {rewatch.entity_type, rewatch.entity_id} end)
    entity_lookup = Library.lookup_entities_for_display(refs)
    {rewatches, entity_lookup}
  end

  defp load_hero_candidates, do: Library.list_hero_candidates(limit: 12)
end
