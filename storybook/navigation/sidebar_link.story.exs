defmodule MediaCentaurWeb.Storybook.Navigation.SidebarLink do
  @moduledoc """
  One entry of the main navigation rail. Each entry says where you are
  (`active`), what waits (`count`, `condition`) and, under keyboard or
  gamepad steering, where the cursor is — the ring is the input system's
  and is not shown here. The accent is primary for a page and the person's
  hue for the profile switcher (UIDR-030, UIDR-053).
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.SidebarLink.sidebar_link/1
  def render_source, do: :function

  # The rail's ground, so the washes read as they do in the shell.
  def template do
    """
    <div class="glass-sidebar inline-flex flex-col gap-0.5 p-2 rounded-lg" psb-code-hidden>
      <.psb-variation-group/>
    </div>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :watch,
        description: "A Watch entry at rest and as the current page.",
        variations: [
          %Variation{
            id: :rest,
            attributes: %{
              id: "rail-library",
              navigate: "/library",
              label: "Library",
              icon: "hero-book-open"
            }
          },
          %Variation{
            id: :active,
            attributes: %{id: "rail-home", navigate: "/", label: "Home", icon: "hero-home", active: true}
          }
        ]
      },
      %VariationGroup{
        id: :system,
        description:
          "System entries sit dimmer at rest. A count is the follow-up pill at the box's corner; a condition is the dot at the icon.",
        variations: [
          %Variation{
            id: :rest,
            attributes: %{
              id: "rail-settings",
              navigate: "/settings",
              label: "Settings",
              icon: "hero-cog-6-tooth",
              system: true
            }
          },
          %Variation{
            id: :active,
            attributes: %{
              id: "rail-settings-active",
              navigate: "/settings",
              label: "Settings",
              icon: "hero-cog-6-tooth",
              system: true,
              active: true
            }
          },
          %Variation{
            id: :count,
            attributes: %{
              id: "rail-review",
              navigate: "/review",
              label: "Review",
              icon: "hero-document-text",
              system: true,
              count: 3
            }
          },
          %Variation{
            id: :count_and_condition,
            attributes: %{
              id: "rail-status",
              navigate: "/status",
              label: "Status",
              icon: "hero-squares-2x2",
              system: true,
              count: 12,
              condition: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :profile,
        description: "The profile switcher takes the person's hue as its accent, at rest and current.",
        variations: [
          %Variation{
            id: :rest,
            attributes: %{
              id: "rail-profile",
              navigate: "/profiles",
              label: "Ana · Switch profile",
              icon: "hero-user-circle",
              system: true,
              hue: 150
            }
          },
          %Variation{
            id: :active,
            attributes: %{
              id: "rail-profile-active",
              navigate: "/profiles",
              label: "Ana · Switch profile",
              icon: "hero-user-circle",
              system: true,
              hue: 150,
              active: true
            }
          }
        ]
      }
    ]
  end
end
