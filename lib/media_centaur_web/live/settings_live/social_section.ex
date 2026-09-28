defmodule MediaCentaurWeb.SettingsLive.SocialSection do
  @moduledoc """
  The Social section of the Settings page (UIDR-041; UIDR-047 rule 3):
  four cards. Your profile — the name friends see, the picture beside it,
  the colour the circle takes (`HueSwatches`, starting on a palette hue
  at random), one form whose save mints the identity when none exists
  (`Social.save_profile/3`); it is the only card before an identity
  exists, so opening the section mints nothing. The picture is a
  LiveView upload: the identity tile shows the stored avatar (or the
  letter while a Remove is pending), the file input takes one JPEG, PNG
  or WebP, and the save turns it into the 256×256 WebP master or, after
  Remove, clears it; Remove steps aside while a file is chosen, since
  the chosen file is what the save publishes. While a file is chosen the
  Picture field carries the crop stage: the entry's `live_img_preview`
  under the `AvatarCrop` hook (croppr, vendored), which draws a square
  box over it and writes the box into three hidden fields — `crop_x`,
  `crop_y`, `crop_side`, in the picture's oriented pixels — that ride
  the form's submit; below it, two canvases wearing the own tile's
  avatar recipe in the pending hue show how the tile will look. Cancel
  removes the stage. The box is set by pointer until the input system
  learns one (arrows on a focused element are navigation today), as the
  hue slider's is. Your identity — the npub with a
  copy control, and behind a disclosure the secret key with reveal and
  copy plus the two-click import that replaces the identity. Relays —
  one connection row per relay (its live state from
  `Social.Connections`, the last error on the detail line, Remove) and
  the inline add-by-URL. Sharing — the toggles that decide which of the
  user's acts become activities for friends (watched, listed; reviewing
  always is). `SettingsLive` delegates to `render/1` and hosts the
  handlers: `validate_profile`, `set_profile_hue`, `remove_avatar`,
  `cancel_avatar`, `save_profile`, `reveal_nsec`, `hide_nsec`,
  `import_nsec`, `add_relay`, `remove_relay`, `toggle_share_watched`,
  `toggle_share_watchlist`. The friend roster stays on the Discovery
  page's Friends tab.

  The import textarea renders `import_draft`, so the arming click keeps
  what was pasted and a finished import clears it.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.Components.Settings.ConnectionRow

  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Discovery.HueSwatches
  alias MediaCentaurWeb.Components.Discovery.IdentityTile
  alias MediaCentaurWeb.RelayStatusRow

  attr :npub, :string,
    default: nil,
    doc: "nil before an identity exists; gates every card but the profile"

  attr :profile_name, :string, default: nil, doc: "the saved name; nil before a profile exists"

  attr :profile_hue, :integer,
    required: true,
    doc: "the form's pending hue (UIDR-048), previewed in the tile and published on Save"

  attr :name_cap, :integer, required: true, doc: "`Social.Profile.Translation.max_name_length/0`"
  attr :uploads, :map, required: true, doc: "the LiveView's `@uploads`; `.avatar` is the one upload"
  attr :own_person, Person, required: true, doc: "`Social.own_person/0`; the tile previews its avatar"

  attr :avatar_removed?, :boolean,
    required: true,
    doc: "Remove was clicked and the save is still to come"

  attr :nsec_revealed, :string, default: nil, doc: "the nsec while revealed; nil hides it"
  attr :import_armed?, :boolean, required: true
  attr :import_draft, :string, default: "", doc: "the pasted nsec while the replace is armed"
  attr :relays, :list, required: true, doc: "`Social.Relay.t()` in URL order"

  attr :status, :map,
    required: true,
    doc: "`Social.Connections.status/0` — `%{url => %{state: atom, last_error: String.t() | nil}}`"

  attr :share_watched?, :boolean, required: true, doc: "the `share_watched` preference"
  attr :share_watchlist?, :boolean, required: true, doc: "the `share_watchlist` preference"

  def render(assigns) do
    ~H"""
    <div id="settings-social" class="space-y-4">
      <.settings_card title="Your profile" description={profile_description(@npub)}>
        <form
          id="profile-form"
          phx-submit="save_profile"
          phx-change="validate_profile"
          class="space-y-3"
        >
          <div class="flex flex-wrap gap-x-8">
            <.settings_field
              label="Picture"
              description="Shown in your circle. One JPEG, PNG or WebP; drag the square to choose what shows."
              layout={:stacked}
              class="w-72 shrink-0"
            >
              <div class="flex items-center gap-3">
                <IdentityTile.identity_tile
                  person={shown_person(@own_person, @avatar_removed?, @profile_hue)}
                  size={48}
                />
                <.live_file_input upload={@uploads.avatar} class="sr-only" />
                <.button
                  id="choose-avatar"
                  type="button"
                  variant="neutral"
                  size="sm"
                  phx-click={JS.dispatch("click", to: "##{@uploads.avatar.ref}")}
                  data-nav-item
                  tabindex="0"
                >
                  Choose picture
                </.button>
                <.button
                  :if={@own_person.avatar_url && !@avatar_removed? && @uploads.avatar.entries == []}
                  id="remove-avatar"
                  type="button"
                  variant="dismiss"
                  size="xs"
                  phx-click="remove_avatar"
                  data-nav-item
                  tabindex="0"
                >
                  Remove
                </.button>
              </div>
              <p :for={err <- upload_errors(@uploads.avatar)} class="mt-2 text-xs text-error">
                {upload_error_words(err, @uploads.avatar)}
              </p>
              <%!-- The pending hue rides here, outside the hook's ignored
                    subtree, and reaches the previews' rings by inheritance
                    (`--hue` is a custom property), so a swatch pressed while
                    a picture is chosen recolours How it will look. --%>
              <div
                :for={entry <- @uploads.avatar.entries}
                class="mt-3 space-y-3"
                data-role="pending-picture"
                {IdentityTile.hue_style(@profile_hue)}
              >
                <div
                  id={"avatar-crop-#{entry.ref}"}
                  phx-hook="AvatarCrop"
                  phx-update="ignore"
                  class="avatar-crop"
                >
                  <div class="avatar-crop-stage">
                    <.live_img_preview entry={entry} data-role="source" alt="" />
                  </div>
                  <input type="hidden" name="crop_x" value="" />
                  <input type="hidden" name="crop_y" value="" />
                  <input type="hidden" name="crop_side" value="" />
                  <div class="mt-3 flex items-center gap-3">
                    <span
                      class="identity-tile identity-tile-own identity-tile-avatar relative grid size-12 shrink-0 place-items-center overflow-hidden rounded-full"
                      aria-hidden="true"
                    >
                      <canvas data-role="preview" width="48" height="48" class="size-full"></canvas>
                    </span>
                    <span
                      class="identity-tile identity-tile-own identity-tile-avatar relative grid size-10 shrink-0 place-items-center overflow-hidden rounded-full"
                      aria-hidden="true"
                    >
                      <canvas data-role="preview" width="40" height="40" class="size-full"></canvas>
                    </span>
                    <span class="text-xs text-base-content/60">How it will look</span>
                  </div>
                </div>
                <p class="flex items-center gap-2 text-xs text-base-content/60">
                  <span class="truncate">{entry.client_name}</span>
                  <span :for={err <- upload_errors(@uploads.avatar, entry)} class="text-error">
                    {upload_error_words(err, @uploads.avatar)}
                  </span>
                  <.button
                    type="button"
                    variant="dismiss"
                    size="xs"
                    phx-click="cancel_avatar"
                    phx-value-ref={entry.ref}
                    data-nav-item
                    tabindex="0"
                  >
                    Cancel
                  </.button>
                </p>
              </div>
            </.settings_field>
            <div class="min-w-0 grow basis-64">
              <.settings_field label="Name" layout={:stacked}>
                <.settings_input
                  id="profile-name"
                  name="name"
                  value={@profile_name}
                  maxlength={@name_cap}
                  autocomplete="off"
                  phx-debounce="blur"
                  class="max-w-64"
                />
              </.settings_field>
              <.settings_field label="Colour" description="Your circle's colour." layout={:stacked}>
                <HueSwatches.hue_swatches
                  id="profile-hues"
                  selected={@profile_hue}
                  event="set_profile_hue"
                  aria-label="Colour"
                />
              </.settings_field>
            </div>
          </div>
          <div class="flex justify-end">
            <.button type="submit" variant="secondary" size="sm" data-nav-item tabindex="0">
              {if @npub, do: "Save", else: "Create profile"}
            </.button>
          </div>
        </form>
      </.settings_card>

      <.settings_card
        :if={@npub}
        title="Your identity"
        description="Friends add you by this key. Your reviews are visible to anyone who can read the relays you configure."
      >
        <div class="flex items-center gap-3">
          <code
            id="identity-npub"
            class="min-w-0 flex-1 truncate rounded-md bg-base-content/5 px-3 py-2 text-xs"
          >
            {@npub}
          </code>
          <.button
            id="copy-npub"
            variant="dismiss"
            size="xs"
            class="shrink-0"
            phx-hook="CopyButton"
            data-copy-text={@npub}
            data-nav-item
            tabindex="0"
          >
            Copy
          </.button>
        </div>

        <.settings_disclosure label="Secret key">
          <p class="text-xs text-base-content/60 max-w-[60ch]">
            This key is your identity. Anyone who has it can publish as you. Keep it somewhere safe; it is the only way to move this identity to another machine.
          </p>

          <div :if={is_nil(@nsec_revealed)}>
            <.button
              id="reveal-nsec"
              variant="neutral"
              size="sm"
              phx-click="reveal_nsec"
              data-nav-item
              tabindex="0"
            >
              Show secret key
            </.button>
          </div>
          <div :if={@nsec_revealed} class="flex items-center gap-3">
            <code
              id="identity-nsec"
              class="min-w-0 flex-1 truncate rounded-md bg-base-content/5 px-3 py-2 text-xs"
            >
              {@nsec_revealed}
            </code>
            <.button
              id="copy-nsec"
              variant="dismiss"
              size="xs"
              class="shrink-0"
              phx-hook="CopyButton"
              data-copy-text={@nsec_revealed}
              data-nav-item
              tabindex="0"
            >
              Copy
            </.button>
            <.button
              id="hide-nsec"
              variant="dismiss"
              size="xs"
              class="shrink-0"
              phx-click="hide_nsec"
              data-nav-item
              tabindex="0"
            >
              Hide
            </.button>
          </div>

          <form id="import-nsec-form" phx-submit="import_nsec" class="space-y-2">
            <label for="import-nsec" class="block text-xs font-medium">
              Replace with another secret key
            </label>
            <textarea
              id="import-nsec"
              name="nsec"
              rows="2"
              placeholder="nsec1…"
              class="textarea textarea-bordered w-full font-mono text-xs"
              data-nav-item
              tabindex="0"
            >{@import_draft}</textarea>
            <.button
              id="import-nsec-submit"
              type="submit"
              variant={if @import_armed?, do: "danger", else: "neutral"}
              size="sm"
              data-nav-item
              tabindex="0"
            >
              {if @import_armed?, do: "Click again to replace", else: "Replace identity"}
            </.button>
          </form>
        </.settings_disclosure>
      </.settings_card>

      <.settings_card
        :if={@npub}
        title="Relays"
        description="The servers your activity is published to and read from. Your group's own relay first; public relays are more entries."
      >
        <ul :if={@relays != []}>
          <.connection_row
            :for={relay <- @relays}
            id={relay_dom_id(relay.url)}
            name={relay.url}
            monospace_name
            state={relay_state(@status[relay.url])}
            state_label={RelayStatusRow.state_label(@status[relay.url])}
            detail={last_error(@status[relay.url])}
          >
            <:actions>
              <.button
                variant="dismiss"
                size="xs"
                phx-click="remove_relay"
                phx-value-url={relay.url}
                data-nav-item
                tabindex="0"
              >
                Remove
              </.button>
            </:actions>
          </.connection_row>
        </ul>

        <form id="add-relay-form" phx-submit="add_relay" class="flex items-center gap-2 pt-1">
          <.settings_input
            name="url"
            placeholder="wss://relay.example"
            mono
            autocomplete="off"
            class="min-w-0 flex-1"
          />
          <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">
            Add relay
          </.button>
        </form>
      </.settings_card>

      <.settings_card
        :if={@npub}
        id="social-sharing"
        title="Sharing"
        description="Reviewing always shares. Each of these shares from the moment it is switched on; what was sent before stays until you delete it from the Feed."
      >
        <div class="space-y-1">
          <.settings_row
            label="Share what you watch"
            description="Friends see a movie or an episode when you finish it."
            checked={@share_watched?}
            event="toggle_share_watched"
          />
          <.settings_row
            label="Share your watchlist"
            description="A title you list is shared with your friends; one you drop is withdrawn."
            checked={@share_watchlist?}
            event="toggle_share_watchlist"
          />
        </div>
      </.settings_card>
    </div>
    """
  end

  @doc "A DOM id for a relay URL."
  @spec relay_dom_id(String.t()) :: String.t()
  def relay_dom_id(url) do
    "relay-" <> (url |> String.replace(~r/[^a-z0-9]+/i, "-") |> String.trim("-") |> String.downcase())
  end

  # Before an identity exists the save also mints it, and the identity
  # card that would explain the key is not on the page yet; the
  # description carries that once.
  defp profile_description(nil),
    do:
      "The name your friends see you under, and the picture beside it, if you like. Saving creates your identity, the key friends add you by."

  defp profile_description(_npub),
    do: "The name your friends see you under, and the picture beside it, if you like."

  # The tile shows the stored avatar, or the letter once Remove is
  # pending; a chosen file shows by name until the save. It draws in the
  # form's pending hue, so a swatch previews before Save.
  defp shown_person(%Person{} = person, removed?, hue) do
    person = %{person | published_hue: hue}
    if removed?, do: %{person | avatar_url: nil}, else: person
  end

  # `Phoenix.Component.upload_errors/1,2`: the whole-upload error and the
  # two an entry can carry under `allow_upload`'s accept and size caps.
  defp upload_error_words(:too_many_files, _upload), do: "One picture"

  defp upload_error_words(:too_large, %{max_file_size: bytes}),
    do: "Larger than #{div(bytes, 1_000_000)} MB"

  defp upload_error_words(:not_accepted, _upload), do: "Not a JPEG, PNG or WebP"

  # The relay row's dot (UIDR-041 §1): synced and connected are the healthy
  # states, connecting is a verify in flight, everything else is a failure.
  defp relay_state(%{state: state}) when state in [:connected, :synced], do: :ok
  defp relay_state(%{state: :connecting}), do: :pending
  defp relay_state(_absent_or_failed), do: :error

  defp last_error(%{last_error: error}) when is_binary(error), do: error
  defp last_error(_absent), do: nil
end
