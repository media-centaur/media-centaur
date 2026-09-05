defmodule MediaCentaurWeb.DiscoveryLive.Logic do
  @moduledoc """
  Pure decisions for the Discovery page (ADR-030): the title detail
  view-model, the acquisition-state words the rows and the modal show,
  the row markers, and the `?title=` URL param's shape.
  """

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Acquisition.MediaResults
  alias MediaCentaurWeb.Components.Discovery.TitleDetail

  @type acquisition_state :: :planning | :downloading | :needs_review | nil

  @doc """
  Builds the detail for a title from the facts the host resolved:
  `library_owner_id`, `on_watchlist?`, `acquisition_state`,
  `release_mode_available`, `today`, plus optional `poster_url`,
  `backdrop_url`, `sender`, `note`, `recommended_at`, `own?`,
  `recommendation_id`, `preview`. The primary action is the watchlist row's
  three-state rule with the acquisition state folded in between In
  library and Download.
  """
  @spec title_detail(Title.t(), map()) :: TitleDetail.t()
  def title_detail(%Title{} = title, facts) do
    %TitleDetail{
      ref: {title.tmdb_id, title.media_type},
      title: title,
      poster_url: Map.get(facts, :poster_url),
      backdrop_url: Map.get(facts, :backdrop_url),
      primary: primary(title, facts),
      scoped?: title.media_type == :tv_series,
      on_watchlist?: Map.fetch!(facts, :on_watchlist?),
      sender: Map.get(facts, :sender),
      note: Map.get(facts, :note),
      recommended_at: Map.get(facts, :recommended_at),
      own?: Map.get(facts, :own?),
      recommendation_id: Map.get(facts, :recommendation_id),
      preview: Map.get(facts, :preview)
    }
  end

  defp primary(title, facts) do
    cond do
      owner = Map.fetch!(facts, :library_owner_id) -> {:in_library, owner}
      state = Map.fetch!(facts, :acquisition_state) -> {:state, state}
      downloadable?(title, facts) -> :download
      true -> :track
    end
  end

  defp downloadable?(title, facts) do
    Map.fetch!(facts, :release_mode_available) and
      MediaResults.release_status(title, Map.fetch!(facts, :today)) == :released
  end

  @doc "The words a row or the modal shows for an acquisition state."
  @spec acquisition_marker(acquisition_state()) :: String.t() | nil
  def acquisition_marker(:planning), do: "Planning"
  def acquisition_marker(:downloading), do: "Downloading"
  def acquisition_marker(:needs_review), do: "Needs review"
  def acquisition_marker(nil), do: nil

  @doc """
  The quiet text markers a Discovery row shows after its type and year,
  in order: the library or acquisition state (one of them — In library
  wins), then provenance (`from <nickname>`), then On watchlist (never
  for an owned title — membership is noise once the file is there). The
  feed row's sender/when line is the host's, not a marker.
  """
  @spec row_markers(%{
          library_owner_id: Ecto.UUID.t() | nil,
          acquisition_state: acquisition_state(),
          from_nickname: String.t() | nil,
          on_watchlist?: boolean()
        }) :: [String.t()]
  def row_markers(facts) do
    state =
      cond do
        facts.library_owner_id -> "In library"
        marker = acquisition_marker(facts.acquisition_state) -> marker
        true -> nil
      end

    provenance = facts.from_nickname && "from #{facts.from_nickname}"
    watchlist = if facts.on_watchlist? and is_nil(facts.library_owner_id), do: "On watchlist"

    Enum.reject([state, provenance, watchlist], &is_nil/1)
  end

  @doc "`?title=<media_type>-<tmdb_id>` → ref."
  @spec parse_title_ref(String.t()) :: {:ok, {integer(), Title.media_type()}} | :error
  def parse_title_ref("movie-" <> id), do: parse_id(id, :movie)
  def parse_title_ref("tv_series-" <> id), do: parse_id(id, :tv_series)
  def parse_title_ref(_other), do: :error

  defp parse_id(id, media_type) do
    case Integer.parse(id) do
      {tmdb_id, ""} -> {:ok, {tmdb_id, media_type}}
      _other -> :error
    end
  end

  @doc "ref → the `?title=` param value."
  @spec title_ref_param({integer(), Title.media_type()}) :: String.t()
  def title_ref_param({tmdb_id, media_type}), do: "#{media_type}-#{tmdb_id}"
end
