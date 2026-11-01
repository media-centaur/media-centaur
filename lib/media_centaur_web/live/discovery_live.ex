defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  Discovery: the page for titles you do not own yet (campaign
  `discovery.md`) — the second assembled page, shelved like Home. A
  feature in development (ADR-081): off by default; its sidebar entry and
  this page exist while the `:discovery` flag is on, and the page is its
  off state otherwise.

  What it holds so far: the **New Releases** shelf — `NewReleases.members/0`
  drawn as a poster row of TMDB identities from the store's snapshots,
  each tile opening the title detail (`TitleDetailHost`), with the quiet
  marker a title the library owns or the watchlist holds carries. Opening
  the page reads the database only; nothing here calls TMDB. The shelf
  follows the membership, the store, the watchlist and the library,
  debounced (`Shelves.reloads?/1`). The watchlist shelves, Reviewed by
  Friends, the verbs on a tile, the hero and media search are later
  milestones of the campaign.

  Empty, the page says why (UIDR-034, `Shelves.empty_reason/3`): TMDB
  never configured is the capability gap with the one action; TMDB down
  with nothing stored, or the first refresh still to run, each say so.

  Input: `data-nav-default-zone="discovery"` selects the `discovery`
  layout — one SHELF zone per shelf, as on Home; no page behaviour until
  search needs CLEAR.
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.TitleDetailHost
  use MediaCentaurWeb.Live.SpoilerFreeAware
  use MediaCentaurWeb.Live.LetterboxdLinksAware

  alias MediaCentaur.Acquisition.TitleStates
  alias MediaCentaur.Features
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.NewReleases
  alias MediaCentaur.NewReleases.Member
  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.Watchlist
  alias MediaCentaurWeb.Components.{DetailPanel, FeatureOff, PosterRow, ShelfHead}
  alias MediaCentaurWeb.DiscoveryLive.Shelves
  alias MediaCentaurWeb.Live.{ReviewModal, Subscriptions, TitleDetailHost}
  alias MediaCentaurWeb.IncomingLive.PlanQuery

  @reload_debounce_ms 500

  @impl true
  def mount(_params, _session, socket) do
    socket =
      Enum.reduce(
        [NewReleases, IntegrationAvailability],
        socket,
        &Subscriptions.subscribe(&2, &1)
      )

    {:ok,
     assign(socket,
       page_title: "Discovery",
       today: Date.utc_today(),
       loaded?: false,
       reload_timer: nil,
       new_releases: [],
       empty_reason: nil
     )}
  end

  # The shelves load once, on whichever render comes first (ADR-051), and
  # only while the feature is on: the off state reads nothing.
  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, ensure_loaded(socket)}

  defp ensure_loaded(%{assigns: %{loaded?: true}} = socket), do: socket

  defp ensure_loaded(socket) do
    if :discovery in socket.assigns.features,
      do: socket |> assign(:loaded?, true) |> load_shelves(),
      else: socket
  end

  defp load_shelves(socket) do
    members = NewReleases.members()
    refs = Enum.map(members, &Member.ref/1)

    items =
      Shelves.new_releases_items(
        members,
        Store.snapshots(refs),
        Watchlist.rungs(),
        ExternalIds.tmdb_owners(refs),
        TitleStates.for_refs(refs)
      )

    assign(socket,
      new_releases: items,
      empty_reason:
        Shelves.empty_reason(
          socket.assigns.tmdb_ready,
          IntegrationAvailability.up?(:tmdb),
          length(items)
        )
    )
  end

  @impl true
  def handle_info(:reload_shelves, socket) do
    {:noreply, socket |> assign(:reload_timer, nil) |> load_shelves()}
  end

  # The title detail host's hook has already refreshed an open detail for
  # these broadcasts; the page reloads its shelf for the ones that change
  # it, coalescing a burst into one read.
  def handle_info(message, socket) do
    if Shelves.reloads?(message) and socket.assigns.loaded?,
      do: {:noreply, debounce_reload(socket)},
      else: {:noreply, socket}
  end

  defp debounce_reload(%{assigns: %{reload_timer: timer}} = socket) do
    if timer, do: Process.cancel_timer(timer)
    assign(socket, :reload_timer, Process.send_after(self(), :reload_shelves, @reload_debounce_ms))
  end

  # --- TitleDetailHost ---

  # Every title here is a store identity the host reads on its own.
  @impl TitleDetailHost
  def page_facts(_socket, _ref, _params), do: {nil, %{}}

  @impl TitleDetailHost
  def title_detail_path(_socket, []), do: ~p"/discovery"
  def title_detail_path(_socket, query), do: ~p"/discovery?#{query}"

  @impl TitleDetailHost
  def open_plan(socket, query), do: push_navigate(socket, to: PlanQuery.path(query))

  @impl TitleDetailHost
  def download_started(socket), do: TitleDetailHost.close_title(socket)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      profile={@profile}
      profiles={@profiles}
      viewing_layer={assigns[:viewing_layer]}
      features={@features}
      flash={@flash}
      current_path="/discovery"
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <:overlays>
        <DetailPanel.detail_panel
          detail={@title_detail}
          state={@modal_state}
          armed_gesture={@armed_gesture}
          today={@today}
          review?={:social in @features}
          spoiler_free={@spoiler_free}
          letterboxd_links={@letterboxd_links}
          tmdb_ready={@tmdb_ready}
          finished_id={@finished_id}
        />
        <ReviewModal.review_modal
          subject={@review_subject}
          poster_url={@review_poster_url}
          sentiment={@review_sentiment}
          relay_counts={@review_relay_counts}
        />
      </:overlays>
      <FeatureOff.feature_off
        :if={:discovery not in @features}
        id="discovery-off"
        feature={Features.get(:discovery)}
      />
      <%!-- The modal's params are modal state: stripped from the remembered
            URL so leaving the page closes the modal rather than reopening
            it on return. --%>
      <div
        :if={:discovery in @features}
        class="relative"
        data-nav-default-zone="discovery"
        data-nav-transient-params="title,entity,view,activity"
      >
        <.page_header title="Discovery" />
        <div class="space-y-10">
          <%!-- Each shelf's section is its vertical reveal subject, as on
                Home: a reveal shows the heading with the row. --%>
          <section
            :if={@new_releases != []}
            data-row="new-releases"
            data-nav-zone="new_releases"
            data-nav-reveal
            data-nav-reveal-block="end"
          >
            <ShelfHead.shelf_head title="New Releases" />
            <PosterRow.poster_row
              id="new-releases-row"
              items={@new_releases}
              show_play_button={false}
            />
          </section>

          <.empty_state
            :if={@empty_reason == :tmdb_unconfigured}
            id="discovery-empty"
            icon="hero-sparkles"
            headline="Connect TMDB to fill this page"
          >
            New releases, your friends' reviews and your watchlist are all read from TMDB.
            <:action>
              <.button variant="primary" size="sm" navigate={~p"/settings?section=tmdb"}>
                Add a TMDB key
              </.button>
            </:action>
          </.empty_state>
          <.empty_state
            :if={@empty_reason == :tmdb_down}
            id="discovery-empty"
            icon="hero-sparkles"
            headline="New releases arrive when TMDB is back"
          >
            TMDB is not answering right now. The shelf fills on the next refresh once it does.
          </.empty_state>
          <.empty_state
            :if={@empty_reason == :filling}
            id="discovery-empty"
            icon="hero-sparkles"
            headline="New releases are on their way"
          >
            The first refresh is running. Movies that recently became available to stream, rent or buy appear here when it finishes.
          </.empty_state>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
