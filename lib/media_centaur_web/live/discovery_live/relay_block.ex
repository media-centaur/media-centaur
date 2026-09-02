defmodule MediaCentaurWeb.DiscoveryLive.RelayBlock do
  @moduledoc """
  The Social tab's relay block: the configured relays with their live
  connection state, an add-by-URL form, and a per-row remove. Iteration-
  phase component (lives with the LiveView, no story yet — spec decision
  11). Events bubble to `DiscoveryLive`: `add_relay`, `remove_relay`.
  """

  use MediaCentaurWeb, :html

  attr :relays, :list, required: true, doc: "`Social.Relay.t()` in URL order"

  attr :status, :map,
    required: true,
    doc: "`Social.Connections.status/0` — `%{url => %{state: atom, last_error: String.t() | nil}}`"

  def relay_block(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-5 space-y-4" data-component="relay-block">
      <div class="space-y-1">
        <h2 class="text-sm font-semibold">Relays</h2>
        <p class="text-xs text-base-content/50">
          The servers your recommendations are published to and read from. Your group's own relay first; public relays are more entries.
        </p>
      </div>

      <ul :if={@relays != []} class="space-y-2">
        <li
          :for={relay <- @relays}
          id={dom_id(relay.url)}
          class="flex items-center gap-3 rounded-md bg-base-content/5 px-3 py-2"
        >
          <code class="min-w-0 flex-1 truncate text-xs">{relay.url}</code>
          <span class="shrink-0 text-xs text-base-content/60">{state_label(@status[relay.url])}</span>
          <span
            :if={last_error(@status[relay.url])}
            class="min-w-0 max-w-48 truncate text-xs text-base-content/40"
          >
            {last_error(@status[relay.url])}
          </span>
          <.button
            variant="dismiss"
            size="xs"
            class="shrink-0"
            phx-click="remove_relay"
            phx-value-url={relay.url}
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
          class="library-filter min-w-0 flex-1"
          autocomplete="off"
        />
        <.button type="submit" variant="neutral" size="sm">Add relay</.button>
      </form>
    </section>
    """
  end

  @doc "A DOM id for a relay URL."
  @spec dom_id(String.t()) :: String.t()
  def dom_id(url) do
    "relay-" <> (url |> String.replace(~r/[^a-z0-9]+/i, "-") |> String.trim("-") |> String.downcase())
  end

  defp state_label(%{state: :connected}), do: "Connected"
  defp state_label(%{state: :connecting}), do: "Connecting"
  defp state_label(%{state: :auth_failed}), do: "Rejected"
  defp state_label(_absent_or_disconnected), do: "Not connected"

  defp last_error(%{last_error: error}) when is_binary(error), do: error
  defp last_error(_absent), do: nil
end
