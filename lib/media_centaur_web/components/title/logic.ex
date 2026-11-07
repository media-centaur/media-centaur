defmodule MediaCentaurWeb.Components.Title.Logic do
  @moduledoc """
  Pure decisions for the title surfaces (ADR-030) — the ones the Social
  page and Downloads share: the title detail view-model, the
  acquisition-state words the rows and the modal show, and the row
  markers. The planning-mode and scope words live here too, so the
  Download menu and the Settings select say the same thing.
  The Social page's own two tab projections live beside its LiveView:
  `FeedEntries` and `People`.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaur.Format
  alias MediaCentaur.Library.EntityView
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Acquisition.MediaResults
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.ModalState

  @type acquisition_state :: :planning | :downloading | :needs_review | nil

  @doc """
  Builds the detail for a title from the facts the host resolved by
  identity: `rung`, `acquisition_state` and `release_mode_available`
  always; `library` (the `Detail.Library` half, nil when unowned),
  `activity`, `intent_note`, `poster_url`, `backdrop_url`, `logo_url`,
  `tracking`, `acquisition?`, `lower_quality_accepted?`,
  `release_window`, `planning_mode`, `social_activity` and `preview`
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
      settled?: Map.get(facts, :settled?, false),
      number_of_seasons: Map.get(facts, :number_of_seasons),
      release_window: Map.get(facts, :release_window),
      planning_mode: Map.get(facts, :planning_mode, :manually_select_release),
      activity: Map.get(facts, :activity),
      intent_note: Map.get(facts, :intent_note),
      social_activity: Map.get(facts, :social_activity, []),
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
  dates row renders (`TrackingControls.rows/1`) and whether a finished
  series reads "caught up" (`Detail.FinishPrompt`). A series has one
  ahead until its TMDB record is settled. For a movie the release window
  read from the live TMDB payload answers once it has landed
  (`:unreleased` and `:theatrical` are ahead, `:home` is not, `:unknown`
  says nothing and defers to the snapshot); until then the snapshot's
  primary date against `today` (`MediaResults.release_status/2`).
  """
  @spec release_ahead?(TitleDetail.t(), Date.t()) :: boolean()
  def release_ahead?(%TitleDetail{title: %Title{media_type: :tv_series}, settled?: settled?}, _today),
    do: not settled?

  def release_ahead?(
        %TitleDetail{title: %Title{media_type: :movie} = title, release_window: window},
        today
      ), do: movie_release_ahead?(title, window, today)

  defp movie_release_ahead?(title, %ReleaseWindow{stage: :unknown}, today),
    do: movie_release_ahead?(title, nil, today)

  defp movie_release_ahead?(_title, %ReleaseWindow{stage: stage}, _today),
    do: stage in [:unreleased, :theatrical]

  defp movie_release_ahead?(title, nil, today),
    do: MediaResults.release_status(title, today) == :upcoming

  @doc """
  The reader's own review among a title's activity rows
  (`Activities.activity_for/1`'s, the reader's acts included), or nil.
  The Review modal opens on it as editing; the detail's pencil and note
  line speak of it.
  """
  @spec own_review([MediaCentaur.Activities.activity_row()]) :: Activity.t() | nil
  def own_review(rows) do
    case own_review_row(rows) do
      %{activity: activity} -> activity
      nil -> nil
    end
  end

  @doc "The row of the reader's own review — the activity with the reader as its author — or nil. The detail's note line draws the author from it."
  @spec own_review_row([MediaCentaur.Activities.activity_row()]) ::
          MediaCentaur.Activities.activity_row() | nil
  def own_review_row(rows) do
    Enum.find(rows, &match?(%{activity: %Activity{kind: :review}, author: %Person{own?: true}}, &1))
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

  @doc "The words for a planning mode — the Settings option and the Download menu item alike (spec 2026-09-12 §2, §11)."
  @spec planning_mode_label(PlanningMode.mode()) :: String.t()
  def planning_mode_label(:auto_select_best_release), do: "Auto-select best release"
  def planning_mode_label(:manually_select_release), do: "Manually select release"

  @doc """
  The scope choices a series' select lists, in menu order: every one,
  but *Latest season* only when the series has more than one regular
  season — with one, it would plan what *First missing season* plans.
  """
  @spec offered_scopes(TitleDetail.t()) :: [ModalState.scope_choice()]
  def offered_scopes(%TitleDetail{number_of_seasons: count}) when is_integer(count) and count > 1,
    do: ModalState.scope_choices()

  def offered_scopes(%TitleDetail{}), do: ModalState.scope_choices() -- [:latest_season]

  @doc """
  Whether the Download row offers *Grab new episodes as they air*: a
  series with a release ahead (`release_ahead?/2`), not on the watchlist
  — a listed title's tracking block already carries Auto-grab, the same
  choice — on a scope that plans here (*Choose episodes* leaves for the
  picker and plans nothing). Download with it on also puts the series
  at Grab; the scope itself never follows (ADR-066).
  """
  @spec grab_rest_offered?(TitleDetail.t(), ModalState.t(), Date.t()) :: boolean()
  def grab_rest_offered?(
        %TitleDetail{title: %Title{media_type: :tv_series}, rung: nil} = detail,
        %ModalState{download_scope: scope},
        today
      ), do: scope != :choose_episodes and release_ahead?(detail, today)

  def grab_rest_offered?(%TitleDetail{}, %ModalState{}, _today), do: false

  @doc "The scope select's words for each of its values (spec 2026-09-12 §1, §11; 2026-09-23 §1)."
  @spec download_scope_label(ModalState.scope_choice()) :: String.t()
  def download_scope_label(:first_missing_season), do: "First missing season"
  def download_scope_label(:everything), do: "All seasons"
  def download_scope_label(:latest_season), do: "Latest season"
  def download_scope_label(:choose_episodes), do: "Choose episodes"

  @doc """
  The quiet text markers a title row shows after its type and year, in
  order: the library or acquisition state (one of them — In library
  wins), then the tracking rung (Tracking at Follow, Auto-grab at Grab).
  A listed title says so: On your list at List. An owned film shows In
  library alone: it is complete, and nothing tracking says is news.

  An owned series you follow is the exception to In library winning: what
  you follow it for is episodes the library does not have yet, so it
  leads with what is happening to them — the acquisition state, then the
  rung — and In library comes last. A surface with room for one marker
  (a poster tile) shows the rung, not the library's claim.

  What people did with the title is the social glyphs', and a feed row's
  sender/when line is the host's; neither is a marker.
  """
  @spec row_markers(%{
          required(:media_type) => Title.media_type(),
          required(:in_library?) => boolean(),
          required(:acquisition_state) => acquisition_state(),
          optional(:rung) => TitleIntent.rung() | nil
        }) :: [String.t()]
  def row_markers(%{media_type: :tv_series, in_library?: true, rung: rung} = facts)
      when rung in [:follow, :grab] do
    Enum.reject([acquisition_marker(facts.acquisition_state), rung_word(rung), "In library"], &is_nil/1)
  end

  def row_markers(facts) do
    state =
      cond do
        facts.in_library? -> "In library"
        marker = acquisition_marker(facts.acquisition_state) -> marker
        true -> nil
      end

    tracking =
      case Map.get(facts, :rung) do
        :ignored -> nil
        rung -> if not facts.in_library?, do: rung_word(rung)
      end

    Enum.reject([state, tracking], &is_nil/1)
  end

  @doc """
  The word for a rung as a state — the row marker, the Watchlist page's
  group heading and its rung menu read one vocabulary: On your list at
  List, Tracking at Follow, Auto-grab at Grab, Ignored. Off says nothing
  (a row would not be there). As a marker Ignored says nothing either —
  it is a stance about the Feed, not an acquisition state — so
  `row_markers/1` drops it; the Watchlist page names its group with it.
  """
  @spec rung_word(TitleIntent.rung() | nil) :: String.t() | nil
  def rung_word(nil), do: nil
  def rung_word(:ignored), do: "Ignored"
  def rung_word(:list), do: "On your list"
  def rung_word(:follow), do: "Tracking"
  def rung_word(:grab), do: "Auto-grab"
end
