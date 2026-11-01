defmodule MediaCentaur.TMDB.ReleaseStages do
  @moduledoc """
  The release stage of each title in a set, read from the store's records
  at a date — a projection over stored payloads (ADR-071), no request.
  Discovery's watchlist shelves split the listed titles by it: Out Now,
  In Theaters, Coming Up.

  A movie reads through `ReleaseWindow`: **home** when a digital or disc
  release has passed, **theatrical** when it opened and no home release
  has, **unreleased** when every known date is ahead, **unknown** when
  TMDB says nothing usable. A series has no theatrical sequence; it reads
  from `first_air_date`: *home* here means available to watch at home,
  which for a series is its first episode aired; ahead is unreleased;
  none is unknown.

  The date beside the stage is the one the stage rests on: the home
  release date, the theatrical opening, or the nearest date ahead.
  """

  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaur.TMDB.Store

  @type stage :: ReleaseWindow.stage()
  @type t :: %{stage: stage(), date: Date.t() | nil}

  @doc "The stage and its date for every ref the store holds; a ref it lacks is absent."
  @spec for_refs([Store.ref()], Date.t()) :: %{Store.ref() => t()}
  def for_refs(refs, %Date{} = today) when is_list(refs) do
    refs
    |> Store.get_many()
    |> Map.new(fn {{_id, media_type} = ref, record} ->
      {ref, read(media_type, record.payload, today)}
    end)
  end

  @doc "One payload's stage and date, for a caller holding the record already."
  @spec read(:movie | :tv_series, map(), Date.t()) :: t()
  def read(:movie, payload, today) do
    window = ReleaseWindow.from_payload(payload, today)
    %{stage: window.stage, date: date_for(window, today)}
  end

  def read(:tv_series, payload, today) do
    case parse(payload["first_air_date"]) do
      nil ->
        %{stage: :unknown, date: nil}

      date ->
        if Date.after?(date, today),
          do: %{stage: :unreleased, date: date},
          else: %{stage: :home, date: date}
    end
  end

  defp date_for(%ReleaseWindow{stage: :home} = window, _today) do
    {_type, date} = ReleaseWindow.home_release(window)
    date
  end

  defp date_for(%ReleaseWindow{stage: :theatrical, theatrical: date}, _today), do: date

  defp date_for(%ReleaseWindow{stage: :unreleased} = window, today) do
    [window.theatrical, window.digital, window.physical, window.primary]
    |> Enum.filter(&(&1 != nil and Date.after?(&1, today)))
    |> Enum.min(Date, fn -> nil end)
  end

  defp date_for(%ReleaseWindow{stage: :unknown}, _today), do: nil

  defp parse(nil), do: nil
  defp parse(""), do: nil

  defp parse(string) when is_binary(string) do
    case Date.from_iso8601(string) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end
end
