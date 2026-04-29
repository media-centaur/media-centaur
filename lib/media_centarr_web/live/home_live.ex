defmodule MediaCentarrWeb.HomeLive do
  @moduledoc """
  Cinematic landing page — the app's root route (`/`).

  Composes data from Library, ReleaseTracking, and WatchHistory contexts:
  hero card + Continue Watching + Coming Up + Recently Added. Pure
  assembly lives in `MediaCentarrWeb.HomeLive.Logic` per ADR-030.
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

    socket =
      socket
      |> assign(:continue_timer, nil)
      |> assign(:coming_up_timer, nil)
      |> assign(:recently_added_timer, nil)
      |> assign_all()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/" full_width>
      <%!-- Hero breaks out of the Layouts.app `<main class="px-6 py-6">`
            wrapper via negative margins so it can fill the available width
            (viewport - side rail). The rows below pull up under the hero's
            fade-to-base for the Netflix dissolve effect.

            Hero is wrapped in `row-scroll-hero` so it can later hold
            multiple featured items that swipe horizontally. Currently a
            single item — the structural setup is for future per-row
            keyboard/gamepad navigation. --%>
      <div
        :if={@hero}
        class="-mx-6 -mt-6"
        data-scroll-row="hero"
      >
        <div class="row-scroll row-scroll-hero">
          <div class="w-full" data-row-item>
            <HeroCard.hero_card item={@hero} />
          </div>
        </div>
      </div>
      <div class={[
        "relative z-[2] space-y-10",
        @hero && "-mt-8"
      ]}>
        <section :if={@continue_items != []} data-row="continue-watching">
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-xl font-semibold tracking-tight">Continue Watching</h2>
            <.link navigate="/library" class="text-sm text-base-content/60 hover:text-primary">
              See all →
            </.link>
          </div>
          <ContinueWatchingRow.continue_watching_row items={@continue_items} />
        </section>

        <section :if={@coming_up_items != []} data-row="coming-up">
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-xl font-semibold tracking-tight">Coming Up</h2>
            <.link navigate="/upcoming" class="text-sm text-base-content/60 hover:text-primary">
              See all →
            </.link>
          </div>
          <ComingUpRow.coming_up_row items={@coming_up_items} />
        </section>

        <section :if={@recently_added != []} data-row="recently-added">
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-xl font-semibold tracking-tight">Recently Added</h2>
            <.link navigate="/library" class="text-sm text-base-content/60 hover:text-primary">
              See all →
            </.link>
          </div>
          <PosterRow.poster_row items={@recently_added} />
        </section>

        <%!-- Empty state if everything is empty --%>
        <div
          :if={
            @hero == nil and @continue_items == [] and @coming_up_items == [] and
              @recently_added == []
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
  def handle_info(:reload_continue_watching, socket) do
    {:noreply, assign_continue_watching(socket)}
  end

  def handle_info(:reload_coming_up, socket) do
    {:noreply, assign_coming_up(socket, Date.utc_today())}
  end

  def handle_info(:reload_recently_added, socket) do
    {:noreply, assign_recently_added(socket)}
  end

  def handle_info(message, socket) do
    socket =
      message
      |> Logic.section_reloaders()
      |> Enum.reduce(socket, &schedule_section_reload/2)

    {:noreply, socket}
  end

  defp schedule_section_reload(:continue_watching, socket),
    do: debounce(socket, :continue_timer, :reload_continue_watching, 500)

  defp schedule_section_reload(:coming_up, socket),
    do: debounce(socket, :coming_up_timer, :reload_coming_up, 500)

  defp schedule_section_reload(:recently_added, socket),
    do: debounce(socket, :recently_added_timer, :reload_recently_added, 500)

  defp assign_all(socket) do
    today = Date.utc_today()

    socket
    |> assign_hero(today)
    |> assign_continue_watching()
    |> assign_coming_up(today)
    |> assign_recently_added()
  end

  defp assign_hero(socket, today) do
    hero_candidates = load_hero_candidates()
    assign(socket, :hero, Logic.hero_card_item(Logic.select_hero(hero_candidates, today)))
  end

  defp assign_continue_watching(socket) do
    assign(socket, :continue_items, Logic.continue_watching_items(load_progress()))
  end

  defp assign_coming_up(socket, today) do
    assign(socket, :coming_up_items, Logic.coming_up_items(load_coming_up(today), today))
  end

  defp assign_recently_added(socket) do
    assign(socket, :recently_added, Logic.recently_added_items(load_recently_added()))
  end

  # --- Data loaders ---
  # Each loader returns a list of plain maps in the shape Logic expects.
  # Loaders returning [] are intentional stubs — see WIRE(4.6) comments.

  defp load_progress, do: Library.list_in_progress(limit: 24)

  defp load_coming_up(today) do
    # Show all upcoming releases in the next 90 days. Earlier this row was
    # bounded to "this week" but the row scrolls horizontally now, so a
    # wider window is what users expect — all their tracked coming-soon
    # items, sorted by air date, scrollable.
    to_date = Date.add(today, 90)
    releases = ReleaseTracking.list_releases_between(today, to_date, limit: 30)

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

  defp load_recently_added, do: Library.list_recently_added(limit: 30)

  defp load_hero_candidates, do: Library.list_hero_candidates(limit: 12)
end
