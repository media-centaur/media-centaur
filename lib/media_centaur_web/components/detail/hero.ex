defmodule MediaCentaurWeb.Components.Detail.Hero do
  @moduledoc """
  21:9 detail-panel hero — a transparent positioning frame for the logo
  overlay (or title fallback), optional tagline, and a top-right `actions`
  slot for things like the release-tracking bell.

  The backdrop image and atmospheric scrims live at the modal-panel level
  (`ModalShell`), where they extend past this frame into the metadata
  region for a cinematic continuation. This component is purely the title
  layer that sits on top.

  Type-agnostic — takes an `entity` for image lookup and name fallback only.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [image_url: 2]

  alias MediaCentaurWeb.Components.Detail.TitleLayer

  attr :entity, :map,
    required: true,
    doc:
      "polymorphic entity-map from `MediaCentaur.Library.Views.DetailItem.to_entity_map/1`. Reads `:name` and `:images` only, so the union stays untyped at this layer; tightening to a typed `DetailItem` attr is a Phase 3.3 follow-up (component-contracts campaign)."

  attr :tagline, :string, default: nil
  attr :available, :boolean, default: true

  attr :season_fraction, :float,
    default: nil,
    doc:
      "current-season watched fraction (0.0–1.0) from `MediaCentaurWeb.ViewModel.Orientation.season_fraction/1`. Non-nil renders the luminous season-progress hairline pinned to the frame's bottom edge (TV series orientation); `nil` (movies, collections) suppresses the track entirely."

  slot :actions, doc: "top-right overlay actions (tracking bell, etc.)"

  def hero(assigns) do
    backdrop = image_url(assigns.entity, "backdrop")
    background = backdrop || image_url(assigns.entity, "poster")
    logo = image_url(assigns.entity, "logo")
    show_placeholder? = !background || !assigns.available

    assigns =
      assigns
      |> assign(:logo, logo)
      |> assign(:show_placeholder?, show_placeholder?)

    ~H"""
    <div class="detail-hero relative">
      <%!-- Empty state when artwork is missing or storage isn't mounted —
            ModalShell renders no panel-level backdrop in those cases, so
            the shared TitleLayer fills the 21:9 frame with its quiet
            placeholder. An unavailable entity also drops the logo back
            to the title logotype. --%>
      <TitleLayer.title_layer
        title={@entity.name}
        logo_url={(@available && @logo) || nil}
        tagline={@tagline}
        placeholder?={@show_placeholder?}
      >
        <:actions :if={@actions != []}>{render_slot(@actions)}</:actions>
      </TitleLayer.title_layer>
      <div
        :if={@season_fraction}
        class="season-hairline"
        role="progressbar"
        aria-valuenow={round(@season_fraction * 100)}
        aria-valuemin="0"
        aria-valuemax="100"
        aria-label="Season progress"
      >
        <div class="season-hairline-fill" style={"width: #{@season_fraction * 100}%"} />
      </div>
    </div>
    """
  end
end
