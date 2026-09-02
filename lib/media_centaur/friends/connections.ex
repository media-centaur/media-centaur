defmodule MediaCentaur.Friends.Connections do
  @moduledoc """
  One `Nostr.Connection` per configured relay, kept in step with the
  `relays` table: a Registry (keyed by URL, so a connection can be
  looked up by the address the user typed), a DynamicSupervisor, and an
  owner process (`Connections.Owner`) that reconciles on boot and on
  `RelayAdded` / `RelayRemoved` / `IdentityChanged`, receives every
  connection's messages, and re-broadcasts them on `friends:connections`.

  Under `:test` the owner is not started (`:start_relay_connections` is
  false); tests start it by hand against `Nostr.FakeRelay`.
  """

  use Supervisor

  alias MediaCentaur.Friends.Connections.Owner
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Filter

  @type entry :: %{state: atom(), last_error: String.t() | nil}

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    owner = if Application.get_env(:media_centaur, :start_relay_connections, true), do: [Owner], else: []

    children =
      [
        {Registry, keys: :unique, name: __MODULE__.Registry},
        {DynamicSupervisor, name: __MODULE__.DynamicSupervisor, strategy: :one_for_one}
      ] ++ owner

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 5, max_seconds: 60)
  end

  @doc "`%{url => %{state: Nostr.Connection.status(), last_error: String.t() | nil}}`; empty when no owner runs."
  @spec status() :: %{optional(String.t()) => entry()}
  def status, do: Owner.status()

  @doc "Publishes a signed event to every connected relay."
  @spec publish(Event.t()) :: :ok
  def publish(event), do: Owner.publish(event)

  @doc "Publishes to one relay; a no-op unless that relay is connected."
  @spec publish(String.t(), Event.t()) :: :ok
  def publish(url, event), do: Owner.publish(url, event)

  @doc "Subscribes every connection with the same filters under `sub_id` (re-applied to connections started later)."
  @spec subscribe_all(String.t(), [Filter.t()]) :: :ok
  def subscribe_all(sub_id, filters), do: Owner.subscribe_all(sub_id, filters)

  @doc "Subscribes one relay under `sub_id` (per-relay; re-applied if that connection restarts)."
  @spec subscribe(String.t(), String.t(), [Filter.t()]) :: :ok
  def subscribe(url, sub_id, filters), do: Owner.subscribe(url, sub_id, filters)

  @doc "The `:via` name of the connection for `url`."
  @spec via(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via(url), do: {:via, Registry, {__MODULE__.Registry, url}}

  @doc "A status entry for a relay nothing has been heard from yet."
  @spec blank_entry() :: entry()
  def blank_entry, do: %{state: :connecting, last_error: nil}

  @doc """
  Folds one `Nostr.Connection` owner message into a status entry. Shared
  by the owner (which keeps the authoritative map) and `DiscoveryLive`
  (which folds the same messages off `friends:connections`), so the two
  can never disagree about what a message means.
  """
  @spec apply_message(entry(), term()) :: entry()
  def apply_message(entry, :connected), do: %{entry | state: :connected, last_error: nil}

  def apply_message(entry, {:disconnected, reason}),
    do: %{entry | state: :disconnected, last_error: format_reason(reason)}

  def apply_message(entry, {:auth, :ok}), do: %{entry | state: :connected, last_error: nil}

  def apply_message(entry, {:auth, {:failed, reason}}),
    do: %{entry | state: :auth_failed, last_error: format_reason(reason)}

  def apply_message(entry, {:ok, _id, false, reason}), do: %{entry | last_error: format_reason(reason)}

  def apply_message(entry, {:closed, _sub_id, reason}), do: %{entry | last_error: format_reason(reason)}

  # A `NOTICE` is a relay talking about itself ("restarting for maintenance"),
  # not a verdict on anything we asked for, so it never becomes `last_error`.
  def apply_message(entry, {:notice, _text}), do: entry
  def apply_message(entry, _other), do: entry

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
