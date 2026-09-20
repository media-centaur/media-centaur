defmodule MediaCentaur.TMDB.ReleaseWindow do
  @moduledoc """
  Where a movie stands in its release sequence, read from a TMDB movie
  payload at a date.

  TMDB lists a film's releases by country and type; the US theatrical
  (type 3), digital (type 4) and physical (type 5) dates are the ones
  that say when a release can exist on an indexer — a theatrical opening
  is not one. `Mapper.us_typed_release_dates/1` extracts them; this
  module reads them as a **stage**:

  | stage | the world it proves |
  |---|---|
  | `:home` | a digital or disc release has passed — a release can exist |
  | `:unreleased` | every known date, typed or TMDB's primary one, is ahead |
  | `:theatrical` | opened in theaters, no home release yet |
  | `:unknown` | TMDB says nothing usable |

  The one judgment here is `@theatrical_run_days`: a theatrical opening
  with no home date on TMDB reads as *in theaters* only within the
  plausible length of a run. TMDB's silence on a home date for a film
  that opened years ago means nothing, and "in theaters since 1994"
  would be false. A known home date ahead lifts the bound — TMDB is
  then saying, in so many words, that the film is still between
  theaters and home.

  Not to be confused with the corpus *freshness window* or the history
  *window*, which are spans of time; this is a position in a sequence.
  Pure — the LiveView fetches the payload and assigns the built struct.
  """

  alias MediaCentaur.TMDB.Mapper

  # The longest a theatrical run plausibly lasts before a home release:
  # studio windows run 45–90 days, the long tail about half a year.
  @theatrical_run_days 180

  @enforce_keys [:stage]
  defstruct [:stage, :theatrical, :digital, :physical, :primary]

  @type stage :: :unreleased | :theatrical | :home | :unknown

  @type t :: %__MODULE__{
          stage: stage(),
          theatrical: Date.t() | nil,
          digital: Date.t() | nil,
          physical: Date.t() | nil,
          primary: Date.t() | nil
        }

  @doc """
  Reads a stored movie payload (`TMDB.Store`) at `today`. Each typed date
  is the earliest US entry of its type (TMDB lists re-releases too).
  `primary` is TMDB's top-level `release_date`; it is read only when no
  typed date exists, and then only ahead — TMDB does not say which kind
  of release it was, and it is often a festival premiere that precedes
  the typed dates, so it must not hide an opening still ahead.
  """
  @spec from_payload(map(), Date.t()) :: t()
  def from_payload(payload, %Date{} = today) when is_map(payload) do
    typed =
      payload
      |> Mapper.us_typed_release_dates()
      |> Enum.group_by(& &1.release_type, & &1.date)

    dates = %{
      theatrical: earliest(typed["theatrical"]),
      digital: earliest(typed["digital"]),
      physical: earliest(typed["physical"]),
      primary: primary_date(payload["release_date"])
    }

    struct!(__MODULE__, Map.put(dates, :stage, stage(dates, today)))
  end

  @doc """
  The home release — the earlier of the digital and disc dates, with its
  type — or nil when TMDB has neither. A same-day tie reads as digital.
  """
  @spec home_release(t()) :: {:digital | :physical, Date.t()} | nil
  def home_release(%__MODULE__{digital: digital, physical: physical}) do
    [{:digital, digital}, {:physical, physical}]
    |> Enum.reject(fn {_type, date} -> is_nil(date) end)
    |> Enum.min_by(fn {_type, date} -> date end, Date, fn -> nil end)
  end

  defp stage(dates, today) do
    home = home_date(dates)
    typed = Enum.reject([dates.theatrical, dates.digital, dates.physical], &is_nil/1)

    cond do
      typed == [] ->
        if dates.primary != nil and Date.after?(dates.primary, today), do: :unreleased, else: :unknown

      home != nil and not Date.after?(home, today) ->
        :home

      Enum.all?(typed, &Date.after?(&1, today)) ->
        :unreleased

      dates.theatrical != nil and not Date.after?(dates.theatrical, today) and
          (home != nil or Date.diff(today, dates.theatrical) <= @theatrical_run_days) ->
        :theatrical

      true ->
        :unknown
    end
  end

  defp home_date(dates) do
    case home_release(struct!(__MODULE__, Map.put(dates, :stage, :unknown))) do
      {_type, date} -> date
      nil -> nil
    end
  end

  defp earliest(nil), do: nil
  defp earliest(dates), do: Enum.min(dates, Date)

  # The primary date is a bare ISO day; anything else TMDB might send
  # (blank, or a placeholder) is no date.
  defp primary_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp primary_date(_absent), do: nil
end
