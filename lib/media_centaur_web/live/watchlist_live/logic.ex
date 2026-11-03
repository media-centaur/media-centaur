defmodule MediaCentaurWeb.WatchlistLive.Logic do
  @moduledoc """
  The Watchlist page's pure logic (ADR-030): the rows from the reads the
  page makes, each title's `State` from the one read that knows it, the
  groups by rung, the filter and the search, the diagnosed empty reason,
  and which broadcasts reload the page.

  A title's state comes from its release calendar when the title is
  followed (a tracking item exists: `ReleaseTracking.list_all_items/0`
  with releases) and from its release stage when it is List-only
  (`TMDB.ReleaseStages`), a movie reading its stage either way — one
  `State` value, whichever read filled it. *Had* is the calendar's
  `in_library` flag until M16 adds the caught-up point.
  """

  alias MediaCentaur.ReleaseTracking.Item, as: TrackingItem
  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaur.TitleArtwork
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Watchlist
  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaurWeb.Components.Title.Logic, as: TitleLogic
  alias MediaCentaurWeb.Components.Watchlist.Row.{Item, State}
  alias MediaCentaurWeb.TitleRef

  @type ref :: MediaCentaur.TMDB.Store.ref()
  @type filter :: :all | :movies | :series
  @type group :: %{rung: TitleIntent.rung(), label: String.t(), items: [Item.t()]}
  @type empty_reason :: :no_records | :nothing_matches | nil

  @group_order [:grab, :follow, :list, :ignored]

  @doc "The groups' rungs in page order: Auto-grab, Tracking, On your list, Ignored."
  @spec group_order() :: [TitleIntent.rung()]
  def group_order, do: @group_order

  @doc """
  One `Item` per record, from `Watchlist.list_intents/0` and, by ref, the
  tracking items, the release stages, the series statuses, the
  acquisition states and the social activity rows.
  """
  @spec items(
          [Watchlist.listed()],
          %{ref() => TrackingItem.t()},
          %{ref() => MediaCentaur.TMDB.ReleaseStages.t()},
          %{ref() => MediaCentaur.TMDB.SeriesStatus.status()},
          %{ref() => atom()},
          %{ref() => [map()]},
          Date.t()
        ) :: [Item.t()]
  def items(listed, tracking, stages, statuses, acquisition_states, activity, today) do
    for %{intent: %TitleIntent{title: %Title{} = title} = intent, library_owner_id: owner} <- listed do
      ref = {intent.tmdb_id, intent.media_type}

      %Item{
        id: "watchlist-row-#{TitleRef.param(ref)}",
        ref: ref,
        title: title,
        rung: intent.rung,
        poster_url: TitleArtwork.urls(title, %{}, :w92).poster_url,
        owned?: owner != nil,
        markers:
          TitleLogic.row_markers(%{
            in_library?: owner != nil,
            acquisition_state: Map.get(acquisition_states, ref)
          }),
        notes: TitleLogic.note_list(intent.note),
        social_activity: Map.get(activity, ref, []),
        state:
          state(
            intent.rung,
            intent.media_type,
            Map.get(tracking, ref),
            Map.get(stages, ref),
            Map.get(statuses, ref),
            today
          )
      }
    end
  end

  @doc """
  A title's `State`: Ignored says so; a followed series reads its
  calendar — aired episodes not had, else the next dated one, else
  TMDB's status word; a movie, or a List-only series, reads its release
  stage.
  """
  @spec state(
          TitleIntent.rung(),
          Title.media_type(),
          TrackingItem.t() | nil,
          MediaCentaur.TMDB.ReleaseStages.t() | nil,
          MediaCentaur.TMDB.SeriesStatus.status() | nil,
          Date.t()
        ) :: State.t()
  def state(:ignored, _media_type, _item, _stage, _status, _today), do: %State{kind: :ignored}

  def state(_rung, :tv_series, %TrackingItem{releases: releases}, _stage, status, today)
      when is_list(releases) do
    aired = Enum.filter(releases, &(Release.released?(&1, today) and not &1.in_library))

    cond do
      aired != [] ->
        latest = aired |> Enum.map(& &1.air_date) |> Enum.max(Date)
        %State{kind: :episodes_out, count: length(aired), date: latest}

      next = next_dated(releases, today) ->
        %State{kind: :next_episode, date: next}

      true ->
        %State{kind: quiet_kind(status)}
    end
  end

  def state(_rung, _media_type, _item, stage, _status, _today), do: from_stage(stage)

  defp next_dated(releases, today) do
    releases
    |> Enum.map(& &1.air_date)
    |> Enum.filter(&(&1 != nil and Date.after?(&1, today)))
    |> Enum.min(Date, fn -> nil end)
  end

  defp quiet_kind(:returning), do: :between_seasons
  defp quiet_kind(:ended), do: :ended
  defp quiet_kind(:canceled), do: :canceled
  defp quiet_kind(_status), do: :nothing_scheduled

  defp from_stage(%{stage: :home, date: date}), do: %State{kind: :out_now, date: date}
  defp from_stage(%{stage: :theatrical, date: date}), do: %State{kind: :in_theaters, date: date}
  defp from_stage(%{stage: :unreleased, date: date}), do: %State{kind: :coming_up, date: date}
  defp from_stage(_unknown), do: %State{kind: :undated}

  @doc """
  The items by rung in page order, each group's rows by urgency —
  episodes out (most first), then out now (newest first), then a date
  ahead (nearest first), then the rest by name — an empty group dropped.
  """
  @spec groups([Item.t()]) :: [group()]
  def groups(items) do
    by_rung = Enum.group_by(items, & &1.rung)

    for rung <- @group_order, rows = Map.get(by_rung, rung, []), rows != [] do
      %{rung: rung, label: TitleLogic.rung_word(rung), items: Enum.sort_by(rows, &urgency/1)}
    end
  end

  defp urgency(%Item{state: state, title: title}) do
    name = String.downcase(title.name || "")

    case state do
      %State{kind: :episodes_out, count: count} ->
        {0, -count, name}

      %State{kind: :out_now, date: date} ->
        {1, -days(date), name}

      %State{kind: kind, date: %Date{} = date} when kind in [:next_episode, :in_theaters, :coming_up] ->
        {2, days(date), name}

      _quiet ->
        {3, 0, name}
    end
  end

  defp days(nil), do: 0
  defp days(%Date{} = date), do: Date.diff(date, ~D[2000-01-01])

  @doc "The items the filter and the query leave: a type, and a case-blind match on the name."
  @spec narrow([Item.t()], filter(), String.t()) :: [Item.t()]
  def narrow(items, filter, query) do
    needle = query |> String.trim() |> String.downcase()

    items
    |> Enum.filter(&type_matches?(&1, filter))
    |> Enum.filter(&(needle == "" or String.contains?(String.downcase(&1.title.name || ""), needle)))
  end

  defp type_matches?(_item, :all), do: true
  defp type_matches?(%Item{title: %Title{media_type: :movie}}, :movies), do: true
  defp type_matches?(%Item{title: %Title{media_type: :tv_series}}, :series), do: true
  defp type_matches?(_item, _filter), do: false

  @doc "Marks the one row whose rung menu is open; `nil` closes every menu."
  @spec mark_open([Item.t()], String.t() | nil) :: [Item.t()]
  def mark_open(items, open_ref) do
    Enum.map(items, &%{&1 | menu_open?: open_ref != nil and TitleRef.param(&1.ref) == open_ref})
  end

  @doc """
  Why the page is empty (UIDR-034): no record at all, or the filter and
  the query leave nothing; nil when rows show.
  """
  @spec empty_reason([Item.t()], [Item.t()]) :: empty_reason()
  def empty_reason([], _shown), do: :no_records
  def empty_reason(_all, []), do: :nothing_matches
  def empty_reason(_all, _shown), do: nil

  @doc "The filter from its segmented-control choice; anything else is All."
  @spec parse_filter(String.t()) :: filter()
  def parse_filter("movies"), do: :movies
  def parse_filter("series"), do: :series
  def parse_filter(_choice), do: :all

  @doc "The rung `rung_choice` names: the three list rungs, Ignored, or Off."
  @spec parse_choice(String.t()) :: TitleIntent.rung() | :off | nil
  def parse_choice("list"), do: :list
  def parse_choice("follow"), do: :follow
  def parse_choice("grab"), do: :grab
  def parse_choice("ignored"), do: :ignored
  def parse_choice("off"), do: :off
  def parse_choice(_choice), do: nil

  @doc """
  Whether a broadcast changes the page's rows: a rung moving, a calendar
  changing, the library gaining or losing an owner, a stored title
  changing, a friend's activity, or an acquisition event (the markers).
  """
  @spec reloads?(term()) :: boolean()
  def reloads?({:title_intent_changed, _event}), do: true
  def reloads?({:releases_updated, _ids}), do: true
  def reloads?({:item_removed, _tmdb_id, _type}), do: true
  def reloads?({:entities_changed, _event}), do: true
  def reloads?({:tmdb_title_changed, _ref}), do: true
  def reloads?({:activity_received, _event}), do: true
  def reloads?({:activity_sent, _event}), do: true
  def reloads?({:activity_deleted, _event}), do: true

  def reloads?(%{__struct__: module}),
    do: String.starts_with?(Atom.to_string(module), "Elixir.MediaCentaur.Acquisition.")

  def reloads?(_message), do: false
end
