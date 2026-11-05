defmodule MediaCentaurWeb.WatchlistLive.Logic do
  @moduledoc """
  The Watchlist page's pure logic (ADR-030): the rows from the reads the
  page makes, each title's `State` from the one read that knows it, the
  groups by rung, the filter and the search, the diagnosed empty reason,
  and which broadcasts reload the page.

  A title's state comes from its release calendar when the title is
  followed (a tracking item exists: `ReleaseTracking.list_all_items/0`
  with releases, read through `ReleaseTracking.Calendar.read/3` with the
  intent's caught-up point — *had* is the library or the point, M16) and
  from its release stage when it is List-only (`TMDB.ReleaseStages`), a
  movie reading its stage either way — one `State` value, whichever read
  filled it.
  """

  alias MediaCentaur.ReleaseTracking.Calendar
  alias MediaCentaur.ReleaseTracking.Item, as: TrackingItem
  alias MediaCentaur.TitleArtwork
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Watchlist
  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaurWeb.Components.Title.Logic, as: TitleLogic
  alias MediaCentaurWeb.Components.Watchlist.Row.{Item, State}
  alias MediaCentaurWeb.TitleRef

  @type ref :: MediaCentaur.TMDB.Store.ref()
  @type filter :: :all | :movies | :series
  @type group_id :: :grab | :follow | :list | :between_seasons | :ignored | :watched
  @type group :: %{id: group_id(), label: String.t(), items: [Item.t()], closed?: boolean()}
  @type empty_reason :: :no_records | :nothing_matches | nil

  @group_order [:grab, :follow, :list, :between_seasons, :ignored, :watched]
  @closed_groups [:between_seasons, :ignored, :watched]

  @doc """
  The groups in page order: Auto-grab, Tracking, On your list, Between
  seasons, Ignored, Series you've watched.
  """
  @spec group_order() :: [group_id()]
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
        poster_url: poster_url(intent.rung, title),
        owned?: owner != nil,
        markers:
          TitleLogic.row_markers(%{
            in_library?: owner != nil,
            acquisition_state: Map.get(acquisition_states, ref)
          }),
        notes: TitleLogic.note_list(intent.note),
        social_activity: Map.get(activity, ref, []),
        state: state(intent, Map.get(tracking, ref), Map.get(stages, ref), Map.get(statuses, ref), today)
      }
    end
  end

  @doc """
  The *Series you've watched* rows: each series the profile watched
  (`Library.watched_tv_series/1`) that has no record (`record_refs`) and
  that TMDB does not mark Ended or Canceled, as an owned row with no rung
  — Off — whose rung control adds it. The title is the store's snapshot
  when `snapshots` holds it, else the library entity's
  (`Title.Logic.snapshot_from_entity/1`); the state reads the series'
  status the way a followed series with nothing dated does.
  """
  @spec candidates([map()], MapSet.t(ref()), %{ref() => Title.t()}, %{
          ref() => MediaCentaur.TMDB.SeriesStatus.status()
        }) :: [Item.t()]
  def candidates(watched, record_refs, snapshots, statuses) do
    for series <- watched,
        %Title{} = entity_title <- [TitleLogic.snapshot_from_entity(series)],
        ref = Title.ref(entity_title),
        not MapSet.member?(record_refs, ref),
        status <- [Map.get(statuses, ref)],
        status not in [:ended, :canceled] do
      title = Map.get(snapshots, ref, entity_title)

      %Item{
        id: "watchlist-row-#{TitleRef.param(ref)}",
        ref: ref,
        title: title,
        rung: nil,
        poster_url: poster_url(nil, title),
        owned?: true,
        markers: TitleLogic.row_markers(%{in_library?: true, acquisition_state: nil}),
        state: %State{kind: quiet_kind(status)}
      }
    end
  end

  # An Ignored record references nothing in the store (ADR-071, amended
  # 2026-11-04), so its row never draws a poster — not even while the
  # snapshot lingers before the sweep.
  defp poster_url(:ignored, _title), do: nil
  defp poster_url(_rung, title), do: TitleArtwork.urls(title, %{}, :w92).poster_url

  @doc """
  A title's `State`: Ignored says so; a followed series reads its
  calendar through `Calendar.read/3` with the record's caught-up point —
  aired episodes not had, else the next dated one, else TMDB's status
  word, the point carried on the state so the row can say where the
  person stands; a movie, or a List-only series, reads its release stage.
  """
  @spec state(
          TitleIntent.t(),
          TrackingItem.t() | nil,
          MediaCentaur.TMDB.ReleaseStages.t() | nil,
          MediaCentaur.TMDB.SeriesStatus.status() | nil,
          Date.t()
        ) :: State.t()
  def state(%TitleIntent{rung: :ignored}, _item, _stage, _status, _today), do: %State{kind: :ignored}

  def state(
        %TitleIntent{media_type: :tv_series} = intent,
        %TrackingItem{releases: releases} = item,
        _stage,
        status,
        today
      )
      when is_list(releases) do
    caught_up = TitleIntent.caught_up(intent)

    case Calendar.read(item, caught_up, today) do
      %{out: [_ | _] = out} ->
        latest = out |> Enum.map(& &1.air_date) |> Enum.max(Date)
        %State{kind: :episodes_out, count: length(out), date: latest, caught_up: caught_up}

      %{next: %Date{} = next} ->
        %State{kind: :next_episode, date: next, caught_up: caught_up}

      %{next: nil} ->
        %State{kind: quiet_kind(status), caught_up: caught_up}
    end
  end

  def state(_intent, _item, stage, _status, _today), do: from_stage(stage)

  defp quiet_kind(:returning), do: :between_seasons
  defp quiet_kind(:ended), do: :ended
  defp quiet_kind(:canceled), do: :canceled
  defp quiet_kind(_status), do: :nothing_scheduled

  defp from_stage(%{stage: :home, date: date}), do: %State{kind: :out_now, date: date}
  defp from_stage(%{stage: :theatrical, date: date}), do: %State{kind: :in_theaters, date: date}
  defp from_stage(%{stage: :unreleased, date: date}), do: %State{kind: :coming_up, date: date}
  defp from_stage(_unknown), do: %State{kind: :undated}

  @doc """
  Whether the row's state block offers *Caught up*: a followed series with
  episodes out. The one press that says the person has seen them.
  """
  @spec caught_up_offered?(Item.t()) :: boolean()
  def caught_up_offered?(%Item{rung: rung, state: %State{kind: :episodes_out}}),
    do: TitleIntent.follows_releases?(rung)

  def caught_up_offered?(_item), do: false

  @doc """
  The page's title count — every record but the Ignored ones, which are
  not on the list, and none of the series you've watched, which have no
  record (both groups are closed by default and counted on their heads).
  """
  @spec listed_count([Item.t()]) :: non_neg_integer()
  def listed_count(items), do: Enum.count(items, &(&1.rung not in [nil, :ignored]))

  @doc """
  Whether a closed group's disclosure is open: closed on every visit,
  opened by the person (`toggled?`) or held open while a search is on —
  a match inside a closed group would be invisible.
  """
  @spec group_open?(boolean(), String.t()) :: boolean()
  def group_open?(toggled?, query), do: toggled? or String.trim(query) != ""

  @doc """
  The items by group in page order, each group's rows by urgency —
  episodes out (most first), then out now (newest first), then a date
  ahead (nearest first), then the rest by name — an empty group dropped.
  A row's group is its rung, except a followed series between seasons
  (*Between seasons*) and a series with no record (*Series you've
  watched*); Between seasons, Ignored and Series you've watched are
  closed by default.
  """
  @spec groups([Item.t()]) :: [group()]
  def groups(items) do
    by_group = Enum.group_by(items, &group_of/1)

    for id <- @group_order, rows = Map.get(by_group, id, []), rows != [] do
      %{
        id: id,
        label: group_label(id),
        items: Enum.sort_by(rows, &urgency/1),
        closed?: id in @closed_groups
      }
    end
  end

  defp group_of(%Item{rung: nil}), do: :watched

  defp group_of(%Item{rung: rung, state: %State{kind: :between_seasons}}) when rung in [:follow, :grab],
    do: :between_seasons

  defp group_of(%Item{rung: rung}), do: rung

  defp group_label(:between_seasons), do: State.kind_word(:between_seasons)
  defp group_label(:watched), do: "Series you've watched"
  defp group_label(rung), do: TitleLogic.rung_word(rung)

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

    Enum.filter(items, fn item ->
      type_matches?(item, filter) and
        (needle == "" or String.contains?(String.downcase(item.title.name || ""), needle))
    end)
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
