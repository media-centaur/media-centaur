defmodule MediaCentaurWeb.Components.Watchlist.CaughtUpPanel do
  @moduledoc """
  The **caught-up panel**: where you stand in a followed series, shown
  and movable, anchored under a Watchlist row's state block (campaign
  `discovery.md`, M16, amended 2026-11-08). The row's *Caught up* button
  is the one-press answer when episodes are out; the panel is for every
  other move, on a series of two seasons or forty: a season select
  (`GlassMenu.menu_select`, every season newest first with its year and
  size), the jumps *Latest aired* and *Nothing yet*, the chosen season's
  episodes as a grid of chips that scrolls when the season is long, a
  legend, and Cancel / Set point. A chip only selects — the readout and
  the chips' colours follow the selection at once — and Set point writes
  it (`caught_up_panel_set`); Cancel, a click outside or BACK leave the
  point as it was.

  Pure rendering of a `CaughtUpLogic.Panel`; the Watchlist page owns the
  panel and every event: `caught_up_panel_season` (`season`),
  `caught_up_season_menu_toggle` / `caught_up_season_menu_close`,
  `caught_up_panel_pick` (`season`, `episode`), `caught_up_panel_latest`,
  `caught_up_panel_nothing`, `caught_up_panel_set`, `caught_up_panel_close`.
  Chips: `.button` with the state as its variant — `secondary` had,
  `primary` the point (`aria-pressed`), `risky` out, `dismiss` unaired
  (disabled: the point names an episode that has aired); `data-state`
  carries it. An unstored season shows a loading line until the store
  has it, and says so when TMDB does not answer.

  Input: the panel is an overlay with regions (`data-nav-overlay="caught_up"`,
  dismissed by `caught_up_panel_close`): `caught_up_head` (TOOLBAR: the
  season trigger, Latest aired, Nothing yet) over `caught_up_chips` (SHELF:
  the chips, walked by geometry, entered on the selected one) over
  `caught_up_foot` (TOOLBAR: Cancel, Set point); the open season list is
  `caught_up_season_menu`, nested in the head. BACK closes the panel from
  any region but the open list, which it closes first; the cursor returns
  to the row.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.GlassMenu
  alias MediaCentaurWeb.WatchlistLive.CaughtUpLogic
  alias MediaCentaurWeb.WatchlistLive.CaughtUpLogic.Panel
  alias Phoenix.LiveView.JS

  attr :panel, Panel, required: true
  attr :today, Date, required: true, doc: "the date a chip's aired-or-not is read against"

  def caught_up_panel(assigns) do
    panel = assigns.panel

    assigns =
      assign(assigns,
        season: Enum.find(panel.seasons, &(&1.number == panel.season)),
        change: CaughtUpLogic.change(panel)
      )

    ~H"""
    <div
      id={@panel.id}
      class="glass-menu-panel glass-surface rounded-xl p-4 space-y-3 text-left"
      role="dialog"
      aria-label="Caught up through"
      data-component="caught-up-panel"
      data-detail-mode="modal"
      data-nav-overlay="caught_up"
      data-dismiss-event="caught_up_panel_close"
      data-selection={selection_param(@panel.selection)}
      phx-click={%JS{}}
    >
      <div class="flex items-baseline justify-between gap-4">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/55">
          Caught up through
        </h3>
        <p class="text-sm font-medium text-base-content/80" data-role="selection">
          {CaughtUpLogic.selection_words(@panel)}
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2" data-nav-zone="caught_up_head">
        <GlassMenu.menu_select
          :if={@season}
          id={"#{@panel.id}-season"}
          open={@panel.menu_open?}
          on_toggle="caught_up_season_menu_toggle"
          on_close="caught_up_season_menu_close"
          menu_zone="caught_up_season_menu"
          value_label={CaughtUpLogic.season_label(@season)}
          label="Season"
          data-role="season"
        >
          <:item
            :for={season <- @panel.seasons}
            id={"#{@panel.id}-season-#{season.number}"}
            event="caught_up_panel_season"
            values={%{"season" => season.number}}
            active={season.number == @panel.season}
          >
            {CaughtUpLogic.season_label(season)}
          </:item>
        </GlassMenu.menu_select>
        <.button
          :if={@panel.latest}
          id={"#{@panel.id}-latest"}
          variant="dismiss"
          size="xs"
          phx-click="caught_up_panel_latest"
          data-nav-item
          tabindex="0"
        >
          Latest aired
        </.button>
        <.button
          id={"#{@panel.id}-nothing"}
          variant="dismiss"
          size="xs"
          phx-click="caught_up_panel_nothing"
          data-nav-item
          tabindex="0"
        >
          Nothing yet
        </.button>
      </div>

      <p :if={@panel.seasons == []} class="text-sm text-base-content/55">
        TMDB lists no seasons for this series yet.
      </p>
      <p :if={@panel.episodes == :loading and @panel.season} class="text-sm text-base-content/55">
        Reading season {@panel.season} from TMDB…
      </p>
      <p :if={@panel.episodes == :unavailable} class="text-sm text-base-content/55">
        TMDB did not answer for season {@panel.season}. Choose it again to retry.
      </p>
      <div
        :if={is_list(@panel.episodes)}
        class="caught-up-chips"
        data-nav-zone="caught_up_chips"
        data-role="chips"
      >
        <.chip
          :for={episode <- @panel.episodes}
          panel={@panel}
          episode={episode}
          state={CaughtUpLogic.chip(@panel, episode, @today)}
          today={@today}
        />
      </div>

      <p class="text-xs text-base-content/55">
        The last episode you have seen. Blue chips you have seen or have, amber ones are out and
        not had, grey ones have not aired. Auto-grab wants everything after the point.
      </p>

      <div class="flex justify-end gap-2" data-nav-zone="caught_up_foot">
        <.button
          id={"#{@panel.id}-cancel"}
          variant="dismiss"
          size="sm"
          phx-click="caught_up_panel_close"
          data-nav-item
          tabindex="0"
        >
          Cancel
        </.button>
        <.button
          id={"#{@panel.id}-set"}
          variant="primary"
          size="sm"
          phx-click="caught_up_panel_set"
          disabled={@change == :unchanged}
          data-nav-item
          tabindex="0"
        >
          Set point
        </.button>
      </div>
    </div>
    """
  end

  attr :panel, Panel, required: true
  attr :episode, :map, required: true, doc: "a `CaughtUpLogic.episode()`: number, air_date, name"

  attr :state, :atom,
    required: true,
    doc: "the chip's `CaughtUpLogic.chip_state()`: point, had, out or unaired"

  attr :today, Date, required: true

  defp chip(assigns) do
    ~H"""
    <.button
      id={"#{@panel.id}-chip-#{@panel.season}-#{@episode.number}"}
      variant={chip_variant(@state)}
      size="xs"
      class="caught-up-chip"
      phx-click="caught_up_panel_pick"
      phx-value-season={@panel.season}
      phx-value-episode={@episode.number}
      aria-pressed={to_string(@state == :point)}
      aria-label={chip_name(@episode)}
      disabled={@state == :unaired}
      data-state={@state}
      data-nav-item
      tabindex="0"
    >
      <span>E{Format.pad2(@episode.number)}</span>
      <span class="caught-up-chip-date">{Format.date_chip(:day, @episode.air_date, @today) || "—"}</span>
    </.button>
    """
  end

  defp chip_variant(:point), do: "primary"
  defp chip_variant(:had), do: "secondary"
  defp chip_variant(:out), do: "risky"
  defp chip_variant(:unaired), do: "dismiss"

  defp chip_name(%{number: number, name: nil}), do: "Episode #{number}"
  defp chip_name(%{number: number, name: name}), do: "Episode #{number} · #{name}"

  defp selection_param(:none), do: "none"
  defp selection_param({season, episode}), do: "#{season}-#{episode}"
end
