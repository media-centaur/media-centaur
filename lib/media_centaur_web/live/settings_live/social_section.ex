defmodule MediaCentaurWeb.SettingsLive.SocialSection do
  @moduledoc """
  The Social section of the Settings page (UIDR-041): three cards. Your
  identity — the npub with a copy control, and behind a disclosure the
  secret key with reveal and copy plus the two-click import that replaces
  the identity. Relays — one connection row per relay (its live state
  from `Social.Connections`, the last error on the detail line, Remove)
  and the inline add-by-URL. Sharing — the toggles that decide which of
  the user's acts become activities for friends (watched, listed;
  reviewing always is). `SettingsLive` delegates to `render/1` and hosts
  the handlers: `reveal_nsec`, `hide_nsec`, `import_nsec`, `add_relay`,
  `remove_relay`, `toggle_share_watched`, `toggle_share_watchlist`. The
  friend roster stays on the Discovery page's Friends tab.

  The import textarea renders `import_draft`, so the arming click keeps
  what was pasted and a finished import clears it.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.Components.Settings.ConnectionRow

  alias MediaCentaurWeb.RelayStatusRow

  attr :npub, :string, required: true
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
      <.settings_card
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

  # The relay row's dot (UIDR-041 §1): synced and connected are the healthy
  # states, connecting is a verify in flight, everything else is a failure.
  defp relay_state(%{state: state}) when state in [:connected, :synced], do: :ok
  defp relay_state(%{state: :connecting}), do: :pending
  defp relay_state(_absent_or_failed), do: :error

  defp last_error(%{last_error: error}) when is_binary(error), do: error
  defp last_error(_absent), do: nil
end
