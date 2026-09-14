defmodule MediaCentaurWeb.Components.ReleaseTracking.ReleaseDates do
  @moduledoc """
  What the app knows about a title's upcoming dates, as a plain readout
  (spec 2026-09-14, iteration 2): no timeline, no featured slot — the
  dates, and a word beside the one the app is acting on. Mounted beside
  the tracking switches on both title surfaces (UIDR-035).

  A movie has three rows: theaters, digital, disc. The dates come from
  the live TMDB release window once the preview has landed — so a movie
  that is not even listed already shows them — and otherwise from the
  tracked title's calendar; a date TMDB has not posted reads "Not
  announced". A series lists its next few dated episodes from the
  calendar, soonest first, and says so when TMDB has posted none.

  The word beside a row is the forecast status that matters here: "Will
  download" when auto-grab will fire, "Downloading" (a link to the
  pursuit on Incoming) while it is, "In your library" once it landed.
  Everything else is silent — the switches beside the readout already
  say what the app will do. `movie_rows/2` and `series_rows/1` are the
  pure rules; the host decides whether there is anything to read out at
  all (a calendar, or a window).
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaurWeb.Components.ReleaseTracking.Present

  @movie_kinds [
    {"theatrical", :theatrical, "Theaters"},
    {"digital", :digital, "Digital"},
    {"physical", :physical, "Disc"}
  ]
  @series_rows 5

  @type row :: %{
          id: String.t(),
          label: String.t(),
          date: Date.t() | nil,
          status: atom() | nil,
          pursuit_id: Ecto.UUID.t() | nil
        }

  attr :id, :string, required: true
  attr :media_type, :atom, values: [:movie, :tv_series], required: true

  attr :release_window, ReleaseWindow,
    default: nil,
    doc: "a movie's live TMDB release window, nil until the preview lands and for a series"

  attr :timeline, :list,
    default: [],
    doc:
      "the tracked title's forecast events, nearness-first (`TrackingDetail.timeline`); [] when untracked"

  attr :today, Date, required: true
  attr :class, :string, default: nil

  def release_dates(assigns) do
    rows =
      case assigns.media_type do
        :movie -> movie_rows(assigns.release_window, assigns.timeline)
        :tv_series -> series_rows(assigns.timeline)
      end

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div id={@id} class={["space-y-1.5", @class]} data-component="release-dates">
      <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
        {heading(@media_type)}
      </h3>
      <p :if={@rows == []} id={"#{@id}-none"} class="text-sm text-base-content/55">
        No air dates announced.
      </p>
      <ul :if={@rows != []} class="space-y-1">
        <li
          :for={row <- @rows}
          id={"#{@id}-#{row.id}"}
          class="flex items-baseline justify-between gap-3 text-sm"
          data-row-status={row.status}
        >
          <span class="min-w-0 truncate text-base-content/80">{row.label}</span>
          <span class="flex shrink-0 items-baseline gap-2">
            <span class={[
              "tabular-nums",
              if(row.date, do: "text-base-content/90", else: "text-base-content/55")
            ]}>
              {date_text(row.date)}
            </span>
            <.status_word row={row} />
          </span>
        </li>
      </ul>
    </div>
    """
  end

  attr :row, :map, required: true, doc: "one `row()` from `movie_rows/2` or `series_rows/1`"

  defp status_word(%{row: %{status: :under_pursuit, pursuit_id: id}} = assigns) when is_binary(id) do
    ~H"""
    <.link
      navigate={"/incoming?selected=#{@row.pursuit_id}"}
      class="inline-flex items-center gap-1 text-xs text-info hover:underline"
    >
      Downloading <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5 opacity-70" />
    </.link>
    """
  end

  defp status_word(%{row: %{status: :armed}} = assigns) do
    ~H"""
    <span class="text-xs text-success">Will download</span>
    """
  end

  defp status_word(%{row: %{status: :in_library}} = assigns) do
    ~H"""
    <span class="text-xs text-success">In your library</span>
    """
  end

  defp status_word(assigns), do: ~H""

  @doc "The readout's heading: what kind of dates a title of this type has."
  @spec heading(:movie | :tv_series) :: String.t()
  def heading(:movie), do: "Release dates"
  def heading(:tv_series), do: "Upcoming episodes"

  @doc """
  A movie's three rows, in release order. Each date is the window's when
  it has one, else the calendar's for that release type; the status and
  pursuit come from the calendar's event for the type.
  """
  @spec movie_rows(ReleaseWindow.t() | nil, [Event.t()]) :: [row()]
  def movie_rows(window, timeline) do
    for {type, key, label} <- @movie_kinds do
      event = Enum.find(timeline, &(&1.kind == :movie and &1.release_type == type))
      date = (window && Map.get(window, key)) || (event && event.air_date)

      %{
        id: type,
        label: label,
        date: date,
        status: event && event.status,
        pursuit_id: event && event.pursuit_id
      }
    end
  end

  @doc """
  A series' next dated episodes or season drops from the calendar,
  nearness-first as the timeline already is, landed ones left out, at
  most five.
  """
  @spec series_rows([Event.t()]) :: [row()]
  def series_rows(timeline) do
    timeline
    |> Enum.filter(&(&1.kind in [:episode, :season_drop] and &1.status != :in_library))
    |> Enum.take(@series_rows)
    |> Enum.map(
      &%{
        id: &1.id,
        label: Present.what_drops(&1),
        date: &1.air_date,
        status: &1.status,
        pursuit_id: &1.pursuit_id
      }
    )
  end

  @doc "The date as TMDB posted it, or that it has not."
  @spec date_text(Date.t() | nil) :: String.t()
  def date_text(nil), do: "Not announced"
  def date_text(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")
end
