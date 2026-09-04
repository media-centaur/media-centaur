defmodule MediaCentaurWeb.Components.Detail.TrackOverrideBadge do
  @moduledoc """
  *Remembered tracks* badge for the detail modal's Manage view —
  per-entity remembered audio/subtitle track selection with a reset
  button.

  Rendered only when an override exists (movies + TV series carry it via
  `Library.MediaTrackOverrides.put_on_entity/1`); other container kinds
  and all-policy overrides render nothing. The Reset button clears the
  override via the EntityModal-injected `reset_track_override` event.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Library.MediaTrackOverride
  alias MediaCentaur.Playback.Iso639

  attr :entity, :map,
    required: true,
    doc: "`MediaCentaur.Library.EntityView`. Reads `:track_override`."

  def track_override_badge(%{entity: %{track_override: %MediaTrackOverride{} = override}} = assigns) do
    assigns = assign(assigns, :segments, track_override_summary(override))

    ~H"""
    <%!-- inline-flex: the card hugs its content so Reset sits right beside
          the summary it clears — stretched full-width, the two ended up at
          opposite edges of the sheet with no visible connection. --%>
    <div
      :if={@segments != []}
      class="glass-inset rounded-lg px-3 py-2.5 inline-flex items-center gap-4"
    >
      <div class="flex items-center gap-2 min-w-0">
        <.icon name="hero-language-mini" class="size-4 text-base-content/50 shrink-0" />
        <div class="min-w-0">
          <div class="text-xs uppercase tracking-wider text-base-content/50">Remembered tracks</div>
          <div class="text-sm text-base-content truncate">{Enum.join(@segments, " · ")}</div>
        </div>
      </div>
      <.button
        variant="neutral"
        size="xs"
        phx-click="reset_track_override"
        class="shrink-0"
        data-nav-item
        tabindex="0"
      >
        Reset to default
      </.button>
    </div>
    """
  end

  def track_override_badge(assigns), do: ~H""

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
end
