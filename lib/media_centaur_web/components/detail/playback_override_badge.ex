defmodule MediaCentaurWeb.Components.Detail.PlaybackOverrideBadge do
  @moduledoc """
  *Remembered settings* badge for the detail modal's Manage view —
  per-entity remembered playback settings (audio and subtitle tracks, the
  picture's Fill width) with a reset button.

  Rendered only when an override exists (movies + TV series carry it via
  `Library.PlaybackOverrides.put_on_entity/2`); other container kinds
  and all-policy overrides render nothing. The Reset button clears the
  override via the host's `reset_playback_override` event.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Library.PlaybackOverride
  alias MediaCentaur.Iso639

  attr :entity, :map,
    required: true,
    doc: "`MediaCentaur.Library.EntityView`. Reads `:playback_override`."

  def playback_override_badge(%{entity: %{playback_override: %PlaybackOverride{} = override}} = assigns) do
    assigns = assign(assigns, :segments, playback_override_summary(override))

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
          <div class="text-xs uppercase tracking-wider text-base-content/55">Remembered settings</div>
          <div class="text-sm text-base-content truncate">{Enum.join(@segments, " · ")}</div>
        </div>
      </div>
      <.button
        variant="neutral"
        size="xs"
        phx-click="reset_playback_override"
        class="shrink-0"
        data-nav-item
        tabindex="0"
      >
        Reset to default
      </.button>
    </div>
    """
  end

  def playback_override_badge(assigns), do: ~H""

  @doc """
  Human-readable segments describing a captured per-entity playback
  override, for the *Remembered settings* badge. Audio first, then
  subtitles, then the picture (`"Fill width"`, or `"Fit"` when chosen;
  a picture on its default is not said). Aspects left to policy (`nil`) are omitted; `subtitles_off`
  yields `"Subtitles off"`; a forced subtitle gets a `" (forced)"`
  suffix. Returns `[]` when no aspect diverges — the badge then renders
  nothing.

  Languages are shown by their English names (`Japanese`, `English`) via
  `Iso639.display_name/1`; unknown codes fall back to the raw code.
  """
  @spec playback_override_summary(PlaybackOverride.t()) :: [String.t()]
  def playback_override_summary(%PlaybackOverride{} = override) do
    Enum.reject(
      [audio_segment(override), subtitle_segment(override), picture_segment(override)],
      &is_nil/1
    )
  end

  defp picture_segment(%PlaybackOverride{fill_width: true}), do: "Fill width"
  defp picture_segment(%PlaybackOverride{fill_width: false}), do: "Fit"
  defp picture_segment(_override), do: nil

  defp audio_segment(%PlaybackOverride{audio_lang: lang}) when is_binary(lang),
    do: "#{Iso639.display_name(lang)} audio"

  defp audio_segment(_override), do: nil

  defp subtitle_segment(%PlaybackOverride{subtitles_off: true}), do: "Subtitles off"

  defp subtitle_segment(%PlaybackOverride{subtitle_lang: lang, subtitle_forced: forced})
       when is_binary(lang) do
    name = Iso639.display_name(lang)
    if forced, do: "#{name} subtitles (forced)", else: "#{name} subtitles"
  end

  defp subtitle_segment(_override), do: nil
end
