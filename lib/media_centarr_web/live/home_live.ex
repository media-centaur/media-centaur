defmodule MediaCentarrWeb.HomeLive do
  @moduledoc """
  Cinematic landing page — the app's root route (`/`).

  Composes data from Library, ReleaseTracking, and WatchHistory contexts:
  hero card + Continue Watching + Coming Up + Recently Added. Pure
  assembly lives in `MediaCentarrWeb.HomeLive.Logic` per ADR-030.
  """
  use MediaCentarrWeb, :live_view
  use MediaCentarrWeb.Live.EntityModal
  use MediaCentarrWeb.Live.SpoilerFreeAware
  use MediaCentarrWeb.Live.CapabilitiesAware

  alias MediaCentarr.{
    Acquisition,
    Capabilities,
    Library,
    Library.Availability,
    Playback,
    ReleaseTracking,
    Settings,
    WatchHistory
  }

  alias MediaCentarrWeb.Components.{
    ComingUpMarquee,
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
      Playback.subscribe()
      Settings.subscribe()
      Availability.subscribe()
      Capabilities.subscribe()
    end

    socket =
      socket
      |> assign(:continue_timer, nil)
      |> assign(:coming_up_timer, nil)
      |> assign(:recently_added_timer, nil)
      |> assign(:playback, load_playback_sessions())
      |> assign(:availability_map, %{})
      |> assign_tmdb_ready()
      |> assign_spoiler_free()
      |> assign(:watch_dirs, MediaCentarr.Config.get(:watch_dirs) || [])
      |> assign_modal_defaults()
      |> assign_all()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/" full_width>
      <%!-- Home page positioning context. `relative` makes this the anchor
            for the absolutely positioned atmosphere layers, and because it
            sizes naturally to its content (unlike Layouts.app's flex-1 inner
            div) the side-dim's `bottom` reaches the true page bottom. --%>
      <div class="relative">
        <%!-- ── Page atmosphere (z-index 0) ──
              Backdrop image fades into base-100 at the top of the page. The
              side-dim continues the hero's left-anchored darkening down the
              entire page height so row titles sit on the same calm band.
              Both escape main's `px-6 py-6` padding and scroll with the page. --%>
        <div :if={@hero && @hero.backdrop_url} class="page-backdrop" aria-hidden="true">
          <img src={@hero.backdrop_url} alt="" />
        </div>
        <div :if={@hero} class="page-side-dim" aria-hidden="true"></div>

        <%!-- ── Hero (z-index 1) ──
              Breaks out of main's padding to fill available width. The
              row-scroll-hero wrapper is structural setup for future multi-item
              featured carousels; today it holds a single item. --%>
        <div
          :if={@hero}
          class="relative z-[1] -mx-6 -mt-6"
          data-scroll-row="hero"
        >
          <div class="row-scroll row-scroll-hero">
            <div class="w-full" data-row-item>
              <HeroCard.hero_card item={@hero} />
            </div>
          </div>
        </div>

        <%!-- ── Content rows (z-index 2) ── --%>
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

          <section :if={@recently_added != []} data-row="recently-added">
            <div class="flex items-baseline justify-between mb-3">
              <h2 class="text-xl font-semibold tracking-tight">Recently Added</h2>
              <.link navigate="/library" class="text-sm text-base-content/60 hover:text-primary">
                See all →
              </.link>
            </div>
            <PosterRow.poster_row items={@recently_added} />
          </section>

          <section :if={@coming_up_marquee.hero != nil} data-row="coming-up">
            <div class="flex items-baseline justify-between mb-3">
              <h2 class="text-xl font-semibold tracking-tight">Coming Up</h2>
              <.link navigate="/upcoming" class="text-sm text-base-content/60 hover:text-primary">
                See all →
              </.link>
            </div>
            <ComingUpMarquee.coming_up_marquee marquee={@coming_up_marquee} />
          </section>

          <%!-- Empty state if everything is empty --%>
          <div
            :if={
              @hero == nil and @continue_items == [] and @coming_up_marquee.hero == nil and
                @recently_added == []
            }
            class="text-center py-16 text-base-content/50"
          >
            <p>Your home page will populate as you add media and watch.</p>
          </div>
        </div>

        <%!-- Detail modal (always in DOM for smooth backdrop-filter) --%>
        <.entity_modal
          selected_entry={@selected_entry}
          selected_entity_id={@selected_entity_id}
          detail_presentation={@detail_presentation}
          detail_view={@detail_view}
          detail_files={@detail_files}
          expanded_seasons={@expanded_seasons}
          rematch_confirm={@rematch_confirm}
          delete_confirm={@delete_confirm}
          tracking_status={@tracking_status}
          availability_map={@availability_map}
          tmdb_ready={@tmdb_ready}
          spoiler_free={@spoiler_free}
        />
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
      {:noreply, apply_modal_params(socket, params)}
    end
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_modal_params(socket, params)}
  end

  @impl true
  def build_modal_path(socket, overrides) do
    selected = Map.get(overrides, :selected, socket.assigns.selected_entity_id)
    view = Map.get(overrides, :view, socket.assigns.detail_view)
    autoplay = Map.get(overrides, :autoplay)

    params = %{}
    params = if selected, do: Map.put(params, :selected, selected), else: params
    params = if selected && view == :info, do: Map.put(params, :view, :info), else: params
    params = if selected && autoplay, do: Map.put(params, :autoplay, autoplay), else: params

    if params == %{}, do: ~p"/", else: ~p"/?#{params}"
  end

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

  def handle_info({:entities_changed, entity_ids}, socket) do
    socket =
      if socket.assigns.selected_entity_id &&
           Enum.member?(entity_ids, socket.assigns.selected_entity_id) do
        refresh_selected_entry(socket)
      else
        socket
      end

    schedule_section_reloads(socket, {:entities_changed, entity_ids})
  end

  def handle_info({:playback_state_changed, entity_id, new_state, now_playing, _started_at}, socket) do
    playback = apply_playback_change(socket.assigns.playback, entity_id, new_state, now_playing)
    {:noreply, assign(socket, playback: playback)}
  end

  def handle_info({:playback_failed, _entity_id, _reason, payload}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       MediaCentarrWeb.LibraryFormatters.playback_failed_flash(payload)
     )}
  end

  def handle_info(message, socket), do: schedule_section_reloads(socket, message)

  defp schedule_section_reloads(socket, message) do
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
    assign(socket, :coming_up_marquee, Logic.coming_up_marquee(load_coming_up(today), today))
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
