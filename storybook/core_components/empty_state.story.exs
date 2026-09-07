defmodule MediaCentaurWeb.Storybook.CoreComponents.EmptyState do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.CoreComponents.empty_state/1
  def render_source, do: :function

  # The variations are the real copy from the surfaces that use the component,
  # so the catalog doubles as the empty-state copy review. Each one states what
  # fills the place and the one action that changes it (UIDR-022 stance) — none
  # of them says "nothing here yet".
  def variations do
    [
      %VariationGroup{
        id: :diagnosed_reasons,
        description:
          "Home is empty for one of three reasons. The page diagnoses which in a pure function; the component renders the matching copy and CTA.",
        variations: [
          %Variation{
            id: :no_media_dirs,
            description: "No media directory configured",
            attributes: %{icon: "hero-film", headline: "Point it at your media"},
            slots: [
              """
              Home fills itself once files are found: what to watch next, the titles you are
              partway through, new episodes on the way, and what was added last.
              <:action>
                <MediaCentaurWeb.CoreComponents.button variant="primary" size="sm">
                  Add a media directory
                </MediaCentaurWeb.CoreComponents.button>
              </:action>
              """
            ]
          },
          %Variation{
            id: :importing,
            description: "Import in flight — the work is happening, so there is no action",
            attributes: %{icon: "hero-arrow-down-on-square-stack", headline: "Importing your media"},
            slots: ["12 files to go."]
          },
          %Variation{
            id: :nothing_imported,
            description: "Directories configured, nothing came back",
            attributes: %{icon: "hero-film", headline: "Nothing imported yet"},
            slots: [
              """
              Your media directories are set, but no video files have been imported from them.
              <:action>
                <MediaCentaurWeb.CoreComponents.button variant="primary" size="sm">
                  Scan media directories
                </MediaCentaurWeb.CoreComponents.button>
              </:action>
              """
            ]
          }
        ]
      },
      %Variation{
        id: :no_action,
        description: "A surface whose emptiness is not the user's to fix reads as a statement",
        attributes: %{icon: "hero-check-circle", headline: "All clear"},
        slots: [
          "Files that cannot be matched to a title automatically land here for you to match by hand."
        ]
      },
      %Variation{
        id: :two_actions,
        description:
          "Two actions is the ceiling — beyond that the surface is a menu, not an empty state",
        attributes: %{icon: "hero-users", headline: "Recommendations from friends land here"},
        slots: [
          """
          Add a relay so Media Centaur can reach the network, then add a friend by their public key.
          <:action>
            <MediaCentaurWeb.CoreComponents.button variant="primary" size="sm">Add a relay</MediaCentaurWeb.CoreComponents.button>
          </:action>
          <:action>
            <MediaCentaurWeb.CoreComponents.button variant="dismiss" size="sm">Add a friend</MediaCentaurWeb.CoreComponents.button>
          </:action>
          """
        ]
      },
      %Variation{
        id: :no_icon,
        description: "A tab body inside an already-titled page drops the icon and keeps the rest",
        attributes: %{headline: "Nothing on your watchlist"},
        slots: ["Titles you save from a search are kept here until you watch them."]
      }
    ]
  end
end
