defmodule MediaCentaur.TMDB.Schedule do
  @heartbeat_days 7
  @settled_after_days 180
  @check_time ~T[12:00:00]

  @moduledoc """
  When the app is next due to ask TMDB about a stored title — a pure
  function of the stored payloads and today's date, with no process and
  no I/O. `MediaCentaur.TMDB.Store` calls it on every write and stores
  the answer as columns, so the checker can query what is due.

  Two rules, agreed with the owner on 2026-09-20 (campaign
  `tmdb-fetch-policy`, ADR-071):

    * **Settled** — a title whose release facts can no longer change. A
      movie is settled at release stage `:home`
      (`MediaCentaur.TMDB.ReleaseWindow`), or when its primary date is
      more than #{@settled_after_days} days past with no typed home
      date, or when canceled. A series is settled when ended or
      canceled with no air date ahead of today in its payload or any
      stored season. A settled title is never due.
    * **Due** — the day after the next known event (noon UTC, past the
      air date in every time zone), or #{@heartbeat_days} days after the
      last fetch, whichever comes first. The heartbeat is the pace at
      which a distant announcement is worth learning, and bounds how
      late a date that moved earlier is noticed.

  The **next known event** is the earliest release fact still ahead of
  today: a series' next air date (its `next_episode_to_air`, any stored
  season's episode, any season's own air date); a movie's typed dates
  and primary date.

  A season is **open** — checked with its series — while it is the
  series' latest numbered season or holds an episode with no air date
  or one ahead of today (`open_season?/3`).
  """

  alias MediaCentaur.TMDB.ReleaseWindow

  @type plan :: %{
          next_event_on: Date.t() | nil,
          next_check_at: DateTime.t() | nil,
          settled?: boolean()
        }

  @doc "Days between checks when no event is nearer."
  @spec heartbeat_days() :: pos_integer()
  def heartbeat_days, do: @heartbeat_days

  @doc """
  The schedule for a title from its payload, its stored season payloads,
  today, and its last fetch time.
  """
  @spec plan(:movie | :tv_series, map(), [map()], Date.t(), DateTime.t()) :: plan()
  def plan(:movie, payload, _season_payloads, %Date{} = today, %DateTime{} = fetched_at) do
    window = ReleaseWindow.from_payload(payload, today)

    future =
      [window.theatrical, window.digital, window.physical, window.primary]
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&Date.after?(&1, today))

    build(future, movie_settled?(payload, window, today, future), fetched_at)
  end

  def plan(:tv_series, payload, season_payloads, %Date{} = today, %DateTime{} = fetched_at) do
    future =
      payload
      |> tv_dates(season_payloads)
      |> Enum.map(&parse_date/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&Date.after?(&1, today))

    settled? = payload["status"] in ["Ended", "Canceled"] and future == []
    build(future, settled?, fetched_at)
  end

  @doc """
  Whether a stored season is still checked with its series: it is the
  series' latest numbered season, or it holds an episode with no air
  date or one ahead of `today`.
  """
  @spec open_season?(map(), map(), Date.t()) :: boolean()
  def open_season?(season_payload, title_payload, %Date{} = today) do
    latest =
      title_payload
      |> Map.get("seasons", [])
      |> List.wrap()
      |> Enum.map(& &1["season_number"])
      |> Enum.reject(&(&1 in [nil, 0]))
      |> Enum.max(fn -> nil end)

    season_payload["season_number"] == latest or
      Enum.any?(season_payload["episodes"] || [], fn episode ->
        case parse_date(episode["air_date"]) do
          nil -> true
          date -> Date.after?(date, today)
        end
      end)
  end

  defp build(future, settled?, fetched_at) do
    next_event_on = Enum.min(future, Date, fn -> nil end)

    %{
      next_event_on: next_event_on,
      next_check_at: if(!settled?, do: next_check_at(next_event_on, fetched_at)),
      settled?: settled?
    }
  end

  defp next_check_at(nil, fetched_at), do: heartbeat(fetched_at)

  defp next_check_at(next_event_on, fetched_at) do
    day_after = DateTime.new!(Date.add(next_event_on, 1), @check_time, "Etc/UTC")
    Enum.min([day_after, heartbeat(fetched_at)], DateTime)
  end

  defp heartbeat(fetched_at), do: DateTime.add(fetched_at, @heartbeat_days, :day)

  defp movie_settled?(payload, window, today, future) do
    cond do
      payload["status"] == "Canceled" -> true
      window.stage == :home -> true
      future != [] -> false
      is_nil(window.primary) -> false
      ReleaseWindow.home_release(window) != nil -> false
      true -> Date.diff(today, window.primary) > @settled_after_days
    end
  end

  defp tv_dates(payload, season_payloads) do
    episode_dates =
      for season <- season_payloads, episode <- season["episodes"] || [], do: episode["air_date"]

    season_dates = for season <- List.wrap(payload["seasons"]), do: season["air_date"]

    [get_in(payload, ["next_episode_to_air", "air_date"]) | episode_dates ++ season_dates]
  end

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_value), do: nil
end
