defmodule MediaCentaurWeb.Components.ReleaseTracking.CaughtUp do
  @moduledoc """
  Where you are in a followed series, shown and adjustable (campaign
  `discovery.md`, M16, decision 6 — Follow means caught up as of now):
  the *Caught up through* row on the title detail's tracking card, under
  the switches (UIDR-042, amended 2026-11-04).

  The point is the person's caught-up pair on their `Watchlist.TitleIntent`,
  the latest aired episode they have seen. Everything at or before it is
  *had*: no want opens for it, the Watchlist row does not count it as out,
  Discovery's Out Now does not place the show for it. The row makes that
  fact visible — a hidden point would be an assumption — and movable:

    * two of the kit's glass selects (`GlassMenu.menu_select`), the season
      and the episode, bounded by the latest aired pair (`latest`): no
      season after it, no episode after it in its season. Choosing a
      season sets the point to that season's last aired episode; choosing
      an episode keeps the season. Their items push `caught_up` with
      `season` and `episode`.
    * the **Caught up** button, the one-press form: `caught_up` with the
      `ref` alone, which the host reads as the latest aired episode.

  The host owns which select is open (`open`, the modal's one open-menu
  slot) through `caught_up_menu_toggle` (`menu` = season | episode) and
  `caught_up_menu_close`; the open list is the `detail_tracking_menu` zone
  under the card's `detail_tracking` region. With no point yet (TMDB has
  aired nothing) the selects show a dash and the button alone acts.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias MediaCentaurWeb.Components.GlassMenu
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :ref, :string, required: true, doc: "the title's `MediaCentaurWeb.TitleRef.param/1`"

  attr :point, :any,
    default: nil,
    doc: "the caught-up pair `{season, episode}`, nil when none is set"

  attr :latest, :any,
    default: nil,
    doc:
      "TMDB's latest aired pair (`ReleaseTracking.Calendar.latest_aired/1`); the selects offer nothing after it"

  attr :season_sizes, :map,
    default: %{},
    doc: "episodes per season by season-number string, specials excluded (`Item.season_sizes`)"

  attr :open, :atom,
    values: [nil, :season, :episode],
    default: nil,
    doc: "which select's list is open"

  attr :class, :any, default: nil, doc: "utilities on the row (its place under the switches)"

  def caught_up_row(assigns) do
    assigns =
      assign(assigns,
        seasons: seasons(assigns.season_sizes, assigns.latest),
        episodes: episodes(assigns.point, assigns.season_sizes, assigns.latest)
      )

    ~H"""
    <div
      id={@id}
      class={["space-y-1", @class]}
      data-component="caught-up-row"
      data-point={point_param(@point)}
    >
      <p class="text-xs text-base-content/55">Caught up through</p>
      <div class="flex flex-wrap items-center gap-2">
        <GlassMenu.menu_select
          id={"#{@id}-season"}
          open={@open == :season}
          on_toggle={JS.push("caught_up_menu_toggle", value: %{menu: "season"})}
          on_close="caught_up_menu_close"
          menu_zone="detail_tracking_menu"
          value_label={season_label(@point)}
          label="Season"
          data-role="season"
        >
          <:item
            :for={{season, last} <- @seasons}
            id={"#{@id}-season-#{season}"}
            event="caught_up"
            values={%{"ref" => @ref, "season" => season, "episode" => last}}
            active={@point != nil and elem(@point, 0) == season}
          >
            Season {season}
          </:item>
        </GlassMenu.menu_select>
        <GlassMenu.menu_select
          id={"#{@id}-episode"}
          open={@open == :episode}
          on_toggle={JS.push("caught_up_menu_toggle", value: %{menu: "episode"})}
          on_close="caught_up_menu_close"
          menu_zone="detail_tracking_menu"
          value_label={episode_label(@point)}
          label="Episode"
          data-role="episode"
        >
          <:item
            :for={episode <- @episodes}
            id={"#{@id}-episode-#{episode}"}
            event="caught_up"
            values={%{"ref" => @ref, "season" => @point && elem(@point, 0), "episode" => episode}}
            active={@point != nil and elem(@point, 1) == episode}
          >
            Episode {episode}
          </:item>
        </GlassMenu.menu_select>
        <.button
          id={"#{@id}-latest"}
          variant="neutral"
          size="xs"
          phx-click="caught_up"
          phx-value-ref={@ref}
          data-nav-item
          tabindex="0"
        >
          Caught up
        </.button>
      </div>
    </div>
    """
  end

  @doc """
  The seasons the select offers, oldest first, each with its last aired
  episode: every sized season up to the latest aired one. Nothing without
  a latest aired pair.
  """
  @spec seasons(%{String.t() => non_neg_integer()}, {pos_integer(), pos_integer()} | nil) ::
          [{pos_integer(), pos_integer()}]
  def seasons(_sizes, nil), do: []

  def seasons(sizes, {latest_season, latest_episode}) do
    sizes
    |> Enum.flat_map(fn {key, size} ->
      case Integer.parse(key) do
        {season, ""} when season >= 1 and season <= latest_season -> [{season, size}]
        _specials_or_later -> []
      end
    end)
    |> Enum.sort()
    |> Enum.flat_map(fn
      {^latest_season, _size} -> [{latest_season, latest_episode}]
      {season, size} when size >= 1 -> [{season, size}]
      _empty -> []
    end)
  end

  @doc """
  The episodes the select offers for the point's season, first to last
  aired: up to the season's size, or to the latest aired episode when the
  point is in its season. Nothing without a point.
  """
  @spec episodes(
          {pos_integer(), pos_integer()} | nil,
          %{String.t() => non_neg_integer()},
          {pos_integer(), pos_integer()} | nil
        ) :: [pos_integer()]
  def episodes(nil, _sizes, _latest), do: []

  def episodes({season, _episode}, sizes, latest) do
    size = Map.get(sizes, Integer.to_string(season), 0)

    last =
      case latest do
        {^season, latest_episode} -> latest_episode
        _other -> size
      end

    if last >= 1, do: Enum.to_list(1..last), else: []
  end

  defp season_label(nil), do: "—"
  defp season_label({season, _episode}), do: "Season #{season}"

  defp episode_label(nil), do: "—"
  defp episode_label({_season, episode}), do: "Episode #{episode}"

  defp point_param(nil), do: nil
  defp point_param({season, episode}), do: "#{season}-#{episode}"
end
