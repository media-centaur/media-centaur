defmodule MediaCentaurWeb.Components.Detail.Logic do
  @moduledoc """
  Pure helpers for the entity detail panel — facet-strip composition and
  the small string transforms used in the metadata row.

  Per ADR-030, all non-trivial branching that would otherwise live in the
  detail panel templates is hoisted here so it can be unit-tested with
  `async: true` and `build_*` factory helpers.
  """

  import MediaCentaurWeb.LibraryFormatters, only: [format_human_duration: 1]

  alias MediaCentaurWeb.Components.Detail.Facet
  alias MediaCentaurWeb.ViewModel.MovieRow
  alias MediaCentaurWeb.Components.Acquisition.MediaResults
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.Detail.Library
  alias MediaCentaurWeb.Components.Title.TrackingControls

  @doc """
  Playback props for a selected collection member (UIDR-023) — the
  member's own state decides the label, never the collection's summary.

  Returns `%{label, target_id, percent, remaining_text}`. `label` and
  `target_id` drive the Play button; `percent` feeds the hero hairline
  (UIDR-024 — the subject's own fraction, full for a watched member) and
  `remaining_text` is the metadata line's "‹duration› left" item:

    * `:unwatched` → `"Play"`, percent 0, no remaining item
    * `:current`   → `"Resume"` with percent + "‹duration› left"
    * `:watched`   → `"Watch again"`, percent 100, no remaining item

  A zero-duration progress row (position recorded before the duration
  probe) yields percent 0 rather than dividing by it.
  """
  @spec member_playback(MovieRow.Library.t()) :: %{
          label: String.t(),
          target_id: Ecto.UUID.t(),
          percent: non_neg_integer(),
          remaining_text: String.t() | nil
        }
  def member_playback(%MovieRow.Library{movie: movie, state: :watched}),
    do: %{label: "Watch again", target_id: movie.id, percent: 100, remaining_text: nil}

  def member_playback(%MovieRow.Library{movie: movie, state: :unwatched}),
    do: %{label: "Play", target_id: movie.id, percent: 0, remaining_text: nil}

  def member_playback(%MovieRow.Library{movie: movie, state: :current, progress: progress}) do
    %{
      label: "Resume",
      target_id: movie.id,
      percent: member_percent(progress),
      remaining_text: member_remaining_text(progress)
    }
  end

  defp member_percent(%{position_seconds: position, duration_seconds: duration})
       when is_number(duration) and duration > 0 do
    min(round((position || 0.0) / duration * 100), 100)
  end

  defp member_percent(_progress), do: 0

  defp member_remaining_text(%{position_seconds: position, duration_seconds: duration})
       when is_number(duration) and duration > 0 and is_number(position) and position > 0 do
    "#{format_human_duration(trunc(duration - position))} left"
  end

  defp member_remaining_text(_progress), do: nil

  @doc """
  Returns the list of facets for an entity, ready for `Detail.FacetStrip`.

  Country and Status are intentionally absent — they already appear in the
  metadata row above the strip and would be duplicates here.

  Variants:

    * `facets_for(:movie, movie)` — Director, Rating, Original language, Studio, Genres
    * `facets_for(:tv_series, tv)` — Network, Rating, Original language, Genres

  Rating sits right after the primary identity field so the stacked
  2-column layout pairs them on the same row — keeps the eye flowing
  left-to-right across the most asked-for metadata before falling to
  secondary fields.

  Empty/nil fields drop their facet so the calling template can render the
  result unconditionally.
  """
  @spec facets_for(:movie, map()) :: [Facet.t()]
  def facets_for(:movie, movie) do
    Enum.reject(
      [
        Facet.text("Director", movie.director),
        Facet.rating("Rating", movie.aggregate_rating_value, Map.get(movie, :vote_count)),
        Facet.text("Original language", movie.original_language),
        Facet.text("Studio", movie.studio),
        Facet.chips("Genres", Map.get(movie, :genres))
      ],
      &blank_facet?/1
    )
  end

  @spec facets_for(:tv_series, map()) :: [Facet.t()]
  def facets_for(:tv_series, tv) do
    Enum.reject(
      [
        Facet.text("Network", tv.network),
        Facet.rating("Rating", tv.aggregate_rating_value, Map.get(tv, :vote_count)),
        Facet.text("Original language", tv.original_language),
        Facet.chips("Genres", Map.get(tv, :genres))
      ],
      &blank_facet?/1
    )
  end

  # ---------------------------------------------------------------------------
  # Play button label/target — explicit case functions
  # ---------------------------------------------------------------------------
  #
  # The play button has five mutually exclusive cases. Each case is its own
  # named public function returning `{label, target_id}`. `playback_props/3`
  # is a `cond` dispatcher that picks the right case using explicit
  # predicates — no inferring "completed" from "resume hint is nil".
  #
  # Cases:
  #   1. `watch_again_label/1`        — fully completed
  #   2. `resume_label_from_hint/2`   — in-progress, with a resume hint
  #   3. `advance_label_from_hint/2`  — next-up after a completion, with a hint
  #   4. `resume_label_from_progress/2` — in-progress, no hint (fallback)
  #   5. `play_label/1`               — never watched
  #
  # Why both hint and progress paths for "resume": the hint carries the
  # specific child id (episode/movie targetId), so we prefer it. But the
  # hint may be missing — e.g. a LiveView that doesn't compute resume
  # targets — and progress alone is enough to know we're mid-watch and
  # produce a generic "Resume" label. Without this fallback the user sees
  # "Watch again" on a partially-watched movie.

  @doc """
  Returns `{label, target_id}` for the play button on a given entity.

  Dispatches to one of the five `*_label/1`/`*_label/2` case functions
  using explicit predicates. The play button styling is fixed in
  `Detail.PlayCard` (always the primary variant) so this function only
  decides the label text and the click target.
  """
  @spec playback_props(map(), map() | nil, map() | nil) ::
          {String.t(), String.t()}
  def playback_props(entity, resume_target, progress) do
    cond do
      completed?(progress) -> watch_again_label(entity)
      resume_hint?(resume_target) -> resume_label_from_hint(entity, resume_target)
      advance_hint?(resume_target) -> advance_label_from_hint(entity, resume_target)
      in_progress?(progress) -> resume_label_from_progress(entity, progress)
      true -> play_label(entity)
    end
  end

  @doc "True when every playable item under the entity has been completed."
  @spec completed?(map() | nil) :: boolean()
  def completed?(%{episodes_completed: completed, episodes_total: total})
      when is_integer(completed) and is_integer(total) and total > 0, do: completed >= total

  def completed?(_), do: false

  @doc """
  True when the entity has been started but not finished — either a child
  item is fully watched, or the current item has a non-zero playback
  position. Returns `false` for fully-completed entities (use `completed?/1`).
  """
  @spec in_progress?(map() | nil) :: boolean()
  def in_progress?(%{episodes_completed: completed, episodes_total: total} = progress)
      when is_integer(completed) and is_integer(total) and total > 0 and completed < total do
    position = Map.get(progress, :episode_position_seconds, 0.0)
    completed > 0 or position > 0.0
  end

  def in_progress?(_), do: false

  @doc "Label for an entity that has never been watched."
  @spec play_label(map()) :: {String.t(), String.t()}
  def play_label(entity), do: {"Play", entity.id}

  @doc "Label for an entity whose entire content is completed."
  @spec watch_again_label(map()) :: {String.t(), String.t()}
  def watch_again_label(entity), do: {"Watch again", entity.id}

  @doc """
  Resume label derived from a resume hint (`%{"action" => "resume", ...}`).
  The hint's `targetId` (when present) is used as the click target so
  the play handler jumps directly to the child item.
  """
  @spec resume_label_from_hint(map(), map()) :: {String.t(), String.t()}
  def resume_label_from_hint(entity, hint) do
    {with_prefix("Resume", entity, hint), target_id_from_hint(hint, entity)}
  end

  @doc """
  Advance label derived from a resume hint (`%{"action" => "begin", ...}`).
  Used when the previously-watched item is complete and the user should
  start the next one fresh — labelled "Play Episode N" rather than
  "Resume" because there's no partial position to pick up from.
  """
  @spec advance_label_from_hint(map(), map()) :: {String.t(), String.t()}
  def advance_label_from_hint(entity, hint) do
    {with_prefix("Play", entity, hint), target_id_from_hint(hint, entity)}
  end

  @doc """
  Resume label derived only from a progress summary, used when no resume
  hint is available. Falls back to the entity id for the click target —
  the play handler resolves the actual child item from the entity's
  progress state.
  """
  @spec resume_label_from_progress(map(), map()) :: {String.t(), String.t()}
  def resume_label_from_progress(entity, progress) do
    {with_prefix_from_progress("Resume", entity, progress), entity.id}
  end

  # --- Hint-shape predicates ---

  defp resume_hint?(%{"action" => "resume"}), do: true
  defp resume_hint?(_), do: false

  defp advance_hint?(%{"action" => "begin"}), do: true
  defp advance_hint?(_), do: false

  # --- Label assembly (shared between hint cases) ---

  defp with_prefix(prefix, %{type: :tv_series}, %{"seasonNumber" => 1, "episodeNumber" => episode})
       when is_integer(episode), do: "#{prefix} Episode #{episode}"

  defp with_prefix(prefix, %{type: :tv_series}, %{"seasonNumber" => season, "episodeNumber" => episode})
       when is_integer(season) and is_integer(episode), do: "#{prefix} S#{season}E#{episode}"

  defp with_prefix(prefix, %{type: :movie_series}, hint), do: movie_series_label(prefix, hint)

  defp with_prefix(prefix, _entity, _hint), do: prefix

  # --- Label assembly from progress (no hint) ---

  defp with_prefix_from_progress(prefix, %{type: :tv_series}, %{
         current_episode: %{season: 1, episode: episode}
       })
       when is_integer(episode), do: "#{prefix} Episode #{episode}"

  defp with_prefix_from_progress(prefix, %{type: :tv_series}, %{
         current_episode: %{season: season, episode: episode}
       })
       when is_integer(season) and is_integer(episode), do: "#{prefix} S#{season}E#{episode}"

  defp with_prefix_from_progress(prefix, %{type: :movie_series}, %{
         current_episode: %{season: 0, episode: ordinal}
       })
       when is_integer(ordinal), do: "#{prefix} Movie #{ordinal}"

  defp with_prefix_from_progress(prefix, _entity, _progress), do: prefix

  # --- Hint helpers ---

  defp target_id_from_hint(%{"targetId" => id}, _entity) when is_binary(id), do: id
  defp target_id_from_hint(_hint, entity), do: entity.id

  defp movie_series_label(prefix, hint) do
    cond do
      blank_string?(Map.get(hint, "name")) and is_integer(Map.get(hint, "ordinal")) ->
        "#{prefix} Movie #{hint["ordinal"]}"

      blank_string?(Map.get(hint, "name")) ->
        prefix

      true ->
        "#{prefix} #{String.trim(hint["name"])}"
    end
  end

  # Inside this many days either side of today the pill speaks in
  # relative terms; beyond it, in a date.
  @relative_window_days 14

  @doc """
  Pill copy for an upcoming episode/movie row. Past dates read
  "aired Xd ago"; future dates read "in Xd". Beyond a fortnight either
  way it is the date itself, carrying the year unless it falls in the
  current one — "Aug 15" is only unambiguous for this year, and a row
  can carry a date decades old. `nil` air_date renders "TBA".

  Pure: extracted for unit testing without LiveView render. Shared by
  the season list's upcoming episode rows and the collection list's
  upcoming part rows.
  """
  @spec upcoming_pill_copy(map(), Date.t()) :: String.t()
  def upcoming_pill_copy(item, today \\ Date.utc_today())

  def upcoming_pill_copy(%{air_date: nil}, _today), do: "TBA"

  def upcoming_pill_copy(%{air_date: %Date{} = air_date}, today) do
    days = Date.diff(air_date, today)

    cond do
      days == 0 -> "today"
      days > 0 and days <= @relative_window_days -> "in #{days}d"
      days < 0 and days >= -@relative_window_days -> "aired #{abs(days)}d ago"
      air_date.year == today.year -> Calendar.strftime(air_date, "%b %-d")
      true -> Calendar.strftime(air_date, "%b %-d, %Y")
    end
  end

  @doc """
  Whether an air date is recent enough to be worth saying on a row for
  an episode the library does not have.

  A gap in a series that finished decades ago gains nothing from its air
  date — you know it aired, because the row is a gap and not an upcoming
  one. A gap that opened in the last fortnight is different: "aired 3d
  ago" is why you don't have it yet.
  """
  @spec recently_aired?(Date.t() | nil, Date.t()) :: boolean()
  def recently_aired?(air_date, today \\ Date.utc_today())

  def recently_aired?(nil, _today), do: false

  def recently_aired?(%Date{} = air_date, today) do
    days = Date.diff(air_date, today)
    days <= 0 and days >= -@relative_window_days
  end

  @doc """
  Renders an entity's status atom as a display string. Returns `nil` for
  `nil`, passes strings through unchanged.
  """
  def humanize_status(nil), do: nil
  def humanize_status(value) when is_binary(value), do: value

  def humanize_status(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp blank_facet?(%Facet{kind: :text, value: value}), do: blank_string?(value)
  defp blank_facet?(%Facet{kind: :chips, value: nil}), do: true
  defp blank_facet?(%Facet{kind: :chips, value: []}), do: true
  defp blank_facet?(%Facet{kind: :chips}), do: false

  defp blank_facet?(%Facet{kind: :rating, value: %{rating: rating}}) do
    !(is_number(rating) and rating > 0)
  end

  defp blank_string?(nil), do: true
  defp blank_string?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_string?(_), do: false

  # --- Modal views ---
  #
  # The detail modal shows one of three readings of a title: what is inside
  # it, Cast, and Manage. These answer which of them exist for a given
  # entity, which one a requested view resolves to, and what the single
  # control beside Play should offer — so the control and the URL can never
  # disagree about what is renderable.

  @doc """
  Whether the entity has content of its own to list — episodes, member
  movies, or entity-level extras.

  False for a bare movie: its main view is the orientation block alone
  (title, Play, synopsis — a page that fits without scrolling), and the
  body region below renders nothing.
  """
  @spec main_body?(map()) :: boolean()
  def main_body?(%{type: type}) when type in [:tv_series, :movie_series], do: true
  def main_body?(entity), do: entity_extras(entity) != []

  @doc """
  Entity-level extras — season-owned ones are rejected because they render
  beside their season in the episode list, not as extras of the title.
  """
  @spec entity_extras(map()) :: [map()]
  def entity_extras(%{extras: extras}) when is_list(extras),
    do: Enum.reject(extras, &(&1.owner_type == :season))

  def entity_extras(_entity), do: []

  @doc """
  Whether the entity has a Cast view. Collections do not — there is no
  collection-level cast to show.
  """
  @spec cast_tab?(map()) :: boolean()
  def cast_tab?(%{type: type}), do: type in [:movie, :tv_series]

  @doc """
  The view that a requested one resolves to for this entity.

  A view that cannot render must never be the selected one, whether it was
  asked for by URL or arrived at by default. Manage always renders.
  """
  @spec resolve_view(map(), atom()) :: atom()
  def resolve_view(_entity, :info), do: :info
  def resolve_view(entity, :cast), do: if(cast_tab?(entity), do: :cast, else: :main)
  def resolve_view(_entity, _main), do: :main

  @doc """
  Whether the panel is showing something other than the entity's root view,
  which is what tells the input system that BACK returns *within* the modal
  rather than dismissing it.

  Answered here rather than in JS because the root view is entity-dependent:
  a title with no contents of its own (a movie with no extras) has no body
  tab and opens on Cast, which is its root. The client used to infer
  this by comparing the view name to `"main"`, which got that case wrong in
  both directions — BACK left focus trapped in an overlay the server had
  already dismissed.

  A closed modal (`entity: nil`) is never nested.
  """
  @spec nested_view?(map() | nil, atom()) :: boolean()
  def nested_view?(nil, _detail_view), do: false
  def nested_view?(entity, detail_view), do: detail_view != resolve_view(entity, :main)

  @doc """
  The name of the entity's main view — the label for the control that
  returns there.

  Type-dependent because the main view is a different kind of thing per
  type, and there is no honest generic word covering episodes, member
  movies and extras at once. A title with no contents of its own reads
  "Overview": its main view is the hero page alone.
  """
  @spec body_label(map()) :: String.t()
  def body_label(%{type: :tv_series}), do: "Episodes"
  def body_label(%{type: :movie_series}), do: "Movies"
  def body_label(entity), do: if(main_body?(entity), do: "Extras", else: "Overview")

  @doc """
  The view the single control beside Play should go to, or `nil` when there
  is nowhere else to offer.

  The modal has one view control, in one slot, and it is labelled for its
  *destination* — "Episodes", "Movies", "Cast", "Overview" — never
  "Back". Naming the destination says where you are going; "Back" only
  says it is not here, and it changes meaning depending on which view you
  happen to be in.

  On the main view the control offers Cast where one exists; anywhere
  else it returns to the main view. `nil` covers the collection, the one
  entity with no Cast view — on its movie list there is nowhere else to
  offer.
  """
  @spec secondary_view(map(), atom()) :: :main | :cast | nil
  def secondary_view(entity, detail_view) do
    cond do
      detail_view != :main -> :main
      cast_tab?(entity) -> :cast
      true -> nil
    end
  end

  @doc """
  The film's Letterboxd page, via Letterboxd's stable
  `letterboxd.com/tmdb/<id>` redirect — no slug resolution or API
  involved. `nil` without a TMDB id.
  """
  @spec letterboxd_url(String.t() | nil) :: String.t() | nil
  def letterboxd_url(nil), do: nil
  def letterboxd_url(tmdb_id), do: "https://letterboxd.com/tmdb/#{tmdb_id}"

  @doc """
  The one honest primary action for a title detail, from its facts
  (UIDR-043): files win — an owned title plays, `{:play, props}` with the
  play card's label and target and the subject's watched fraction and
  time left (`member_playback/1` for a collection member, `playback_props/3`
  for anything else); then a plan or pursuit in flight is a stated fact,
  `{:state, state}`; then a title that is out with an indexer ready
  downloads, `{:download, scoped?}` — a series carries the scope menu;
  else `:none` — arming is the tracking controls' job, not a verb in the
  strip (ADR-066).
  """
  @spec primary_action(TitleDetail.t(), Date.t()) ::
          {:play,
           %{
             label: String.t(),
             target_id: String.t(),
             percent: number(),
             remaining_text: String.t() | nil
           }}
          | {:state, :planning | :downloading | :needs_review}
          | {:download, boolean()}
          | :none
  def primary_action(%TitleDetail{library: %Library{} = library}, _today),
    do: {:play, library_playback(library)}

  def primary_action(%TitleDetail{acquisition_state: state}, _today) when not is_nil(state),
    do: {:state, state}

  def primary_action(%TitleDetail{release_mode_available: true, title: title}, today) do
    if MediaResults.release_status(title, today) == :released,
      do: {:download, title.media_type == :tv_series},
      else: :none
  end

  def primary_action(%TitleDetail{}, _today), do: :none

  defp library_playback(%Library{member: %MovieRow.Library{} = member}), do: member_playback(member)

  defp library_playback(%Library{entry: entry}) do
    {label, target_id} = playback_props(entry.entity, entry.resume_target, entry.progress)

    %{
      label: label,
      target_id: target_id,
      percent: overall_progress_percent(entry.progress, entry.entity),
      remaining_text: progress_remaining_text(entry.progress, entry.entity)
    }
  end

  @doc """
  Whether the tracking card under the body has anything to show — one
  rule for an owned and an unowned title alike: the switches once the
  title is listed (or the Ignored word), the dates once there is a
  calendar or a movie's live release window, the note once a lower
  quality is accepted.
  """
  @spec tracking_card?(TitleDetail.t()) :: boolean()
  def tracking_card?(%TitleDetail{} = detail) do
    release_dates?(detail) or TrackingControls.control_form(detail.rung) != :none or
      detail.lower_quality_accepted?
  end

  @doc """
  Whether the release dates readout has something to say: a calendar
  (the title is tracked), or a movie's live release window.
  """
  @spec release_dates?(TitleDetail.t()) :: boolean()
  def release_dates?(%TitleDetail{title: %{media_type: :movie}, release_window: %{}}), do: true
  def release_dates?(%TitleDetail{tracking: %TrackingDetail{}}), do: true
  def release_dates?(_detail), do: false

  @doc """
  A leaf's watched fraction as a percent (UIDR-024): containers derive
  theirs from `ViewModel.Orientation`; a movie's or member's comes from
  its progress summary here.
  """
  @spec overall_progress_percent(map() | nil, map()) :: non_neg_integer()
  def overall_progress_percent(nil, _entity), do: 0

  def overall_progress_percent(progress, _entity) do
    if progress.episode_duration_seconds > 0 do
      min(round(progress.episode_position_seconds / progress.episode_duration_seconds * 100), 100)
    else
      if progress.episodes_completed > 0, do: 100, else: 0
    end
  end

  @doc """
  The metadata line's remaining item (UIDR-024). Completed titles yield
  nil — the full hairline and the watched toggle carry that state; the
  metadata line goes back to showing the status.
  """
  @spec progress_remaining_text(map() | nil, map()) :: String.t() | nil
  def progress_remaining_text(nil, _entity), do: nil

  def progress_remaining_text(progress, _entity) do
    if progress.episodes_completed == 0 && progress.episode_duration_seconds > 0 &&
         progress.episode_position_seconds > 0 do
      remaining_seconds = progress.episode_duration_seconds - progress.episode_position_seconds
      "#{format_human_duration(trunc(remaining_seconds))} left"
    end
  end
end
