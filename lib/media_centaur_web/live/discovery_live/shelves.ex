defmodule MediaCentaurWeb.DiscoveryLive.Shelves do
  @moduledoc """
  The pure half of the Discovery page (ADR-030): the shelf items from the
  reads the page made, the diagnosed reason the page is empty, and which
  broadcasts call for a reload. Nothing here touches the database or the
  network; `TitleArtwork.urls/3` reads the artwork cache's directory only.
  """

  alias MediaCentaur.NewReleases.Member
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TitleArtwork
  alias MediaCentaurWeb.Components.PosterRow
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.TitleRef

  @typedoc """
  Why the page is empty: TMDB never configured (the capability gap,
  UIDR-034), TMDB down with nothing stored yet, the first refresh still
  to run; nil when there is something to show.
  """
  @type empty_reason :: :tmdb_unconfigured | :tmdb_down | :filling | nil

  @doc """
  The New Releases shelf: one poster tile per member in shelf order, from
  the store's snapshot. A member the store has no record for yet is not
  drawn (the refresh or the check job stores it and the page follows);
  an ignored title is dropped, as the Feed drops it. The marker is the
  first of `Title.Logic.row_markers/2`'s words: In library, an
  acquisition state, or the rung.
  """
  @spec new_releases_items(
          [Member.t()],
          %{MediaCentaur.TMDB.Store.ref() => Title.t()},
          %{MediaCentaur.TMDB.Store.ref() => atom()},
          %{MediaCentaur.TMDB.Store.ref() => String.t()},
          %{MediaCentaur.TMDB.Store.ref() => atom()}
        ) :: [PosterRow.Item.t()]
  def new_releases_items(members, snapshots, rungs, owners, acquisition_states) do
    Enum.flat_map(members, fn member ->
      ref = Member.ref(member)
      rung = Map.get(rungs, ref)

      case Map.get(snapshots, ref) do
        nil -> []
        _title when rung == :ignored -> []
        title -> [item(ref, title, Map.get(owners, ref), Map.get(acquisition_states, ref), rung)]
      end
    end)
  end

  defp item(ref, %Title{} = title, owner_id, acquisition_state, rung) do
    facts = %{in_library?: owner_id != nil, acquisition_state: acquisition_state, rung: rung}

    %PosterRow.Item{
      id: TitleRef.param(ref),
      ref: ref,
      name: title.name,
      year: title.year,
      poster_url: TitleArtwork.urls(title, %{}, :w342).poster_url,
      marker: facts |> Logic.row_markers(false) |> List.first()
    }
  end

  @doc """
  The diagnosed reason the page is empty, from whether TMDB is configured
  (`Capabilities.tmdb_ready?/0`), whether it is up
  (`IntegrationAvailability.up?/1`) and how many tiles the page has.
  """
  @spec empty_reason(boolean(), boolean(), non_neg_integer()) :: empty_reason()
  def empty_reason(false, _up?, _tiles), do: :tmdb_unconfigured
  def empty_reason(true, _up?, tiles) when tiles > 0, do: nil
  def empty_reason(true, false, 0), do: :tmdb_down
  def empty_reason(true, true, 0), do: :filling

  @doc """
  Whether a broadcast changes what the shelf shows: the membership, a
  stored title, a rung, the library's holdings, or TMDB's availability
  (the empty state's wording). The title detail host subscribes the page
  to the store, the watchlist and the library; the page adds the
  membership and availability topics.
  """
  @spec reloads?(term()) :: boolean()
  def reloads?({:new_releases_changed}), do: true
  def reloads?({:tmdb_title_changed, _ref}), do: true
  def reloads?({:title_intent_changed, _event}), do: true
  def reloads?({:entities_changed, _event}), do: true
  def reloads?({:integration_availability_changed, :tmdb, _state}), do: true
  def reloads?(_message), do: false
end
