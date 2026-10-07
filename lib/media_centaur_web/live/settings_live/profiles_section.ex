defmodule MediaCentaurWeb.SettingsLive.ProfilesSection do
  @moduledoc """
  The Profiles section of the Settings page (ADR-078, UIDR-053 rule 5):
  one card per profile — the tile, Picture (an Add/Change picture button
  that opens the one picture field with its crop stage, one card at a
  time, saved by its own Save; Remove pending until that save), Name
  (saves on blur or Enter), Colour (`HueSwatches`, saves on the act) —
  with Remove profile as an arm gesture in the card's action slot,
  disabled on the last profile; and an Add card. `SettingsLive`
  delegates to `render/1` and hosts the handlers: `edit_profile_picture`,
  `stop_editing_picture`, `remove_profile_picture`,
  `cancel_profile_picture`, `save_profile_picture`,
  `validate_profile_card`, `set_profile_hue`, `rename_profile`,
  `remove_profile`, `add_profile`. The list itself is
  `Live.ProfileAware`'s `@profiles`, kept live by the hook.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Profiles
  alias MediaCentaurWeb.Components.PictureField
  alias MediaCentaurWeb.Components.Social.HueSwatches
  alias MediaCentaurWeb.Components.Social.IdentityTile
  alias MediaCentaurWeb.Live.ArmGesture

  attr :profiles, :list,
    required: true,
    doc: "every `Profiles.Profile`, oldest first (`Live.ProfileAware`)"

  attr :uploads, :map, required: true, doc: "the LiveView's `@uploads`; `.profile_picture` is the field"
  attr :picture_editing, :string, default: nil, doc: "the id whose card shows the picture field"
  attr :picture_removed, :string, default: nil, doc: "the id whose Remove is pending until its save"
  attr :armed_gesture, :any, required: true, doc: "the page's `ArmGesture` slot"

  def render(assigns) do
    ~H"""
    <div id="settings-profiles" class="space-y-4">
      <.settings_card
        :for={profile <- @profiles}
        id={"profile-card-#{profile.id}"}
        title={profile.name}
        data-nav-grid
      >
        <:action>
          <.armed_button
            id={"remove-profile-#{profile.id}"}
            event="remove_profile"
            armed={ArmGesture.armed?(@armed_gesture, "remove_profile", profile.id)}
            armed_label="Click again to remove"
            phx-value-id={profile.id}
            disabled={length(@profiles) == 1}
          >
            Remove profile
          </.armed_button>
        </:action>
        <form
          id={"profile-card-form-#{profile.id}"}
          phx-change="validate_profile_card"
          phx-submit="save_profile_picture"
          class="space-y-3"
        >
          <input type="hidden" name="profile_id" value={profile.id} />
          <div class="flex flex-wrap gap-x-8">
            <.settings_field
              label="Picture"
              description="Shown in the circle. One JPEG, PNG or WebP; drag the square to choose what shows."
              layout={:stacked}
              class="w-72 shrink-0"
            >
              <%= if @picture_editing == profile.id do %>
                <PictureField.picture_field
                  id={"profile-picture-#{profile.id}"}
                  upload={@uploads.profile_picture}
                  aspect={{1, 1}}
                  removable?={profile.picture_at != nil && @picture_removed != profile.id}
                  remove_event="remove_profile_picture"
                  cancel_event="cancel_profile_picture"
                  {IdentityTile.hue_style(profile.hue)}
                >
                  <:current>
                    <IdentityTile.identity_tile
                      name={profile.name}
                      picture_url={shown_picture(profile, @picture_removed)}
                      hue={profile.hue}
                      own?
                      size={48}
                    />
                  </:current>
                  <:preview>
                    <IdentityTile.crop_previews />
                  </:preview>
                </PictureField.picture_field>
                <div class="flex gap-2 pt-2">
                  <.button type="submit" variant="secondary" size="sm" data-nav-item tabindex="0">
                    Save picture
                  </.button>
                  <.button
                    type="button"
                    variant="dismiss"
                    size="sm"
                    phx-click="stop_editing_picture"
                    data-nav-item
                    tabindex="0"
                  >
                    Cancel
                  </.button>
                </div>
              <% else %>
                <div class="flex items-center gap-3">
                  <IdentityTile.identity_tile
                    name={profile.name}
                    picture_url={Profiles.picture_url(profile)}
                    hue={profile.hue}
                    own?
                    size={48}
                  />
                  <.button
                    id={"edit-profile-picture-#{profile.id}"}
                    type="button"
                    variant="neutral"
                    size="sm"
                    phx-click="edit_profile_picture"
                    phx-value-id={profile.id}
                    data-nav-item
                    tabindex="0"
                  >
                    {if profile.picture_at, do: "Change picture", else: "Add picture"}
                  </.button>
                </div>
              <% end %>
            </.settings_field>
            <div class="min-w-0 grow basis-64">
              <.settings_field label="Name" layout={:stacked}>
                <%!-- Not `settings_text_row`: its payload carries no profile id. --%>
                <.settings_input
                  id={"profile-name-#{profile.id}"}
                  name="name"
                  value={profile.name}
                  maxlength={DisplayName.max_length()}
                  autocomplete="off"
                  phx-blur="rename_profile"
                  phx-keydown="rename_profile"
                  phx-key="Enter"
                  phx-value-id={profile.id}
                  phx-debounce="blur"
                  class="max-w-64"
                />
              </.settings_field>
              <.settings_field label="Colour" description="The circle's colour." layout={:stacked}>
                <HueSwatches.hue_swatches
                  id={"profile-hues-#{profile.id}"}
                  selected={profile.hue}
                  event="set_profile_hue"
                  values={%{"id" => profile.id}}
                  aria-label="Colour"
                />
              </.settings_field>
            </div>
          </div>
        </form>
      </.settings_card>

      <.settings_card
        :if={length(@profiles) < Profiles.max_profiles()}
        id="add-profile"
        title="Add profile"
        description="Another person who watches here. They pick themselves on the Who's watching? screen."
      >
        <form
          id="settings-add-profile-form"
          phx-submit="add_profile"
          class="flex items-center gap-2"
        >
          <.settings_input
            name="name"
            placeholder="Name"
            maxlength={DisplayName.max_length()}
            autocomplete="off"
            class="min-w-0 flex-1"
          />
          <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">
            Add profile
          </.button>
        </form>
      </.settings_card>
    </div>
    """
  end

  # The tile shows the stored picture, or the letter once Remove is pending.
  defp shown_picture(profile, removed_id) do
    if removed_id != profile.id, do: Profiles.picture_url(profile)
  end
end
