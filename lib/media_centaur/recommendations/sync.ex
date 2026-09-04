defmodule MediaCentaur.Recommendations.Sync do
  @moduledoc """
  Keeps recommendations in step with the relays — the app's side of the
  *Reading and sync* section of `docs/social-protocol.md`. Consumes
  `social:connections`:

    * `:connected` for a relay → subscribe `"feed"` (authors = friends ++
      self, kinds 32160 and 5, `limit` = the page size) and `"own:<url>"`
      (authors = [self], both kinds) on that relay; collect the event ids
      the relay sends on the own sub.
    * `{:event, "feed", event}` → `Recommendations.ingest/1` (verified,
      friend or self, newest wins; a deletion tombstones).
    * `{:eose, "feed"}` → if the page came back full, ask for the next
      one (`until` = one second before the oldest seen); after a short
      page that followed a full one, re-issue `"feed"` live (no `until`)
      so new events keep arriving.
    * `{:eose, "own:<url>"}` → publish to that relay every stored own
      event it did not send — recommendations of live rows, deletions of
      withdrawn ones. A per-relay diff, not a blanket re-publish.
    * `{:ok, id, false, reason}` → log the refusal by what was refused
      (`Recommendations.own_event_kind/1`): a relay refusing a deletion
      is the one that has not been upgraded to carry the contract. The
      connection keeps the reason as the relay row's last error.

  Consumes `social:updates`: a roster change re-issues `"feed"` on every
  connected relay with the new author list.

  Every connect reads the relay from the start: no `since` cursor. A relay
  holds one record per signer per title (contract Deletion rule 3), so a
  friend group's whole history is a page, and a cursor keyed on
  `created_at` would skip an event published late with an older stamp —
  a withdrawal made offline. Re-reading is idempotent: ingest ignores
  what is not newer than the row.

  On reconnect, `Connections.Owner` also re-applies the relay's
  previously-registered subscriptions (its own job, independent of this
  module), so `"feed"` and `"own:<url>"` each go out twice — this is
  harmless (relays de-duplicate identical subs, and `seen` resets on
  `:connected` here so the own-events diff still lands right) and left
  alone rather than adding a seam to suppress one of the two senders.

  Paging steps `until` back by one second, so more than `page_limit`
  events sharing one second lose the excess; the alternative is an
  endless page. Gated off under `:test` (`:start_recommendations_sync`);
  tests start it by hand against `Nostr.FakeRelay`, with `page_limit:`
  lowered to exercise paging.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Recommendations
  alias MediaCentaur.Recommendations.Translation

  @default_page_limit 500
  @feed Connections.feed_sub_id()

  defmodule Page do
    @moduledoc false
    defstruct count: 0, oldest: nil, paging?: false
  end

  defstruct seen: %{}, pages: %{}, page_limit: @default_page_limit

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    Social.subscribe_connections()
    Social.subscribe()
    {:ok, %__MODULE__{page_limit: Keyword.get(opts, :page_limit, @default_page_limit)}}
  end

  @impl true
  def handle_info({:relay_connection, url, :connected}, state) do
    Connections.subscribe(url, own_sub(url), [own_filter()])

    state =
      state
      |> put_in([Access.key(:seen), url], MapSet.new())
      |> subscribe_feed(url, nil, false)

    {:noreply, state}
  end

  def handle_info({:relay_connection, url, {:event, sub_id, event}}, state) do
    state = if sub_id == own_sub(url), do: mark_seen(state, url, event.id), else: state
    state = if sub_id == @feed, do: note_page_event(state, url, event), else: state

    case Recommendations.ingest(event) do
      {:ok, _rec} ->
        :ok

      :ignored ->
        :ok

      {:error, reason} ->
        Log.debug(:social, "#{url}: dropped event #{event.id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info({:relay_connection, url, {:eose, @feed}}, state) do
    {:noreply, next_page(state, url)}
  end

  def handle_info({:relay_connection, url, {:eose, sub_id}}, state) do
    if sub_id == own_sub(url), do: publish_missing(url, Map.get(state.seen, url, MapSet.new()))
    {:noreply, state}
  end

  def handle_info({:relay_connection, url, {:ok, event_id, false, reason}}, state) do
    Log.warning(
      :social,
      "#{url} rejected #{refused(Recommendations.own_event_kind(event_id))}: #{reason}"
    )

    {:noreply, state}
  end

  def handle_info({:friend_added, _event}, state), do: {:noreply, resubscribe(state)}
  def handle_info({:friend_removed, _event}, state), do: {:noreply, resubscribe(state)}
  def handle_info(_other, state), do: {:noreply, state}

  # --- feed paging ---------------------------------------------------------

  defp subscribe_feed(state, url, until, paging?) do
    Connections.subscribe(url, @feed, [feed_filter(until, state.page_limit)])
    put_in(state, [Access.key(:pages), url], %Page{paging?: paging?})
  end

  defp note_page_event(state, url, event) do
    update_in(state, [Access.key(:pages), url], fn
      nil ->
        %Page{count: 1, oldest: event.created_at}

      page ->
        %{page | count: page.count + 1, oldest: min(page.oldest || event.created_at, event.created_at)}
    end)
  end

  defp next_page(state, url) do
    case Map.get(state.pages, url) do
      %Page{count: count, oldest: oldest} when count >= state.page_limit and is_integer(oldest) ->
        subscribe_feed(state, url, oldest - 1, true)

      %Page{paging?: true} ->
        subscribe_feed(state, url, nil, false)

      _short_first_page_or_unknown ->
        state
    end
  end

  defp resubscribe(state) do
    Connections.status()
    |> Enum.filter(fn {_url, entry} -> Connections.connected?(entry) end)
    |> Enum.reduce(state, fn {url, _entry}, acc -> subscribe_feed(acc, url, nil, false) end)
  end

  # --- own events ------------------------------------------------------------

  defp refused(:recommendation), do: "a recommendation"
  defp refused(:deletion), do: "a deletion"
  defp refused(nil), do: "an event"

  defp mark_seen(state, url, event_id),
    do: %{state | seen: Map.update(state.seen, url, MapSet.new([event_id]), &MapSet.put(&1, event_id))}

  defp publish_missing(url, seen) do
    missing = Enum.reject(Recommendations.own_events(), &MapSet.member?(seen, &1.id))
    for event <- missing, do: Connections.publish(url, event)

    if missing != [],
      do: Log.info(:social, "#{url}: published #{length(missing)} event(s) it lacked")

    :ok
  end

  # --- filters ---------------------------------------------------------------

  # Before an identity exists there is nothing to subscribe as — and no
  # connection either, since `Connections` starts none — but the nil
  # would still reach the wire as an author, so it is filtered out.
  defp feed_filter(until, limit) do
    authors = Enum.reject(Enum.uniq([Identity.pubkey() | Social.friend_pubkeys()]), &is_nil/1)
    Filter.new(authors: authors, kinds: kinds(), until: until, limit: limit)
  end

  defp own_filter, do: Filter.new(authors: Enum.reject([Identity.pubkey()], &is_nil/1), kinds: kinds())

  defp kinds, do: [Translation.kind(), Translation.deletion_kind()]

  defp own_sub(url), do: "own:" <> url
end
