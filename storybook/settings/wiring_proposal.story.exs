defmodule MediaCentaurWeb.Storybook.Settings.WiringProposal do
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Downloads.Wiring.Proposal

  def function, do: &MediaCentaurWeb.Components.Settings.WiringProposal.wiring_proposal/1
  def render_source, do: :function
  def layout, do: :one_column

  @digest "0f3a"

  @prowlarr %{
    id: :prowlarr,
    url: "http://127.0.0.1:9696",
    new?: true,
    changes: [:prowlarr_url, :prowlarr_api_key]
  }

  @torrent %{
    id: :download_client,
    url: "http://127.0.0.1:8080",
    new?: true,
    changes: [
      :download_client_type,
      :download_client_url,
      :download_client_username,
      :download_client_password
    ]
  }

  @usenet %{
    id: :usenet_download_client,
    url: "http://127.0.0.1:8085",
    new?: true,
    changes: [:usenet_download_client_type, :usenet_download_client_url, :usenet_download_client_api_key]
  }

  def variations do
    [
      %Variation{
        id: :first_install,
        description:
          "Nothing saved yet: all three connections are new, and the completed directory is inside a media directory.",
        attributes: %{
          wiring:
            {:proposal,
             %Proposal{
               digest: @digest,
               connections: [@prowlarr, @torrent, @usenet],
               completed_dir: "/mnt/videos/completed",
               completed_dir_watched?: true
             }}
        }
      },
      %Variation{
        id: :changed_credential,
        description:
          "The stack regenerated one credential: only that connection is listed, with the fields that change.",
        attributes: %{
          wiring:
            {:proposal,
             %Proposal{
               digest: @digest,
               connections: [%{@usenet | new?: false, changes: [:usenet_download_client_api_key]}],
               completed_dir: "/mnt/videos/completed",
               completed_dir_watched?: true
             }}
        }
      },
      %Variation{
        id: :moved,
        description: "A new connection beside one whose address and credential changed.",
        attributes: %{
          wiring:
            {:proposal,
             %Proposal{
               digest: @digest,
               connections: [
                 %{@prowlarr | new?: false},
                 @usenet
               ],
               completed_dir: "/mnt/videos/completed",
               completed_dir_watched?: true
             }}
        }
      },
      %Variation{
        id: :completed_dir_not_watched,
        description:
          "The completed directory is outside every media directory: the line says so and links to Settings → Library.",
        attributes: %{
          wiring:
            {:proposal,
             %Proposal{
               digest: @digest,
               connections: [@prowlarr, @torrent, @usenet],
               completed_dir: "/srv/downloads/completed",
               completed_dir_watched?: false
             }}
        }
      },
      %Variation{
        id: :narrow,
        description: "A half-width window at 2× UI scale: the actions drop beneath the title.",
        template: ~s|<div class="w-[21rem]"><.psb-variation/></div>|,
        attributes: %{
          wiring:
            {:proposal,
             %Proposal{
               digest: @digest,
               connections: [@prowlarr, @torrent, @usenet],
               completed_dir: "/mnt/videos/completed",
               completed_dir_watched?: true
             }}
        }
      },
      %VariationGroup{
        id: :unusable,
        description: "A wiring that cannot be used: the reason, no actions, nothing applied.",
        variations: [
          %Variation{id: :unknown_format, attributes: %{wiring: {:error, {:unknown_format, 2}}}},
          %Variation{id: :malformed, attributes: %{wiring: {:error, :malformed}}},
          %Variation{
            id: :unsupported_client,
            attributes: %{wiring: {:error, {:unsupported_client, "otherclient"}}}
          },
          %Variation{id: :writable_by_others, attributes: %{wiring: {:error, :writable_by_others}}},
          %Variation{id: :unreadable, attributes: %{wiring: {:error, {:unreadable, :eacces}}}}
        ]
      }
    ]
  end
end
