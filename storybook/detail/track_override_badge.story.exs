defmodule MediaCentaurWeb.Storybook.Detail.TrackOverrideBadge do
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.EntityView
  alias MediaCentaur.Library.MediaTrackOverride

  def function, do: &MediaCentaurWeb.Components.Detail.TrackOverrideBadge.track_override_badge/1

  @entity %EntityView{id: "00000000-0000-0000-0000-0000000000b1", type: :movie, name: "Sample Movie"}

  defp with_override(override), do: %{@entity | track_override: override}

  def variations do
    [
      %Variation{
        id: :audio_and_subtitles,
        description:
          "Captured per-entity track override — audio + subtitle languages " <>
            "and a Reset action.",
        attributes: %{
          entity:
            with_override(%MediaTrackOverride{
              owner_type: :movie,
              owner_id: "00000000-0000-0000-0000-000000000001",
              audio_lang: "jpn",
              subtitle_lang: "eng"
            })
        }
      },
      %Variation{
        id: :subtitles_off,
        description: "Override that disables subtitles — badge reads 'Subtitles off'.",
        attributes: %{
          entity:
            with_override(%MediaTrackOverride{
              owner_type: :movie,
              owner_id: "00000000-0000-0000-0000-000000000002",
              audio_lang: "eng",
              subtitles_off: true
            })
        }
      },
      %Variation{
        id: :forced_subtitles,
        description: "Forced-subtitle override — '(forced)' suffix on the language.",
        attributes: %{
          entity:
            with_override(%MediaTrackOverride{
              owner_type: :tv_series,
              owner_id: "00000000-0000-0000-0000-000000000003",
              subtitle_lang: "eng",
              subtitle_forced: true
            })
        }
      },
      %Variation{
        id: :no_override,
        description: "No override on the entity — the badge renders nothing.",
        attributes: %{entity: @entity}
      }
    ]
  end
end
