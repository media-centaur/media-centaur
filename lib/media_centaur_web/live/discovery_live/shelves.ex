defmodule MediaCentaurWeb.DiscoveryLive.Shelves do
  @moduledoc """
  The pure half of the Discovery page (ADR-030): the shelf items from the
  reads the page made, the diagnosed reason the page is empty, and which
  broadcasts call for a reload. Nothing here touches the database or the
  network; `TitleArtwork.urls/3` reads the artwork cache's directory only.
  """

  alias MediaCentaur.Format
  alias MediaCentaur.NewReleases.Member
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Calendar
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TitleArtwork
  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaurWeb.Components.{HeroCard, PosterRow}
  alias MediaCentaurWeb.Components.Title.{Grade, Logic, SocialWords, ToolbarSlots}
  alias MediaCentaurWeb.LibraryFormatters
  alias MediaCentaurWeb.TitleRef

  @hero_pool 5

  @typedoc "A listed title as `Watchlist.list_watchlist/0` returns it."
  @type listed :: %{intent: MediaCentaur.Watchlist.TitleIntent.t(), library_owner_id: String.t() | nil}

  @typedoc "A release stage with its date, as `TMDB.ReleaseStages.for_refs/2` returns it."
  @type staged :: %{stage: atom(), date: Date.t() | nil}

  @typedoc "The watchlist split by release stage: each a list of tiles in shelf order."
  @type watchlist_shelves :: %{
          out_now: [PosterRow.Item.t()],
          in_theaters: [PosterRow.Item.t()],
          coming_up: [PosterRow.Item.t()]
        }

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
  first of `Title.Logic.row_markers/1`'s words: In library, an
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

  @doc """
  The hero's pool (decision 1): the first #{@hero_pool} New Releases
  members whose backdrop the referenced artwork tier holds on disk — the
  canvas decodes a local file, never a hotlink — each as a `HeroCard.Item`
  from the store's record: the lockup or name, year, genres, runtime,
  overview, the local backdrop and logo. `HeroRotation.select/2` picks
  one of them per seven-hour block, as Home picks among its candidates.
  """
  @spec hero_candidates(
          [Member.t()],
          %{MediaCentaur.TMDB.Store.ref() => Title.t()},
          %{MediaCentaur.TMDB.Store.ref() => map()}
        ) :: [HeroCard.Item.t()]
  def hero_candidates(members, snapshots, payloads) do
    members
    |> Enum.flat_map(fn member ->
      ref = Member.ref(member)

      with %Title{} = title <- Map.get(snapshots, ref),
           %{} = payload <- Map.get(payloads, ref),
           %{backdrop_url: "/media-images/" <> _} = urls <- TitleArtwork.urls(title, %{}, :w342) do
        [hero_item(ref, title, payload, urls)]
      else
        _absent_or_hotlinked -> []
      end
    end)
    |> Enum.take(@hero_pool)
  end

  defp hero_item(ref, %Title{} = title, payload, urls) do
    %HeroCard.Item{
      id: TitleRef.param(ref),
      ref: ref,
      name: title.name,
      year: title.year,
      runtime: runtime(payload["runtime"]),
      genre_label: genres(payload["genres"]),
      overview: title.overview || payload["overview"],
      backdrop_url: urls.backdrop_url,
      logo_url: urls.logo_url
    }
  end

  defp runtime(minutes) when is_integer(minutes) and minutes > 0,
    do: LibraryFormatters.format_human_duration(minutes * 60)

  defp runtime(_minutes), do: nil

  defp genres(genres) when is_list(genres) and genres != [] do
    genres |> Enum.map(& &1["name"]) |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  defp genres(_genres), do: nil

  @doc """
  The watchlist by release stage (decisions 13–15, M16): every listed
  title the library does not own. A **followed series** — one with a
  tracking item, passed by ref with its releases — is placed by its
  calendar (`ReleaseTracking.Calendar.read/3` with the record's caught-up
  point): **Out Now** while an aired episode is not had, at the latest
  such date; **Coming Up** when nothing is out and an episode is dated
  ahead; otherwise off the shelves (the Watchlist page inventories it).
  Every other title is placed by `TMDB.ReleaseStages`' reading of its
  record — **Out Now** at the home stage (a digital or disc release
  passed, a List-only series' first episode aired), newest home date
  first; **In Theaters** at the theatrical stage, newest opening first,
  the opening date as the chip; **Coming Up** unreleased, nearest first,
  the release month as the chip. A title whose stage is unknown, or whose
  record the store lacks, waits off the shelves. The marker is the rung's
  word.
  """
  @spec watchlist_shelves(
          [listed()],
          %{MediaCentaur.TMDB.Store.ref() => staged()},
          %{MediaCentaur.TMDB.Store.ref() => MediaCentaur.ReleaseTracking.Item.t()},
          %{MediaCentaur.TMDB.Store.ref() => atom()},
          Date.t()
        ) ::
          watchlist_shelves()
  def watchlist_shelves(listed, stages, tracking, acquisition_states, today) do
    placed =
      for %{intent: intent, library_owner_id: nil} <- listed,
          ref = {intent.tmdb_id, intent.media_type},
          {stage, date} <- [placement(intent, Map.get(tracking, ref), Map.get(stages, ref), today)],
          stage in [:home, :theatrical, :unreleased] do
        {stage, date, item(ref, intent.title, nil, Map.get(acquisition_states, ref), intent.rung)}
      end

    %{
      out_now: shelf(placed, :home, :desc, today, nil),
      in_theaters: shelf(placed, :theatrical, :desc, today, :day),
      coming_up: shelf(placed, :unreleased, :asc, today, :month)
    }
  end

  # A followed series answers from its calendar; everything else from its stage.
  defp placement(
         %TitleIntent{media_type: :tv_series} = intent,
         %ReleaseTracking.Item{releases: releases} = item,
         _stage,
         today
       )
       when is_list(releases) do
    case Calendar.read(item, TitleIntent.caught_up(intent), today) do
      %{out: [_ | _] = out} -> {:home, out |> Enum.map(& &1.air_date) |> Enum.max(Date)}
      %{next: %Date{} = next} -> {:unreleased, next}
      %{next: nil} -> {:off, nil}
    end
  end

  defp placement(_intent, _item, %{stage: stage, date: date}, _today), do: {stage, date}
  defp placement(_intent, _item, nil, _today), do: {:unknown, nil}

  defp shelf(placed, stage, order, today, chip) do
    placed
    |> Enum.filter(fn {placed_stage, _date, _item} -> placed_stage == stage end)
    |> Enum.sort_by(fn {_stage, date, _item} -> date || ~D[0001-01-01] end, {order, Date})
    |> Enum.map(fn {_stage, date, item} -> %{item | chip: Format.date_chip(chip, date, today)} end)
  end

  @doc """
  The Reviewed by Friends shelf: one tile per title from
  `Activities.reviewed_by_friends/1`, in its order, with the title's
  social glyphs from `Activities.activity_for/1`'s rows (the flags a
  friend flew, each at its grade, UIDR-049) and the marker; an ignored
  title is dropped, as the Feed drops it. An owned title stays, marked.
  """
  @spec friends_items(
          [%{ref: MediaCentaur.TMDB.Store.ref(), title: Title.t()}],
          %{MediaCentaur.TMDB.Store.ref() => [map()]},
          %{MediaCentaur.TMDB.Store.ref() => atom()},
          %{MediaCentaur.TMDB.Store.ref() => String.t()},
          %{MediaCentaur.TMDB.Store.ref() => atom()}
        ) :: [PosterRow.Item.t()]
  def friends_items(reviewed, activity_by_ref, rungs, owners, acquisition_states) do
    for %{ref: ref, title: title} <- reviewed, Map.get(rungs, ref) != :ignored do
      rows = Map.get(activity_by_ref, ref, [])

      item =
        item(ref, title, Map.get(owners, ref), Map.get(acquisition_states, ref), Map.get(rungs, ref))

      %{
        item
        | glyphs: %{
            flags: SocialWords.drawn_flags(rows),
            grades: Grade.for_title(rows),
            tips: SocialWords.sentences(rows)
          }
      }
    end
  end

  defp item(ref, %Title{} = title, owner_id, acquisition_state, rung) do
    facts = %{in_library?: owner_id != nil, acquisition_state: acquisition_state, rung: rung}

    %PosterRow.Item{
      id: TitleRef.param(ref),
      ref: ref,
      name: title.name,
      year: title.year,
      poster_url: TitleArtwork.urls(title, %{}, :w342).poster_url,
      marker: facts |> Logic.row_markers() |> List.first(),
      slots:
        ToolbarSlots.resolve(%{
          rung: rung,
          library_owner_id: owner_id,
          acquisition_state: acquisition_state
        })
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
  Whether a broadcast changes what the shelves show: the membership, a
  stored title, a rung, the library's holdings, a friend's activity, the
  Social flag, or TMDB's availability (the empty state's wording). The
  title detail host subscribes the page to the store, the watchlist, the
  library and Activities; the page adds the membership and availability
  topics.
  """
  @spec reloads?(term()) :: boolean()
  def reloads?({:new_releases_changed}), do: true
  def reloads?({:tmdb_title_changed, _ref}), do: true
  def reloads?({:title_intent_changed, _event}), do: true
  def reloads?({:entities_changed, _event}), do: true
  def reloads?({:activity_received, _event}), do: true
  def reloads?({:activity_sent, _event}), do: true
  def reloads?({:activity_deleted, _event}), do: true
  def reloads?({:setting_changed, "feature:social", _value}), do: true
  def reloads?({:integration_availability_changed, :tmdb, _state}), do: true
  def reloads?(_message), do: false
end
