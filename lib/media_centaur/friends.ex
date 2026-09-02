defmodule MediaCentaur.Friends do
  use Boundary,
    deps: [MediaCentaur.Nostr],
    exports: [
      Connections,
      Events,
      Events.IdentityChanged,
      Events.RelayAdded,
      Events.RelayRemoved,
      Identity,
      Relay
    ]

  @moduledoc """
  Bounded context for the friend network's configuration: this install's
  identity (`Friends.Identity`), the relay list (`Friends.Relay`) and the
  live connections keyed by it (`Friends.Connections`); the friend roster
  joins them in a later layer.

  Broadcasts typed events on `friends:updates` (subscribe through
  `subscribe/0`) and re-broadcasts every relay connection's messages on
  `friends:connections` (`subscribe_connections/0`).
  """

  import Ecto.Query

  alias MediaCentaur.Friends.Events
  alias MediaCentaur.Friends.Relay
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to friends events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.friends_updates())

  @doc "Subscribe the caller to relay connection messages."
  @spec subscribe_connections() :: :ok | {:error, term()}
  def subscribe_connections, do: Topics.subscribe(Topics.friends_connections())

  @doc "Adds a relay URL (idempotent on the normalized URL)."
  @spec add_relay(String.t()) :: {:ok, Relay.t()} | {:error, Ecto.Changeset.t()}
  def add_relay(url) when is_binary(url) do
    normalized = Relay.normalize(url)

    case Repo.get_by(Relay, url: normalized) do
      %Relay{} = existing -> {:ok, existing}
      nil -> insert_relay(url, normalized)
    end
  end

  @doc "Removes a relay by URL. Absent is a no-op — and broadcasts nothing."
  @spec remove_relay(String.t()) :: :ok
  def remove_relay(url) when is_binary(url) do
    case Repo.get_by(Relay, url: Relay.normalize(url)) do
      nil ->
        :ok

      relay ->
        Repo.delete!(relay)
        Events.broadcast(%Events.RelayRemoved{url: relay.url})
        :ok
    end
  end

  @doc "Every configured relay, in URL order."
  @spec list_relays() :: [Relay.t()]
  def list_relays, do: Repo.all(from(relay in Relay, order_by: relay.url))

  defp insert_relay(url, normalized) do
    case Repo.insert(Relay.create_changeset(%{url: url})) do
      {:ok, relay} ->
        Events.broadcast(%Events.RelayAdded{url: relay.url})
        {:ok, relay}

      {:error, changeset} ->
        # A concurrent insert of the same URL is the idempotent case, not a failure.
        if unique_violation?(changeset),
          do: {:ok, Repo.get_by!(Relay, url: normalized)},
          else: {:error, changeset}
    end
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, meta}} -> meta[:constraint] == :unique end)
  end
end
