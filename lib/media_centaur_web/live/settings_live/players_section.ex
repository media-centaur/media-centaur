defmodule MediaCentaurWeb.SettingsLive.PlayersSection do
  @moduledoc """
  The Players section of the Settings page: one card per paired player —
  its name, edited in place; what device it is, whether it is connected
  or when and from where it was last seen (`MediaCentaurWeb.PlayerWords`);
  when it paired; Remove as an arm gesture in the card's action slot —
  and the Pair card, which
  starts pairing and then shows the open code beside the addresses a
  device can reach this install at, or says why none can. `SettingsLive`
  delegates to `render/1` and hosts the handlers: `rename_player`,
  `start_pairing`, `cancel_pairing`, `remove_player`.

  `reach/2` is the pure judgement of how a device reaches the install,
  from the endpoint's bound address and port and the host's LAN
  addresses (`Platform.LanAddresses`).
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Format
  alias MediaCentaur.Players.Pairing.Code
  alias MediaCentaur.Settings.Config.BindAddress
  alias MediaCentaurWeb.Live.ArmGesture
  alias MediaCentaurWeb.PlayerWords

  @typedoc "How a device reaches the install: not at all while bound to loopback, or at these URLs."
  @type reach :: :loopback | {:addresses, [String.t()]}

  @doc """
  From the endpoint's `http` config (`ip`, `port`) and the host's LAN
  addresses: `:loopback` when the install listens on the host alone;
  otherwise the URLs a device can use — every LAN address when bound to
  every interface, or the one address bound.
  """
  @spec reach(keyword(), [:inet.ip_address()]) :: reach()
  def reach(http, lan_addresses) do
    ip = Keyword.fetch!(http, :ip)
    port = Keyword.fetch!(http, :port)

    cond do
      BindAddress.loopback?(ip) -> :loopback
      any_interface?(ip) -> {:addresses, Enum.map(lan_addresses, &reach_url(&1, port))}
      true -> {:addresses, [reach_url(ip, port)]}
    end
  end

  defp any_interface?({0, 0, 0, 0}), do: true
  defp any_interface?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp any_interface?(_ip), do: false

  defp reach_url(ip, port), do: "http://#{:inet.ntoa(ip)}:#{port}"

  attr :players, :list, required: true, doc: "every `Players.Player`, oldest first"
  attr :connected, :any, required: true, doc: "the ids of the players connected now, a `MapSet`"
  attr :pairing, :any, required: true, doc: "the open `Players.Pairing.Code`, or nil"
  attr :reach, :any, required: true, doc: "`reach/2`'s answer"
  attr :armed_gesture, :any, required: true, doc: "the page's `ArmGesture` slot"

  def render(assigns) do
    ~H"""
    <div id="settings-players" class="space-y-4">
      <.settings_card :for={player <- @players} id={"player-card-#{player.id}"} title={player.name}>
        <:action>
          <.armed_button
            id={"remove-player-#{player.id}"}
            event="remove_player"
            armed={ArmGesture.armed?(@armed_gesture, "remove_player", player.id)}
            armed_label="Press again to remove"
            phx-value-id={player.id}
          >
            Remove player
          </.armed_button>
        </:action>
        <div id={"player-facts-#{player.id}"} class="px-3.5 space-y-1 text-base-content/70">
          <div
            :if={line = PlayerWords.device_line(player)}
            class="flex items-center gap-2 text-base-content/80"
          >
            <.icon name={PlayerWords.icon(player)} class="size-4 shrink-0 text-base-content/55" />
            <span class="truncate">{line}</span>
          </div>
          <div>
            {PlayerWords.seen_line(
              player,
              MapSet.member?(@connected, player.id),
              DateTime.utc_now()
            )}
          </div>
          <div>Paired {Format.relative_ago(player.inserted_at)}</div>
        </div>
        <.settings_text_row
          id={"player-name-#{player.id}"}
          label="Name"
          description="What this player is called here and on Status."
          name="name"
          value={player.name}
          event="rename_player"
          event_value={%{"id" => player.id}}
          maxlength={DisplayName.max_length()}
          autocomplete="off"
        />
      </.settings_card>

      <.settings_card
        id="pair-player"
        title="Pair a player"
        description="A TV or other device on your network. Open Media Centaur on it and enter the address and the code shown here."
      >
        <p class="text-base-content/70">
          On an Android TV, install the
          <a
            href="https://github.com/media-centaur/media-centaur-android/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
            class="link link-primary"
            data-nav-item
            tabindex="0"
          >Media Centaur TV app</a>
          first; it asks for this computer's address, then shows the pairing page.
        </p>
        <div :if={@pairing} class="space-y-3">
          <div class="flex flex-wrap items-center gap-x-10 gap-y-3">
            <span id="pairing-code" class="font-mono text-4xl tracking-[0.3em] text-base-content">
              {@pairing.code}
            </span>
            <div class="space-y-0.5 font-mono text-base-content/80">
              <div :for={address <- addresses(@reach)}>{address}</div>
              <div :if={addresses(@reach) == []} class="font-sans text-base-content/70">
                No network address found on this computer.
              </div>
            </div>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-base-content/70">The code works for {Code.lifetime_minutes()} minutes.</span>
            <.button
              id="cancel-pairing"
              variant="dismiss"
              size="sm"
              phx-click="cancel_pairing"
              data-nav-item
              tabindex="0"
            >
              Cancel
            </.button>
          </div>
        </div>
        <.button
          :if={is_nil(@pairing)}
          id="start-pairing"
          variant="neutral"
          size="sm"
          phx-click="start_pairing"
          data-nav-item
          tabindex="0"
        >
          Start pairing
        </.button>
        <p :if={@reach == :loopback} class="text-warning">
          Other devices can't reach this install: it listens on 127.0.0.1 only. Set
          <code class="font-mono">bind = "0.0.0.0"</code>
          in the config file and restart the service.
        </p>
      </.settings_card>
    </div>
    """
  end

  defp addresses({:addresses, urls}), do: urls
  defp addresses(:loopback), do: []
end
