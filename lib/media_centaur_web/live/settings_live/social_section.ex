defmodule MediaCentaurWeb.SettingsLive.SocialSection do
  @moduledoc """
  The Social section of the Settings page — this install's identity (npub
  with a copy control, the secret key behind a disclosure with reveal and
  copy, and the two-click import that replaces the identity) and the
  relays it publishes to and reads from (live connection state, add by
  URL, remove). `SettingsLive` delegates to `render/1` and hosts the
  handlers: `reveal_nsec`, `hide_nsec`, `import_nsec`, `add_relay`,
  `remove_relay`. The friend roster stays on the Discovery page's Social
  tab.

  The import textarea renders `import_draft`, so the arming click keeps
  what was pasted and a finished import clears it.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Social.Connections
  alias MediaCentaurWeb.RelayStatusRow

  import MediaCentaurWeb.SettingsLive.Components

  attr :npub, :string, required: true
  attr :nsec_revealed, :string, default: nil, doc: "the nsec while revealed; nil hides it"
  attr :import_armed?, :boolean, required: true
  attr :import_draft, :string, default: "", doc: "the pasted nsec while the replace is armed"
  attr :relays, :list, required: true, doc: "`Social.Relay.t()` in URL order"

  attr :status, :map,
    required: true,
    doc: "`Social.Connections.status/0` — `%{url => %{state: atom, last_error: String.t() | nil}}`"

  def render(assigns) do
    ~H"""
    <div id="settings-social" class="space-y-4">
      <section class="p-5 rounded-lg glass-surface space-y-5">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            Social <.status_dot configured={any_connected?(@status)} />
          </h2>
          <p class="text-sm text-base-content/55 mt-0.5">
            Your identity and the relays your recommendations travel over. Friends are managed on the Discovery page.
          </p>
        </div>

        <div class="space-y-4">
          <.settings_card_header title="Your identity" />
          <p class="text-xs text-base-content/55 max-w-[60ch]">
            Friends add you by this key. Your recommendations are visible to anyone who can read the relays you configure.
          </p>

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

          <details class="release-notes-disclosure">
            <summary class="cursor-pointer select-none text-xs text-base-content/50 inline-flex items-center gap-1.5">
              <.icon name="hero-chevron-right-mini" class="size-4 disclosure-caret" />
              <span>Secret key</span>
            </summary>
            <div class="mt-3 ml-5 space-y-4 border-l border-base-content/10 pl-4 text-sm">
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
            </div>
          </details>
        </div>

        <div class="pt-5 border-t border-base-content/10 space-y-4">
          <.settings_card_header title="Relays" />
          <p class="text-xs text-base-content/55 max-w-[60ch]">
            The servers your recommendations are published to and read from. Your group's own relay first; public relays are more entries.
          </p>

          <ul :if={@relays != []} class="space-y-2">
            <li
              :for={relay <- @relays}
              id={relay_dom_id(relay.url)}
              class="flex items-center gap-3 rounded-md bg-base-content/5 px-3 py-2"
            >
              <code class="min-w-0 flex-1 truncate text-xs">{relay.url}</code>
              <span class="shrink-0 text-xs text-base-content/60">
                {RelayStatusRow.state_label(@status[relay.url])}
              </span>
              <span
                :if={last_error(@status[relay.url])}
                class="min-w-0 max-w-48 truncate text-xs text-base-content/55"
                title={last_error(@status[relay.url])}
              >
                {last_error(@status[relay.url])}
              </span>
              <.button
                variant="dismiss"
                size="xs"
                class="shrink-0"
                phx-click="remove_relay"
                phx-value-url={relay.url}
                data-nav-item
                tabindex="0"
              >
                Remove
              </.button>
            </li>
          </ul>

          <form id="add-relay-form" phx-submit="add_relay" class="flex items-center gap-2">
            <input
              type="text"
              name="url"
              placeholder="wss://relay.example"
              class="input input-bordered min-w-0 flex-1 font-mono text-sm"
              autocomplete="off"
              data-nav-item
              tabindex="0"
            />
            <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">
              Add relay
            </.button>
          </form>
        </div>
      </section>
    </div>
    """
  end

  @doc "A DOM id for a relay URL."
  @spec relay_dom_id(String.t()) :: String.t()
  def relay_dom_id(url) do
    "relay-" <> (url |> String.replace(~r/[^a-z0-9]+/i, "-") |> String.trim("-") |> String.downcase())
  end

  @doc "Whether at least one relay is connected — the section's status dot."
  @spec any_connected?(map()) :: boolean()
  def any_connected?(status),
    do: Enum.any?(status, fn {_url, entry} -> Connections.connected?(entry) end)

  defp last_error(%{last_error: error}) when is_binary(error), do: error
  defp last_error(_absent), do: nil
end
