defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  Discovery: the page for titles you do not own yet (campaign
  `discovery.md`) — the second assembled page, shelved like Home, and the
  *choose* stage of a title's life (UIDR-057). An optional feature
  (ADR-081), on by default: its sidebar entry, this page and its shelf
  refresh exist while the `:discovery` flag is on, and the page is its off
  state otherwise.

  **Media search** lives at the top of the page (UIDR-014, amended
  2026-11-01; `Live.MediaSearch`): the omnibox centred over the hero's
  artwork, the placeholder alone (decision 11). While a query owns the
  page the hero, its artwork and the shelves are not rendered and the
  results answer flat over the scrim as title rows (decision 10); a row
  opens the detail, where a result is listed or downloaded. Clearing the
  query is the one dismissal, by the box's X or CLEAR
  (`discovery_behavior.js`).

  Discovery is the second artwork page (UIDR-010 and UIDR-033, amended
  2026-11-01): a full-bleed backdrop painted by the hero canvas from the
  referenced artwork tier, and a hero card for the most notable new
  release — one of the shelf's first five members with a backdrop on disk,
  rotated every seven hours as Home rotates its own (`HeroRotation`) —
  whose actions are **Add to watchlist** (the bookmark at hero size,
  UIDR-039), **Download** (the host's `title_download`, absent once the
  library has it or a plan runs) and **More info** (decision 12). Without
  a hero the page keeps its title and the scrim alone.

  The shelves, in order (decisions 13–16): **Out Now**, the listed titles
  at the home release stage, first because it is the actionable one;
  **New Releases**, `NewReleases.members/0` as a poster row of TMDB
  identities from the store's snapshots; **Reviewed by Friends**, the
  titles friends have reviewed with their social glyphs, while the Social
  feature is on; the **Watchlist** grouped row, In Theaters · Coming Up,
  what waits. Each tile opens the title detail (`TitleDetailHost`) and
  carries the quiet marker a title the library owns or the watchlist
  holds. Opening the page reads the database only; nothing here calls
  TMDB. The shelves follow the membership, the store, the watchlist, the
  library, Activities and the Social flag, debounced
  (`Shelves.reloads?/1`). The verbs on a tile, the hero and media search
  are later milestones of the campaign.

  Empty, the page says why (UIDR-034, `Shelves.empty_reason/3`): TMDB
  never configured is the capability gap with the one action; TMDB down
  with nothing stored, or the first refresh still to run, each say so.

  Input: `data-nav-default-zone="discovery"` selects the `discovery`
  layout — one SHELF zone per shelf, as on Home; no page behaviour until
  search needs CLEAR.
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.TitleDetailHost
  use MediaCentaurWeb.Live.MediaSearch
  use MediaCentaurWeb.Live.SpoilerFreeAware
  use MediaCentaurWeb.Live.LetterboxdLinksAware

  alias MediaCentaur.Acquisition.TitleStates
  alias MediaCentaur.Activities
  alias MediaCentaur.Features
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.NewReleases
  alias MediaCentaur.NewReleases.Member
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TMDB.{ReleaseStages, Store, Title}
  alias MediaCentaur.Watchlist
  alias MediaCentaurWeb.Components.Acquisition.{MediaOmnibox, MediaResults}
  alias MediaCentaurWeb.Components.{ActionToast, DetailPanel, FeatureOff, PosterRow, ShelfHead}
  alias MediaCentaurWeb.Components.{HeroBackdrop, HeroCard}
  alias MediaCentaurWeb.Components.Title.{ToolbarSlots, WatchlistToggle}
  alias MediaCentaurWeb.DiscoveryLive.Shelves
  alias MediaCentaurWeb.HeroRotation
  alias MediaCentaurWeb.Live.{MediaSearch, ReviewModal, Subscriptions, TitleDetailHost}
  alias MediaCentaurWeb.DownloadsLive.PlanQuery

  @reload_debounce_ms 500
  @friends_limit 40

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
       hero: nil,
       hero_slots: nil,
       title_rungs: %{},
       out_now: [],
       new_releases: [],
       friends: [],
       watchlist_groups: [],
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

  # Every read is bounded and local: the membership, the listed titles,
  # the friends' reviews, then for their refs together the store's
  # snapshots, the release stages, the rungs, the library's owners, the
  # acquisition states and the friends' activity rows.
  defp load_shelves(socket) do
    today = socket.assigns.today
    members = NewReleases.members()
    member_refs = Enum.map(members, &Member.ref/1)
    listed = Watchlist.list_watchlist()
    listed_refs = Enum.map(listed, &{&1.intent.tmdb_id, &1.intent.media_type})

    reviewed =
      if :social in socket.assigns.features, do: Activities.reviewed_by_friends(@friends_limit), else: []

    reviewed_refs = Enum.map(reviewed, & &1.ref)

    refs = Enum.uniq(member_refs ++ listed_refs ++ reviewed_refs)
    rungs = Watchlist.rungs()
    owners = ExternalIds.tmdb_owners(refs)
    states = TitleStates.for_refs(refs)

    member_snapshots = Store.snapshots(member_refs)
    new_releases = Shelves.new_releases_items(members, member_snapshots, rungs, owners, states)

    payloads =
      member_refs |> Store.get_many() |> Map.new(fn {ref, record} -> {ref, record.payload} end)

    hero = members |> Shelves.hero_candidates(member_snapshots, payloads) |> HeroRotation.select()

    hero_slots =
      hero &&
        ToolbarSlots.resolve(%{
          rung: Map.get(rungs, hero.ref),
          library_owner_id: Map.get(owners, hero.ref),
          acquisition_state: Map.get(states, hero.ref)
        })

    tracking = Map.new(ReleaseTracking.list_all_items(), &{{&1.tmdb_id, &1.media_type}, &1})

    watchlist =
      Shelves.watchlist_shelves(
        listed,
        ReleaseStages.for_refs(listed_refs, today),
        tracking,
        states,
        today
      )

    friends =
      Shelves.friends_items(reviewed, Activities.activity_for(reviewed_refs), rungs, owners, states)

    tiles =
      length(new_releases) + length(friends) +
        length(watchlist.out_now) + length(watchlist.in_theaters) + length(watchlist.coming_up)

    assign(socket,
      hero: hero,
      hero_slots: hero_slots,
      title_rungs: rungs,
      out_now: watchlist.out_now,
      new_releases: new_releases,
      friends: friends,
      watchlist_groups: [
        %{label: "In Theaters", items: watchlist.in_theaters},
        %{label: "Coming Up", items: watchlist.coming_up}
      ],
      empty_reason:
        Shelves.empty_reason(socket.assigns.tmdb_ready, IntegrationAvailability.up?(:tmdb), tiles)
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
      do: {:noreply, debounce(socket, :reload_timer, :reload_shelves, @reload_debounce_ms)},
      else: {:noreply, socket}
  end

  # --- TitleDetailHost ---

  # A shelf's title is a store identity the host reads on its own; a
  # search result is the page's in-memory snapshot until the store holds
  # it.
  @impl TitleDetailHost
  def page_facts(socket, ref, _params),
    do: {Enum.find(MediaSearch.results(socket), &(Title.ref(&1) == ref)), %{}}

  @impl TitleDetailHost
  def title_detail_path(_socket, []), do: ~p"/discovery"
  def title_detail_path(_socket, query), do: ~p"/discovery?#{query}"

  @impl TitleDetailHost
  def open_plan(socket, query), do: push_navigate(socket, to: PlanQuery.path(query))

  @impl TitleDetailHost
  def download_started(socket), do: TitleDetailHost.close_title(socket)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :search_owns?, MediaSearch.owns_page?(assigns))

    ~H"""
    <Layouts.app
      profile={@profile}
      profiles={@profiles}
      viewing_layer={assigns[:viewing_layer]}
      features={@features}
      flash={@flash}
      current_path="/discovery"
      full_width
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <:overlays>
        <%!-- Before the detail: the input system takes the first open
              [data-detail-mode=modal] in DOM order as the active overlay, so the
              raised Review modal must precede the detail it opens over. --%>
        <ReviewModal.review_modal state={@review} armed_gesture={@armed_gesture} />
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
        data-page-behavior="discovery"
        data-nav-default-zone="discovery"
        data-nav-transient-params="title,entity,view,activity"
      >
        <%!-- Page atmosphere, as Home's: the backdrop painted by the hero
              canvas fades into base-100; the side dim continues down the
              page so every shelf head sits on the same calm band. While a
              query owns the page the artwork goes with the hero: the
              results read over the scrim alone (decision 10). --%>
        <div
          :if={@hero && @hero.backdrop_url && !@search_owns?}
          class="page-backdrop"
          aria-hidden="true"
        >
          <HeroBackdrop.hero_backdrop backdrop_url={@hero.backdrop_url} />
        </div>
        <div class="page-side-dim" aria-hidden="true"></div>

        <%!-- Media search, centred in the backdrop's top band: the one
              control on the page that is not a tile. Without TMDB the box
              cannot answer and the capability gap below says so. --%>
        <div :if={@tmdb_ready} class="relative z-[3] pb-4">
          <MediaOmnibox.media_omnibox query={@omnibox_query} />
        </div>

        <%!-- A query owns the page: the results, flat, in the title rows
              every search surface draws; nothing else until it clears. --%>
        <div :if={@search_owns?} class="relative z-[2] max-w-6xl mx-auto">
          <MediaResults.media_results
            query={@omnibox_query}
            results={@omnibox_results}
            searching?={@omnibox_searching?}
            metadata_available={@tmdb_ready}
            scope={@omnibox_scope}
            today={@today}
            title_rungs={@title_rungs}
            in_library_refs={@in_library_refs}
            social_activity_by_ref={@social_activity_by_ref}
          />
        </div>

        <%!-- The hero: a plain full-bleed track, not a ScrollRow (one item
              has nothing to scroll); `data-nav-reveal` shows the whole hero
              when one of its actions takes focus. --%>
        <div
          :if={@hero && !@search_owns?}
          class="relative z-[1] -mx-6 -mt-6"
          data-nav-zone="hero"
          data-nav-reveal
        >
          <div class="row-scroll row-scroll-hero">
            <div class="w-full" data-row-item>
              <HeroCard.hero_card item={@hero}>
                <:actions>
                  <WatchlistToggle.watchlist_toggle
                    id="discovery-hero-list"
                    rung={@hero_slots.rung}
                    event="set_rung"
                    size="lg"
                    phx-value-ref={@hero.id}
                    data-entity-id={@hero.id}
                  />
                  <.button
                    :if={@hero_slots.download == :download}
                    id="discovery-hero-download"
                    variant="secondary"
                    size="lg"
                    class="text-white"
                    phx-click="title_download"
                    phx-value-ref={@hero.id}
                    data-nav-item
                    data-entity-id={@hero.id}
                    tabindex="0"
                  >
                    <.icon name="hero-arrow-down-tray" class="size-5" /> Download
                  </.button>
                  <.button
                    id="discovery-hero-more"
                    variant="secondary"
                    size="lg"
                    class="text-white"
                    phx-click="open_title"
                    phx-value-ref={@hero.id}
                    data-nav-item
                    data-entity-id={@hero.id}
                    tabindex="0"
                  >
                    <.icon name="hero-information-circle-mini" class="size-5" /> More info
                  </.button>
                </:actions>
              </HeroCard.hero_card>
            </div>
          </div>
        </div>

        <.page_header :if={!@hero && !@search_owns?} title="Discovery" />
        <%!-- Ignore shows no state to reverse, so it gets an undo toast; the
              host keeps the undo (`:ignore_undo`), this page draws it. --%>
        <ActionToast.action_toast
          :if={@ignore_undo}
          id="ignore-undo"
          message={"#{@ignore_undo.title.name} ignored"}
          action="Undo"
          on_action={JS.push("ignore_undo")}
          on_dismiss={JS.push("ignore_undo_dismiss") |> hide("#ignore-undo")}
        />
        <div :if={!@search_owns?} class={["relative z-[2] space-y-10", @hero && "-mt-8"]}>
          <%!-- Each shelf's section is its vertical reveal subject, as on
                Home: a reveal shows the heading with the row; every shelf
                but the last also shows the one below it. --%>
          <section
            :if={@out_now != []}
            data-row="out-now"
            data-nav-zone="out_now"
            data-nav-reveal
            data-nav-reveal-block="end"
            data-nav-reveal-next
          >
            <ShelfHead.shelf_head title="Out Now" />
            <PosterRow.poster_row id="out-now-row" items={@out_now} show_play_button={false} />
          </section>

          <section
            :if={@new_releases != []}
            data-row="new-releases"
            data-nav-zone="new_releases"
            data-nav-reveal
            data-nav-reveal-block="end"
            data-nav-reveal-next
          >
            <ShelfHead.shelf_head title="New Releases" />
            <PosterRow.poster_row
              id="new-releases-row"
              items={@new_releases}
              show_play_button={false}
            />
          </section>

          <section
            :if={:social in @features and @friends != []}
            data-row="friends"
            data-nav-zone="friends"
            data-nav-reveal
            data-nav-reveal-block="end"
            data-nav-reveal-next
          >
            <ShelfHead.shelf_head title="Reviewed by Friends" see_all_href="/social" />
            <PosterRow.poster_row id="friends-row" items={@friends} show_play_button={false} />
          </section>

          <section
            :if={Enum.any?(@watchlist_groups, &(&1.items != []))}
            data-row="watchlist"
            data-nav-zone="watchlist"
            data-nav-reveal
            data-nav-reveal-block="end"
          >
            <ShelfHead.shelf_head title="Watchlist" />
            <PosterRow.grouped_poster_row
              id="watchlist-row"
              groups={@watchlist_groups}
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
