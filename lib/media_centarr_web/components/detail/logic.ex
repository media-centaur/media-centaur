defmodule MediaCentarrWeb.Components.Detail.Logic do
  @moduledoc """
  Pure helpers for the entity detail panel — facet-strip composition and
  the small string transforms used in the metadata row.

  Per ADR-030, all non-trivial branching that would otherwise live in the
  detail panel templates is hoisted here so it can be unit-tested with
  `async: true` and `build_*` factory helpers.
  """

  alias MediaCentarrWeb.Components.Detail.Facet

  @doc """
  Returns the list of facets for an entity, ready for `Detail.FacetStrip`.

  Country and Status are intentionally absent — they already appear in the
  metadata row above the strip and would be duplicates here.

  Variants:

    * `facets_for(:movie, movie)` — Director, Rating, Original language, Studio, Genres
    * `facets_for(:tv_series, tv)` — Network, Rating, Original language, Genres
    * `facets_for(:movie_series, ms, movies)` — Movies, Rating, First released, Latest, Genres

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

  @spec facets_for(:movie_series, map(), [map()]) :: [Facet.t()]
  def facets_for(:movie_series, movie_series, movies) when is_list(movies) do
    years = movie_series_years(movies)

    Enum.reject(
      [
        Facet.text("Movies", movie_count(movies)),
        Facet.rating(
          "Rating",
          Map.get(movie_series, :aggregate_rating_value),
          Map.get(movie_series, :vote_count)
        ),
        Facet.text("First released", List.first(years)),
        Facet.text("Latest", List.last(years)),
        Facet.chips("Genres", Map.get(movie_series, :genres))
      ],
      &blank_facet?/1
    )
  end

  @doc """
  Extracts the 4-digit year from an ISO 8601 date string. Returns `nil` for
  any input that doesn't match.
  """
  def year_from_date(nil), do: nil
  def year_from_date(""), do: nil

  def year_from_date(<<year::binary-size(4), "-", _rest::binary>>) when byte_size(year) == 4 do
    if String.match?(year, ~r/^\d{4}$/), do: year
  end

  def year_from_date(_), do: nil

  @doc """
  Formats an ISO 8601 duration string (`"PT1H55M"`) into a compact human
  form (`"1h 55m"`). Returns `nil` for `nil`, blank, or malformed input —
  never crashes on bad data.
  """
  def format_duration(nil), do: nil
  def format_duration(""), do: nil

  def format_duration("PT" <> rest) do
    {hours, after_hours} = take_iso_component(rest, "H")
    {minutes, _tail} = take_iso_component(after_hours, "M")

    case {hours, minutes} do
      {nil, nil} -> nil
      {nil, m} -> "#{m}m"
      {h, nil} -> "#{h}h"
      {h, m} -> "#{h}h #{m}m"
    end
  end

  def format_duration(_), do: nil

  defp take_iso_component(string, suffix) do
    case String.split(string, suffix, parts: 2) do
      [num, rest] ->
        case Integer.parse(num) do
          {n, ""} -> {n, rest}
          _ -> {nil, string}
        end

      [_only] ->
        {nil, string}
    end
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

  defp movie_series_years(movies) do
    movies
    |> Enum.map(&year_from_date(&1.date_published))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp movie_count([]), do: nil
  defp movie_count(movies), do: Integer.to_string(length(movies))

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
end
