defmodule MediaCentaurWeb.IncomingLive.WatchlistRows do
  @moduledoc """
  The Watchlist tab's rows (UIDR-050): every title intent at List or
  above, once, joined with what the page already holds — the forecast
  (`UpcomingFeed`) for a followed title's next release, the social
  activity for the glyphs, the acquisition state for the marker, the
  poster — and sorted the way the tab reads: titles with a dated next
  release nearest first, then followed titles TMDB has not dated, then
  listed-only titles newest first (the watchlist read's own order).

  Pure: every fact is injected (ADR-030). The status vocabulary is the
  `StatusPill`'s; this is the one mapping from the feed's statuses onto
  it — an armed release that already came out is one the app is
  searching for, so it reads Searching, never "Will grab".
  """

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Components.Title.Row.NextRelease

  @type row :: %{
          ref: MediaCentaur.Discovery.ref(),
          title: Title.t(),
          rung: TitleIntent.rung(),
          in_library?: boolean(),
          acquisition_state: Logic.acquisition_state(),
          markers: [String.t()],
          notes: [map()],
          social_activity: list(),
          poster_url: String.t() | nil,
          next_release: NextRelease.t() | nil
        }

  @doc """
  Inputs: `:watchlist` (`Discovery.list_watchlist/0` rows), `:feed`
  (`UpcomingFeed.t()`), `:social_activity` (`Activities.activity_for/1`),
  `:acquisition_states` (`TitleStates.for_refs/1`), `:posters`
  (`ref => url`), `:today`.
  """
  @spec build(map()) :: [row()]
  def build(inputs) do
    next_by_ref =
      Map.new(UpcomingFeed.next_per_title(inputs.feed), &{{&1.tmdb_id, &1.media_type}, &1})

    inputs.watchlist
    |> Enum.map(&row(&1, next_by_ref, inputs))
    |> Enum.sort_by(&sort_key/1)
  end

  defp row(%{intent: intent, library_owner_id: owner_id}, next_by_ref, inputs) do
    ref = {intent.tmdb_id, intent.media_type}
    in_library? = not is_nil(owner_id)
    acquisition_state = Map.get(inputs.acquisition_states, ref)

    %{
      ref: ref,
      title: intent.title,
      rung: intent.rung,
      in_library?: in_library?,
      acquisition_state: acquisition_state,
      markers:
        Logic.row_markers(
          %{in_library?: in_library?, acquisition_state: acquisition_state, rung: intent.rung},
          true
        ),
      notes: Logic.note_list(intent.note),
      social_activity: Map.get(inputs.social_activity, ref, []),
      poster_url: Map.get(inputs.posters, ref),
      next_release: next_release(Map.get(next_by_ref, ref), inputs.today)
    }
  end

  # Stable sort: within the undated and the listed-only groups the
  # watchlist read's order (newest first) stands. Every key is a pair —
  # term order ranks a shorter tuple before a longer one, so a bare
  # `{1}` would sort ahead of every `{0, date}`.
  defp sort_key(%{next_release: %NextRelease{air_date: date}}), do: {0, Date.to_erl(date)}
  defp sort_key(%{rung: rung}), do: {if(TitleIntent.follows_releases?(rung), do: 1, else: 2), nil}

  defp next_release(nil, _today), do: nil

  defp next_release(%Event{} = event, today) do
    %NextRelease{
      air_date: event.air_date,
      date_label: UpcomingFeed.date_label(event, today),
      subtitle: subtitle(event),
      status: pill_status(event, today),
      pursuit_id: event.pursuit_id
    }
  end

  defp pill_status(%Event{status: :armed, air_date: date}, today),
    do: if(Date.before?(date, today), do: :searching, else: :armed)

  defp pill_status(%Event{status: :under_pursuit}, _today), do: :in_pursuit
  # A fallback date never leads a title's row — the earlier armed date
  # sorts first — mapped defensively.
  defp pill_status(%Event{status: :armed_fallback}, _today), do: :tracked
  defp pill_status(%Event{status: :theatrical_info}, _today), do: :in_theaters
  defp pill_status(%Event{status: :in_library}, _today), do: :landed
  defp pill_status(%Event{status: :upcoming}, _today), do: :tracked

  # A season drop names the season and the count; an episode its code
  # and, when the release has one, its title; a movie's edition title
  # only when it differs from the movie's own name.
  defp subtitle(%Event{kind: :season_drop, season_number: season, episode_count: count}),
    do: "S#{season} · all #{count} episodes at once"

  defp subtitle(%Event{kind: :episode} = event) do
    code = "S#{pad(event.season_number)}E#{pad(event.episode_number)}"
    if event.title, do: "#{code} · “#{event.title}”", else: code
  end

  defp subtitle(%Event{kind: :movie, title: title, item_name: title}), do: nil
  defp subtitle(%Event{kind: :movie} = event), do: event.title

  defp pad(number), do: number |> to_string() |> String.pad_leading(2, "0")
end
