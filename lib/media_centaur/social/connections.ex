defmodule MediaCentaur.Social.Connections do
  @moduledoc """
  One `Nostr.Connection` per configured relay, kept in step with the
  `relays` table: a Registry (keyed by URL, so a connection can be
  looked up by the address the user typed), a DynamicSupervisor, and an
  owner process (`Connections.Owner`) that reconciles on boot and on
  `RelayAdded` / `RelayRemoved` / `IdentityChanged`, receives every
  connection's messages, and re-broadcasts them on `social:connections`.

  Under `:test` the owner is not started (`:start_relay_connections` is
  false); tests start it by hand against `Nostr.FakeRelay`.
  """

  use Supervisor

  alias MediaCentaur.Social.Connections.Owner
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Nostr.Reason

  @typedoc """
  One relay's status. `state` names how far the connection has got:

    * `:connecting` — nothing heard yet, or a socket mid-handshake
    * `:connected` — the socket is up (and authenticated, where the relay asks)
    * `:synced` — the relay has answered the feed subscription with `EOSE`,
      so it serves this identity's requests
    * `:auth_failed` — the relay rejected this identity: a NIP-42 refusal, or a
      `CLOSED` on the feed whose reason starts with `restricted:` (khatru
      cannot refuse an `AUTH` event, so that is the only signal a non-member gets)
    * `:disconnected` — lost, retrying at `retry_at`

  `last_error` is the newest plain-language complaint (`Nostr.Reason`);
  `since` the onset of the current state; `last_heard_at` the newest inbound
  frame of any kind, pongs included; `retry_at` the next attempt while
  disconnected, nil otherwise.
  """
  @type entry :: %{
          state: :connecting | :connected | :synced | :auth_failed | :disconnected,
          last_error: String.t() | nil,
          since: DateTime.t(),
          last_heard_at: DateTime.t() | nil,
          retry_at: DateTime.t() | nil
        }

  @feed_sub_id "feed"

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

  @doc """
  `%{url => %{state: Nostr.Connection.status(), last_error: String.t() |
  nil, since: DateTime.t()}}`; empty when no owner runs. `since` is when
  the entry entered its current state — what `Social.IncidentContext`
  measures its grace window from.
  """
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

  @doc "The subscription id of the friends feed — the one whose `EOSE` means synced."
  @spec feed_sub_id() :: String.t()
  def feed_sub_id, do: @feed_sub_id

  @doc "Whether a state counts as connected for the connected-of-configured count."
  @spec connected?(entry()) :: boolean()
  def connected?(%{state: state}), do: state in [:connected, :synced]

  @doc "A status entry for a relay nothing has been heard from yet."
  @spec blank_entry() :: entry()
  def blank_entry,
    do: %{
      state: :connecting,
      last_error: nil,
      since: DateTime.utc_now(),
      last_heard_at: nil,
      retry_at: nil
    }

  @doc """
  Folds one `Nostr.Connection` owner message into a status entry. Shared
  by the owner (which keeps the authoritative map) and `DiscoveryLive`
  (which folds the same messages off `social:connections`), so the two
  can never disagree about what a message means.
  """
  @spec apply_message(entry(), term()) :: entry()
  def apply_message(entry, {:disconnected, reason, retry_in_ms}) do
    %{
      put_state(entry, :disconnected, Reason.describe(reason))
      | retry_at: DateTime.add(DateTime.utc_now(), retry_in_ms, :millisecond)
    }
  end

  def apply_message(entry, message), do: entry |> heard() |> fold(message)

  # A reconnect starts over at :connected: whether the relay still serves
  # the feed is proven again by its next EOSE.
  defp fold(entry, :connected), do: put_state(entry, :connected, nil)
  defp fold(entry, {:auth, :ok}), do: put_state(entry, :connected, nil)

  defp fold(entry, {:auth, {:failed, reason}}),
    do: put_state(entry, :auth_failed, Reason.describe(reason))

  defp fold(entry, {:eose, @feed_sub_id}), do: put_state(entry, :synced, nil)

  defp fold(entry, {:closed, @feed_sub_id, "restricted:" <> _rest = reason}),
    do: put_state(entry, :auth_failed, reason)

  # The feed going away is a demotion, not a loss: the socket is still up.
  defp fold(%{state: :synced} = entry, {:closed, @feed_sub_id, reason}),
    do: put_state(entry, :connected, reason)

  defp fold(entry, {:closed, _sub_id, reason}), do: %{entry | last_error: reason}
  defp fold(entry, {:ok, _id, false, reason}), do: %{entry | last_error: reason}

  # A `NOTICE` is a relay talking about itself ("restarting for maintenance"),
  # not a verdict on anything we asked for, so it never becomes `last_error`.
  defp fold(entry, {:notice, _text}), do: entry
  defp fold(entry, _other), do: entry

  defp heard(entry), do: %{entry | last_heard_at: DateTime.utc_now(), retry_at: nil}

  # `since` is the onset of the *current* state, so re-affirming the state
  # an entry is already in leaves it alone — a relay that keeps saying
  # "connected" has not started being connected again.
  defp put_state(%{state: state} = entry, state, last_error), do: %{entry | last_error: last_error}

  defp put_state(entry, state, last_error),
    do: %{entry | state: state, last_error: last_error, since: DateTime.utc_now()}
end
