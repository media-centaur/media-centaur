defmodule MediaCentaur.Recommendations.Sync do
  @moduledoc """
  Keeps recommendations in step with the relays. Consumes
  `friends:connections`:

    * `:connected` for a relay → subscribe `"feed"` (authors = friends ++
      self, kind 32160) and `"own:<url>"` (authors = [self]) on that
      relay; collect the event ids the relay sends on the own sub.
    * `{:eose, "own:<url>"}` → publish to that relay every stored own
      event it did not send. A per-relay diff, not a blanket re-publish:
      addressable events are few, and a relay that already has one does
      not need it again.
    * `{:event, _sub_id, event}` → `Recommendations.ingest/1` (verified,
      friend or self, newest wins).

  Consumes `friends:updates`: a roster change resubscribes `"feed"` on
  every relay with the new author list.

  On reconnect, `Connections.Owner` also re-applies the relay's
  previously-registered subscriptions (its own job, independent of this
  module), so `"feed"` and `"own:<url>"` each go out twice — this is
  harmless (relays de-duplicate identical subs, and `seen` resets on
  `:connected` here so the own-events diff still lands right) and left
  alone rather than adding a seam to suppress one of the two senders.

  Gated off under `:test` (`:start_recommendations_sync`); tests start it
  by hand against `Nostr.FakeRelay`, as with `Connections.Owner`.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Connections
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Recommendations
  alias MediaCentaur.Recommendations.Translation

  defstruct seen: %{}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Friends.subscribe_connections()
    Friends.subscribe()
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info({:relay_connection, url, :connected}, state) do
    Connections.subscribe(url, "feed", [feed_filter()])
    Connections.subscribe(url, own_sub(url), [own_filter()])
    {:noreply, %{state | seen: Map.put(state.seen, url, MapSet.new())}}
  end

  def handle_info({:relay_connection, url, {:event, sub_id, event}}, state) do
    state = if sub_id == own_sub(url), do: mark_seen(state, url, event.id), else: state

    case Recommendations.ingest(event) do
      {:ok, _rec} ->
        :ok

      :ignored ->
        :ok

      {:error, reason} ->
        Log.debug(:recommendations, "#{url}: dropped event #{event.id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info({:relay_connection, url, {:eose, sub_id}}, state) do
    if sub_id == own_sub(url), do: publish_missing(url, Map.get(state.seen, url, MapSet.new()))
    {:noreply, state}
  end

  def handle_info({:friend_added, _event}, state), do: resubscribe(state)
  def handle_info({:friend_removed, _event}, state), do: resubscribe(state)
  def handle_info(_other, state), do: {:noreply, state}

  defp resubscribe(state) do
    Connections.subscribe_all("feed", [feed_filter()])
    {:noreply, state}
  end

  defp mark_seen(state, url, event_id),
    do: %{state | seen: Map.update(state.seen, url, MapSet.new([event_id]), &MapSet.put(&1, event_id))}

  defp publish_missing(url, seen) do
    missing = Enum.reject(Recommendations.own_events(), &MapSet.member?(seen, &1.id))
    for event <- missing, do: Connections.publish(url, event)

    if missing != [],
      do: Log.info(:recommendations, "#{url}: published #{length(missing)} recommendation(s) it lacked")

    :ok
  end

  # Before an identity exists there is nothing to subscribe as — and no
  # connection either, since `Connections` starts none — but the nil
  # would still reach the wire as an author, so it is filtered out.
  defp feed_filter do
    authors = Enum.reject(Enum.uniq([Identity.pubkey() | Friends.friend_pubkeys()]), &is_nil/1)
    Filter.new(authors: authors, kinds: [Translation.kind()])
  end

  defp own_filter,
    do: Filter.new(authors: Enum.reject([Identity.pubkey()], &is_nil/1), kinds: [Translation.kind()])

  defp own_sub(url), do: "own:" <> url
end
