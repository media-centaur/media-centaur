defmodule MediaCentaurWeb.Components.Detail.MoreInfoPanel do
  @moduledoc """
  *More info* sub-view of the detail modal — opened from the PlayCard's
  *More info* button. Acts as a thin shell that composes per-type
  credit rendering with shared cast and external-link sub-components.

  Composition (top-to-bottom):

    1. **Headline credits** — `MovieCredits.headline/1` for movies
       (Directed by / Written by), `SeriesCredits.headline/1` for
       TV series (Created by). Dispatched by `entity.type`.
    2. **Cast grid** — shared `CastGrid.cast_grid/1`. Identical
       layout for movies and series.
    3. **Meta block** — `MovieCredits.meta_block/1` (Studio /
       Country / Language / Runtime / Released) for movies,
       `SeriesCredits.meta_block/1` (Network / First aired / Status
       / Country / Language) for series.
    4. **External links** — shared `ExternalLinks.external_links/1`
       (TMDB + IMDb).

  Person names link to TMDB person pages when `tmdb_person_id` is
  present; otherwise rendered as plain text. Profile photos hotlink
  from `image.tmdb.org/t/p/w185{path}` — same convention the rest of
  the app uses for unimported TMDB artwork.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Library.MediaTrackOverride
  alias MediaCentaur.Playback.Iso639

  alias MediaCentaur.Subtitles

  alias MediaCentaurWeb.Components.Detail.MoreInfo.{
    CastGrid,
    ExternalLinks,
    FileDetails,
    MovieCredits,
    SeriesCredits
  }

  alias MediaCentaurWeb.Components.Detail.SubtitlesRow

  attr :entity, :map,
    required: true,
    doc:
      "entity-map produced by `MediaCentaur.Library.Views.DetailItem.to_entity_map/1` (Phase 3.2 Task D). Loose-typed because it spans multiple container kinds; the shell reads `:type` to dispatch and forwards the map to per-type sub-components. Typed-attr migration is a Phase 3.3 follow-up."

  attr :cast_filter, :string,
    default: "",
    doc: "current cast filter query, owned by the host LiveView and forwarded to `CastGrid`."

  def more_info_panel(assigns) do
    subtitle_languages = subtitle_languages_for(assigns.entity)

    # Understood languages lead the subtitles row; the rest fold behind
    # the trailing-+ reveal. Read here (prod: SettingsCache) rather than
    # threaded through every modal host.
    understood_languages =
      if subtitle_languages == [],
        do: [],
        else: MediaCentaur.Playback.LanguagePolicy.load().understood_languages

    assigns =
      assigns
      |> assign(:subtitle_languages, subtitle_languages)
      |> assign(:understood_languages, understood_languages)

    ~H"""
    <section class="space-y-6 pt-2 pb-4">
      <%!-- Credits left; the file's own facts (probed tech line +
            subtitle languages) right — the headline pair is short, so
            the row's right half was dead space. --%>
      <div class="grid gap-6 sm:grid-cols-2 sm:items-start">
        <.headline_for_type entity={@entity} />
        <div class="min-w-0 space-y-3">
          <FileDetails.file_details files={@entity[:watched_files] || []} />
          <SubtitlesRow.subtitles_row
            languages={@subtitle_languages}
            understood={@understood_languages}
          />
        </div>
      </div>
      <CastGrid.cast_grid cast={@entity[:cast] || []} filter={@cast_filter} />
      <.meta_for_type entity={@entity} />
      <.track_override_badge entity={@entity} />
      <ExternalLinks.external_links tmdb_url={@entity[:url]} imdb_id={@entity[:imdb_id]} />
    </section>
    """
  end

  # Movies are the only type with detected subtitles for v1. Series'
  # episodes each carry their own WatchedFile with its own tracks;
  # aggregating across episodes needs a different display story
  # (per-season? show-wide?). Skip non-movies entirely so the row
  # never renders for them. Reads the projection's already-loaded
  # tracks — never re-queried.
  defp subtitle_languages_for(%{type: :movie, subtitle_tracks: tracks}) when is_list(tracks),
    do: Subtitles.aggregate_track_languages(tracks)

  defp subtitle_languages_for(_entity), do: []

  # Per-entity remembered audio/subtitle track selection. Rendered only
  # when an override exists (movies + TV series carry it via
  # `Library.MediaTrackOverrides.put_on_entity/1`); other container kinds and
  # all-policy overrides render nothing. The Reset button clears the
  # override via the EntityModal-injected `reset_track_override` event.
  defp track_override_badge(%{entity: %{track_override: %MediaTrackOverride{} = override}} = assigns) do
    assigns = assign(assigns, :segments, track_override_summary(override))

    ~H"""
    <div
      :if={@segments != []}
      class="glass-inset rounded-lg px-3 py-2.5 flex items-center justify-between gap-3"
    >
      <div class="flex items-center gap-2 min-w-0">
        <.icon name="hero-language-mini" class="size-4 text-base-content/50 shrink-0" />
        <div class="min-w-0">
          <div class="text-xs uppercase tracking-wider text-base-content/50">Remembered tracks</div>
          <div class="text-sm text-base-content truncate">{Enum.join(@segments, " · ")}</div>
        </div>
      </div>
      <.button variant="neutral" size="xs" phx-click="reset_track_override" class="shrink-0">
        Reset to default
      </.button>
    </div>
    """
  end

  defp track_override_badge(assigns), do: ~H""

  @doc """
  Human-readable segments describing a captured per-entity track
  override, for the *Remembered tracks* badge. Audio first, then
  subtitles. Aspects left to policy (`nil`) are omitted; `subtitles_off`
  yields `"Subtitles off"`; a forced subtitle gets a `" (forced)"`
  suffix. Returns `[]` when no aspect diverges — the badge then renders
  nothing.

  Languages are shown by their English names (`Japanese`, `English`) via
  `Iso639.display_name/1`; unknown codes fall back to the raw code.
  """
  @spec track_override_summary(MediaTrackOverride.t()) :: [String.t()]
  def track_override_summary(%MediaTrackOverride{} = override) do
    Enum.reject([audio_segment(override), subtitle_segment(override)], &is_nil/1)
  end

  defp audio_segment(%MediaTrackOverride{audio_lang: lang}) when is_binary(lang),
    do: "#{Iso639.display_name(lang)} audio"

  defp audio_segment(_override), do: nil

  defp subtitle_segment(%MediaTrackOverride{subtitles_off: true}), do: "Subtitles off"

  defp subtitle_segment(%MediaTrackOverride{subtitle_lang: lang, subtitle_forced: forced})
       when is_binary(lang) do
    name = Iso639.display_name(lang)
    if forced, do: "#{name} subtitles (forced)", else: "#{name} subtitles"
  end

  defp subtitle_segment(_override), do: nil

  defp headline_for_type(%{entity: %{type: :movie}} = assigns) do
    MovieCredits.headline(assigns)
  end

  defp headline_for_type(%{entity: %{type: :tv_series}} = assigns) do
    SeriesCredits.headline(assigns)
  end

  defp headline_for_type(assigns) do
    ~H""
  end

  defp meta_for_type(%{entity: %{type: :movie}} = assigns) do
    MovieCredits.meta_block(assigns)
  end

  defp meta_for_type(%{entity: %{type: :tv_series}} = assigns) do
    SeriesCredits.meta_block(assigns)
  end

  defp meta_for_type(assigns) do
    ~H""
  end
end
