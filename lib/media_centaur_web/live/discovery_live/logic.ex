defmodule MediaCentaurWeb.DiscoveryLive.Logic do
  @moduledoc """
  Pure decisions for the Discovery page (ADR-030): the title detail
  view-model, the acquisition-state words the rows and the modal show,
  the row markers, and a watchlist row's next release date. The two tab
  projections live beside it: `RecommendationRows` and `People`.
  """

  alias MediaCentaur.ReleaseTracking.{Item, Release}
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Acquisition.MediaResults
  alias MediaCentaurWeb.Components.Discovery.TitleDetail
  alias MediaCentaurWeb.Components.ReleaseTracking.Present

  @type acquisition_state :: :planning | :downloading | :needs_review | nil

  @doc """
  Builds the detail for a title from the facts the host resolved:
  `library_owner_id`, `on_watchlist?`, `acquisition_state`,
  `release_mode_available`, `today`, plus optional `poster_url`,
  `backdrop_url`, `logo_url`, `tracking`, `acquisition?`,
  `default_grab_mode`, `kind`, `episode`, `sender`, `note`, `acted_at`,
  `own?`, `activity_id`, `recommendations`, `preview`. The primary
  action is In library, else the acquisition state, else Download when
  the title is out and an indexer is ready — else nothing: arming is
  the tracking-mode control's job, not a verb in the strip.
  """
  @spec title_detail(Title.t(), map()) :: TitleDetail.t()
  def title_detail(%Title{} = title, facts) do
    %TitleDetail{
      ref: Title.ref(title),
      title: title,
      poster_url: Map.get(facts, :poster_url),
      backdrop_url: Map.get(facts, :backdrop_url),
      logo_url: Map.get(facts, :logo_url),
      primary: primary(title, facts),
      scoped?: title.media_type == :tv_series,
      on_watchlist?: Map.fetch!(facts, :on_watchlist?),
      tracking: Map.get(facts, :tracking),
      acquisition?: Map.get(facts, :acquisition?, false),
      default_grab_mode: Map.get(facts, :default_grab_mode, "off"),
      kind: Map.get(facts, :kind),
      episode: Map.get(facts, :episode),
      sender: Map.get(facts, :sender),
      note: Map.get(facts, :note),
      acted_at: Map.get(facts, :acted_at),
      own?: Map.get(facts, :own?),
      activity_id: Map.get(facts, :activity_id),
      recommendations: Map.get(facts, :recommendations, []),
      preview: Map.get(facts, :preview)
    }
  end

  defp primary(title, facts) do
    cond do
      owner = Map.fetch!(facts, :library_owner_id) -> {:in_library, owner}
      state = Map.fetch!(facts, :acquisition_state) -> {:state, state}
      downloadable?(title, facts) -> :download
      true -> nil
    end
  end

  defp downloadable?(title, facts) do
    Map.fetch!(facts, :release_mode_available) and
      MediaResults.release_status(title, Map.fetch!(facts, :today)) == :released
  end

  @doc "A watchlist note as the row's `notes`: one unattributed entry, or none."
  @spec note_list(String.t() | nil) :: [%{name: nil, text: String.t()}]
  def note_list(nil), do: []
  def note_list(note), do: [%{name: nil, text: note}]

  @doc "The words a row or the modal shows for an acquisition state."
  @spec acquisition_marker(acquisition_state()) :: String.t() | nil
  def acquisition_marker(:planning), do: "Planning"
  def acquisition_marker(:downloading), do: "Downloading"
  def acquisition_marker(:needs_review), do: "Needs review"
  def acquisition_marker(nil), do: nil

  @doc """
  The quiet text markers a Discovery row shows after its type and year,
  in order: the library or acquisition state (one of them — In library
  wins), then On watchlist (never for an owned title — membership is
  noise once the file is there), then — a watchlist row's — the tracking
  mode when the title is armed (`tracking_mode` + `default_grab_mode`,
  Default resolved to what it does; never for an owned title, whose
  tracking is the library detail's) and the next release date when the
  facts carry one (`next_air_date` + `today`). Who recommended the title
  is the pennant's, and the feed row's sender/when line is the host's;
  neither is a marker.
  """
  @spec row_markers(%{
          required(:library_owner_id) => Ecto.UUID.t() | nil,
          required(:acquisition_state) => acquisition_state(),
          required(:on_watchlist?) => boolean(),
          optional(:tracking_mode) => Item.tracking_mode() | nil,
          optional(:default_grab_mode) => String.t(),
          optional(:next_air_date) => Date.t() | nil,
          optional(:today) => Date.t()
        }) :: [String.t()]
  def row_markers(facts) do
    state =
      cond do
        facts.library_owner_id -> "In library"
        marker = acquisition_marker(facts.acquisition_state) -> marker
        true -> nil
      end

    watchlist = if facts.on_watchlist? and is_nil(facts.library_owner_id), do: "On watchlist"

    tracking =
      if is_nil(facts.library_owner_id),
        do: tracking_marker(Map.get(facts, :tracking_mode), Map.get(facts, :default_grab_mode))

    next =
      case Map.get(facts, :next_air_date) do
        %Date{} = date -> "Next: " <> Present.relative_day(date, Map.fetch!(facts, :today))
        nil -> nil
      end

    Enum.reject([state, watchlist, tracking, next], &is_nil/1)
  end

  # Off and never-tracked have nothing to say; Default says what it
  # resolves to, so the row never asks the reader to know the setting.
  defp tracking_marker(mode, _default) when mode in [nil, :none], do: nil
  defp tracking_marker(:watch, _default), do: "Tracking: Watch"
  defp tracking_marker(:ask, _default), do: "Tracking: Ask"
  defp tracking_marker(:grab, _default), do: "Tracking: Grab"

  defp tracking_marker(:global, default) do
    case Item.grab_mode(:global, default) do
      "all_releases" -> "Tracking: Grab"
      "ask" -> "Tracking: Ask"
      _off -> "Tracking: Watch"
    end
  end

  @doc """
  A tracked title's next release date — the earliest air date today or
  later among releases not yet in the library — or nil when nothing is
  scheduled.
  """
  @spec next_air_date([Release.t()], Date.t()) :: Date.t() | nil
  def next_air_date(releases, today) do
    releases
    |> Enum.reject(&(&1.in_library or is_nil(&1.air_date)))
    |> Enum.map(& &1.air_date)
    |> Enum.filter(&(Date.compare(&1, today) != :lt))
    |> Enum.min(Date, fn -> nil end)
  end
end
