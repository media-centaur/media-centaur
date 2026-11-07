defmodule MediaCentaurWeb.Storybook.Detail.PlaybackOverrideBadge do
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.EntityView
  alias MediaCentaur.Library.PlaybackOverride

  def function, do: &MediaCentaurWeb.Components.Detail.PlaybackOverrideBadge.playback_override_badge/1

  @entity %EntityView{id: "00000000-0000-0000-0000-0000000000b1", type: :movie, name: "Sample Movie"}

  defp with_override(override), do: %{@entity | playback_override: override}

  def variations do
    [
      %Variation{
        id: :audio_and_subtitles,
        description:
          "Captured per-entity playback override — audio + subtitle languages " <>
            "and a Reset action.",
        attributes: %{
          entity:
            with_override(%PlaybackOverride{
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
            with_override(%PlaybackOverride{
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
            with_override(%PlaybackOverride{
              owner_type: :tv_series,
              owner_id: "00000000-0000-0000-0000-000000000003",
              subtitle_lang: "eng",
              subtitle_forced: true
            })
        }
      },
      %Variation{
        id: :fill_width,
        description: "Picture remembered as Fill width beside a remembered audio language.",
        attributes: %{
          entity:
            with_override(%PlaybackOverride{
              owner_type: :tv_series,
              owner_id: "00000000-0000-0000-0000-000000000004",
              audio_lang: "eng",
              fill_width: true
            })
        }
      },
      %Variation{
        id: :fill_width_only,
        description: "Only the picture remembered — the badge reads 'Fill width'.",
        attributes: %{
          entity:
            with_override(%PlaybackOverride{
              owner_type: :tv_series,
              owner_id: "00000000-0000-0000-0000-000000000005",
              fill_width: true
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
