defmodule MediaCentaurWeb.Components.Title.Logic do
  @moduledoc """
  Pure decisions for the title surfaces (ADR-030) — the ones Discovery
  and Incoming share: the title detail view-model, the acquisition-state
  words the rows and the modal show, the row markers, and a watchlist
  row's next release date. The planning-mode and scope words live here
  too, so the Download menu and the Settings select say the same thing.
  Discovery's own two tab projections live beside its LiveView:
  `FeedEntries` and `People`.
  """

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Format
  alias MediaCentaur.Library.EntityView
  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Acquisition.MediaResults
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.ModalState
  alias MediaCentaurWeb.Components.ReleaseTracking.Present

  @type acquisition_state :: :planning | :downloading | :needs_review | nil

  @doc """
  Builds the detail for a title from the facts the host resolved by
  identity: `rung`, `acquisition_state` and `release_mode_available`
  always; `library` (the `Detail.Library` half, nil when unowned),
  `activity`, `intent_note`, `poster_url`, `backdrop_url`, `logo_url`,
  `tracking`, `acquisition?`, `lower_quality_accepted?`, `complete?`,
  `release_window`, `planning_mode`, `friend_activity` and `preview`
  when the host has them. Nothing here decides: the action row and the
  tracking card derive their rules from these facts where they mount
  (`Detail.Logic`). The residue — an owned entity with no TMDB identity
  — builds from a nil title and its library half.
  """
  @spec title_detail(Title.t() | nil, map()) :: TitleDetail.t()
  def title_detail(title, facts) when is_nil(title) or is_struct(title, Title) do
    %TitleDetail{
      ref: title && Title.ref(title),
      title: title,
      poster_url: Map.get(facts, :poster_url),
      backdrop_url: Map.get(facts, :backdrop_url),
      logo_url: Map.get(facts, :logo_url),
      library: Map.get(facts, :library),
      acquisition_state: Map.fetch!(facts, :acquisition_state),
      release_mode_available: Map.fetch!(facts, :release_mode_available),
      rung: Map.fetch!(facts, :rung),
      tracking: Map.get(facts, :tracking),
      acquisition?: Map.get(facts, :acquisition?, false),
      lower_quality_accepted?: Map.get(facts, :lower_quality_accepted?, false),
      complete?: Map.get(facts, :complete?, false),
      release_window: Map.get(facts, :release_window),
      planning_mode: Map.get(facts, :planning_mode, :manually_select_release),
      activity: Map.get(facts, :activity),
      intent_note: Map.get(facts, :intent_note),
      friend_activity: Map.get(facts, :friend_activity, []),
      preview: Map.get(facts, :preview)
    }
  end

  @doc """
  The owner's entity as the title's snapshot — the source between the
  intent's embedded title and the page's in-memory copy in the host's
  resolution order, so a title the library owns never needs a TMDB
  fetch to open. Name, year, release date and overview come from the
  entity; a library image is a local file, not a TMDB path, so the art
  paths stay empty and the artwork comes from the library half. Nil
  for an entity with no title identity (`EntityView.title_ref/1`).
  """
  @spec snapshot_from_entity(map()) :: Title.t() | nil
  def snapshot_from_entity(entity) do
    case EntityView.title_ref(entity) do
      {tmdb_id, media_type} ->
        date = Map.get(entity, :date_published)

        Title.new!(%{
          tmdb_id: tmdb_id,
          media_type: media_type,
          name: entity.name,
          year: Format.year(date),
          release_date: date,
          overview: Map.get(entity, :description)
        })

      nil ->
        nil
    end
  end

  @doc """
  Whether a release is still ahead — what decides if the Track release
  dates row renders (`TrackingControls.rows/1`). A series always has one
  ahead as far as the snapshot knows. For a movie the release window
  read from the live TMDB payload answers once it has landed
  (`:unreleased` and `:theatrical` are ahead, `:home` is not, `:unknown`
  says nothing and defers to the snapshot); until then the snapshot's
  primary date against `today` (`MediaResults.release_status/2`).
  """
  @spec release_ahead?(Title.t(), ReleaseWindow.t() | nil, Date.t()) :: boolean()
  def release_ahead?(%Title{media_type: :tv_series}, _window, _today), do: true

  def release_ahead?(%Title{media_type: :movie} = title, %ReleaseWindow{stage: :unknown}, today),
    do: release_ahead?(title, nil, today)

  def release_ahead?(%Title{media_type: :movie}, %ReleaseWindow{stage: stage}, _today),
    do: stage in [:unreleased, :theatrical]

  def release_ahead?(%Title{media_type: :movie} = title, nil, today),
    do: MediaResults.release_status(title, today) == :upcoming

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

  @doc "The words for a planning mode — the Settings option and the Download menu item alike (spec 2026-09-12 §2, §11)."
  @spec planning_mode_label(PlanningMode.mode()) :: String.t()
  def planning_mode_label(:auto_select_best_release), do: "Auto-select best release"
  def planning_mode_label(:manually_select_release), do: "Manually select release"

  @doc "The scope select's words for each of its values (spec 2026-09-12 §1, §11; 2026-09-23 §1)."
  @spec download_scope_label(ModalState.scope_choice()) :: String.t()
  def download_scope_label(:first_season), do: "Season 1"
  def download_scope_label(:everything), do: "All seasons"
  def download_scope_label(:choose_episodes), do: "Choose episodes"

  @doc """
  The quiet text markers a title row shows after its type and year, in
  order: the library or acquisition state (one of them — In library
  wins), then the tracking rung (Tracking at Follow, Auto-grab at Grab;
  never for an owned title, whose tracking is the library detail's) and
  the next release date when the facts carry one (`next_air_date` +
  `today`).

  `list_implied?` is a fact about the *container*, not the title: pass
  true where every row is on the list — Discovery's watchlist tab — and
  the List rung's own marker is dropped as redundant. Everywhere else a
  listed title says so, which is the only place a search result can.

  Who reviewed the title is the pennant's, and a feed row's
  sender/when line is the host's; neither is a marker.
  """
  @spec row_markers(
          %{
            required(:in_library?) => boolean(),
            required(:acquisition_state) => acquisition_state(),
            optional(:rung) => TitleIntent.rung() | nil,
            optional(:next_air_date) => Date.t() | nil,
            optional(:today) => Date.t()
          },
          boolean()
        ) :: [String.t()]
  def row_markers(facts, list_implied? \\ false) do
    state =
      cond do
        facts.in_library? -> "In library"
        marker = acquisition_marker(facts.acquisition_state) -> marker
        true -> nil
      end

    tracking =
      if not facts.in_library? do
        rung_marker(Map.get(facts, :rung), list_implied?)
      end

    next =
      case Map.get(facts, :next_air_date) do
        %Date{} = date -> "Next: " <> Present.relative_day(date, Map.fetch!(facts, :today))
        nil -> nil
      end

    Enum.reject([state, tracking, next], &is_nil/1)
  end

  # Off says nothing — the row would not be here. Ignored says so: the
  # Feed hides it, but a search result must still say the reader
  # dismissed it. List says it is on the list, except where the
  # container already says so.
  defp rung_marker(nil, _list_implied?), do: nil
  defp rung_marker(:ignored, _list_implied?), do: "Ignored"
  defp rung_marker(:list, true), do: nil
  defp rung_marker(:list, false), do: "On your list"
  defp rung_marker(:follow, _list_implied?), do: "Tracking"
  defp rung_marker(:grab, _list_implied?), do: "Auto-grab"

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
