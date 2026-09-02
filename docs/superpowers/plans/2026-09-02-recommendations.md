# Recommendations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send and receive recommendations: the `Recommendations` context (records, the event translation, the relay sync), the Recommend modal from library detail pages and watchlist rows, and the Feed tab at `/discovery`.

**Architecture:** `MediaCentaur.Recommendations` (`use Boundary, deps: [Nostr, Friends, TMDB, TmdbArtwork]`) owns the `recommendations` table (one row per author + title, newest event wins), `Translation` (the anti-corruption layer between kind-32160 events and records), `Sync` (a GenServer on `friends:connections`: per-relay feed subscription, per-relay own-events diff after `EOSE`, ingest of verified events from friends), `recommend/2`, `ingest/1`, `list_feed/0`, `list_sent/0`, and a `TmdbArtworkHolds` provider. Discovery and Recommendations never depend on each other; `DiscoveryLive` joins them (feed rows get on-watchlist and in-library state from `Discovery.watchlisted_refs/0` and `Library.ExternalIds.tmdb_owners/1`). The Recommend modal is one shared function component rendered in each host's overlays slot, with a small `RecommendFlow` helper the hosts call from their event handlers (EntityModal's injected clauses for the detail hosts, DiscoveryLive's own for watchlist rows).

**Tech Stack:** Ecto/SQLite (`:map` embeds), `Nostr.Event`/`Filter`/`Connection` (layers 2, 4), `Friends` (layers 3–5), `TmdbArtwork.ensure/2`, LiveView, `Components.Modal`, `FakeRelay`.

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` — Architecture › `MediaCentaur.Recommendations`; Event shape; Runtime behavior; UI › Discovery page (Feed), Recommend modal. Layer 6. Layer 7 (watchlist provenance `:friend` + `recommendation_id`, Status section) follows; this layer's "Add to watchlist" adds a plain item.

**Decisions fixed by this plan:**
- Kind 32160, address tag `["d", "tmdb:<movie|tv_series>:<id>"]`, optional recipient tag `["p", pubkey]` never set. Content JSON `{"title": {tmdb_id, media_type, name, year, release_date, poster_path, backdrop_path, overview}, "note": string|null}`. `media_type` in the address and content uses the app's atoms as strings (`movie`, `tv_series`).
- **Decoration lives in the web layer.** `list_feed/0` returns rows decorated with the friend nickname only (Friends is a dep); `DiscoveryLive` adds `library_owner_id`, `on_watchlist?`, `poster_url`. This reads the spec's `list_feed/0` sentence as "the feed row carries…", the only Boundary-legal reading.
- Received events for a title trigger `TmdbArtwork.ensure/2` async (context-layer task, ADR-049), so a recommendation whose snapshot has no poster path (library-origin sends) still gets art; `Recommendations.TmdbArtworkHolds` holds it.
- The Recommend control on the detail page is gated by `show_discovery` (the preference that gates the Discovery entry — the whole feature is a preview), like nothing else on the modal. Watchlist rows are only reachable on the Discovery page, so no extra gate there.
- Sync per relay: on `:connected` subscribe `"feed"` (authors = friends ++ self, kinds [32160]) and `"own:" <> url` (authors = [self], kinds [32160]); collect event ids seen on the own sub; on its `EOSE`, publish every stored own event the relay did not send (`Connections.publish(url, event)`). On `FriendAdded`/`FriendRemoved`, `Connections.subscribe_all("feed", …)` with the new author list. Sync is gated off in `:test` (`:start_recommendations_sync`) and tests start it by hand, as with `Connections.Owner`.
- Feed time uses `Format.relative_ago/1` as it is ("3d ago").
- Copy (house voice): Feed empty state when there are no friends or relays: **"Recommendations from your friends land here. Add a relay and a friend on the Friends tab."**; when both exist but nothing has arrived: **"Nothing from your friends yet."** Feed row secondary line: `from <nickname> · <relative time>`, then the note if any (the note replaces the overview, the "from" line is a marker). Row actions: **Add to watchlist** / **On watchlist** (disabled state) / **In library** link. Recommend modal: heading **Recommend to your friends**; note placeholder **Why they should watch it (optional)**; relay line: **Connected to N of M relays** / **No relay configured — it will send when you add one**; buttons **Send** / **Cancel**; flash after send **Recommended to your friends** or, with no connected relay, **Saved — it will send when a relay connects**. Detail-page control tooltip **Recommend**. Watchlist row action **Recommend**.

**House rules:** test-first; zero warnings; `mix format`; credo customs (MC0003/MC0006/MC0011/MC0020/MC0024/MC0025/MC0027, event chokepoint, storybook MC0009 for `watchlist_row`'s new variation and any `components/**` file touched — `view_controls.ex` story must gain the Recommend state); no real titles ("Sample Movie", "Sample Show"); commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`; no push, no tag.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `priv/repo/migrations/20260902180000_add_recommendations.exs` | table |
| Create | `lib/media_centaur/recommendations.ex` | Boundary, `subscribe/0`, `recommend/2`, `ingest/1`, `list_feed/0`, `list_sent/0`, `own_events/0` |
| Create | `lib/media_centaur/recommendations/recommendation.ex` | schema |
| Create | `lib/media_centaur/recommendations/translation.ex` | event ↔ attrs |
| Create | `lib/media_centaur/recommendations/events.ex` | `Received`, `Sent` |
| Create | `lib/media_centaur/recommendations/sync.ex` | relay sync GenServer |
| Create | `lib/media_centaur/recommendations/tmdb_artwork_holds.ex` | hold provider |
| Modify | `lib/media_centaur/topics.ex`, `config/config.exs`, `config/test.exs`, `lib/media_centaur/application.ex`, `test/support/global_state_sandbox.ex`, `lib/media_centaur_web.ex` | wiring |
| Create | `test/media_centaur/recommendations/{translation,recommendations,sync}_test.exs` | |
| Create | `lib/media_centaur_web/live/recommend_flow.ex` | open/close/send helpers over socket assigns |
| Create | `lib/media_centaur_web/live/discovery_live/recommend_modal.ex`, `feed_row.ex` | components (iteration-phase) |
| Modify | `lib/media_centaur_web/live/entity_modal.ex`, `lib/media_centaur_web/components/detail/view_controls.ex`, `lib/media_centaur_web/components/detail_panel.ex`, `storybook/detail/view_controls.story.exs` (or wherever its story is) | Recommend control + injected handlers |
| Modify | `lib/media_centaur_web/live/home_live.ex`, `library_live.ex` | render the modal in overlays; pass `show_discovery` into the panel |
| Modify | `lib/media_centaur_web/components/discovery/watchlist_row.ex` + its story | third action |
| Modify | `lib/media_centaur_web/live/discovery_live.ex`, `lib/media_centaur_web/router.ex`, `lib/media_centaur_web/components/layouts.ex` | Feed tab at `/discovery` |
| Tests | `test/media_centaur_web/live/discovery_live_test.exs`, `library_live_test.exs` | |

---

### Task 1: Records + translation

**Files:** migration, `recommendation.ex`, `translation.ex`, `events.ex`, `recommendations.ex` (context without Sync), `topics.ex`, `tmdb_artwork_holds.ex`, `config/config.exs`, tests `translation_test.exs`, `recommendations_test.exs`.

- [ ] **Step 1: Failing tests**

`test/media_centaur/recommendations/translation_test.exs`:

```elixir
defmodule MediaCentaur.Recommendations.TranslationTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Recommendations.Translation
  alias MediaCentaur.Secret
  alias MediaCentaur.TMDB.Title

  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  defp title do
    Title.new!(%{tmdb_id: 603, media_type: :movie, name: "Sample Movie", year: "1999", release_date: ~D[1999-03-31], poster_path: "/p.jpg", overview: "A sample overview."})
  end

  test "to_event builds an addressable kind-32160 event with the title snapshot and note" do
    event = Translation.to_event(title(), "Watch it twice.", @pubkey)
    assert event.kind == 32160
    assert event.pubkey == @pubkey
    assert Event.tag_value(event, "d") == "tmdb:movie:603"
    refute Event.tag_value(event, "p")
    assert %{"title" => %{"tmdb_id" => 603, "media_type" => "movie", "name" => "Sample Movie", "release_date" => "1999-03-31"}, "note" => "Watch it twice."} = Jason.decode!(event.content)
  end

  test "a nil note serializes as null" do
    assert %{"note" => nil} = Jason.decode!(Translation.to_event(title(), nil, @pubkey).content)
  end

  test "from_event round-trips a signed event into attrs" do
    signed = Event.sign(Translation.to_event(title(), "Watch it twice.", @pubkey), @secret)
    assert {:ok, attrs} = Translation.from_event(signed)
    assert attrs.event_id == signed.id
    assert attrs.author_pubkey == @pubkey
    assert attrs.tmdb_id == 603
    assert attrs.media_type == :movie
    assert %Title{name: "Sample Movie", release_date: ~D[1999-03-31], poster_path: "/p.jpg"} = attrs.title
    assert attrs.note == "Watch it twice."
    assert attrs.recommended_at == DateTime.from_unix!(signed.created_at)
    assert attrs.raw_event == Event.to_map(signed)
  end

  test "from_event rejects the wrong kind, a bad address, mismatched identity, and junk content" do
    good = Event.sign(Translation.to_event(title(), nil, @pubkey), @secret)
    assert {:error, :wrong_kind} = Translation.from_event(%{good | kind: 1})
    assert {:error, :bad_address} = Translation.from_event(%{good | tags: [["d", "imdb:tt1"]]})
    assert {:error, :bad_address} = Translation.from_event(%{good | tags: []})
    assert {:error, :identity_mismatch} = Translation.from_event(%{good | tags: [["d", "tmdb:movie:604"]]})
    assert {:error, :bad_content} = Translation.from_event(%{good | content: "not json"})
    assert {:error, :bad_content} = Translation.from_event(%{good | content: ~s({"title": {"tmdb_id": 603, "media_type": "movie"}})})
  end
end
```

`test/media_centaur/recommendations/recommendations_test.exs`:

```elixir
defmodule MediaCentaur.RecommendationsTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Nostr.{Event, Keys}
  alias MediaCentaur.Recommendations
  alias MediaCentaur.Recommendations.Events.{Received, Sent}
  alias MediaCentaur.Recommendations.{Recommendation, Translation}
  alias MediaCentaur.Secret
  alias MediaCentaur.TMDB.Title

  @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  setup do
    MediaCentaur.TmdbStubs.setup_tmdb_client()
    Identity.ensure()
    :ok
  end

  defp title(id \\ 603), do: Title.new!(%{tmdb_id: id, media_type: :movie, name: "Sample Movie #{id}", year: "1999"})

  defp friend_event(title, note, created_at) do
    %{Translation.to_event(title, note, @friend_pubkey) | created_at: created_at} |> Event.sign(@friend_secret)
  end

  describe "recommend/2" do
    test "signs with the identity, stores it as a sent recommendation, and broadcasts" do
      Recommendations.subscribe()
      assert {:ok, %Recommendation{} = rec} = Recommendations.recommend(title(), "Go.")
      assert rec.author_pubkey == Identity.pubkey()
      assert rec.note == "Go."
      assert {:ok, event} = Event.from_map(rec.raw_event)
      assert Event.verify(event) == :ok
      assert_receive {:recommendation_sent, %Sent{id: id}}, 500
      assert id == rec.id
      assert [%Recommendation{id: ^id}] = Recommendations.list_sent()
      assert Recommendations.list_feed() == []
      await_supervised_tasks()
    end

    test "re-recommending the same title replaces the record" do
      {:ok, a} = Recommendations.recommend(title(), "first")
      {:ok, b} = Recommendations.recommend(title(), "second")
      assert a.id == b.id
      assert Recommendations.list_sent() |> hd() |> Map.get(:note) == "second"
      assert length(Recommendations.own_events()) == 1
      await_supervised_tasks()
    end
  end

  describe "ingest/1" do
    test "accepts a friend's verified event, decorates the feed with the nickname, broadcasts" do
      {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      Recommendations.subscribe()
      event = friend_event(title(), "Great.", 1_700_000_000)

      assert {:ok, %Recommendation{}} = Recommendations.ingest(event)
      assert_receive {:recommendation_received, %Received{author_pubkey: @friend_pubkey}}, 500
      assert [%{recommendation: %Recommendation{note: "Great."}, nickname: "Sample Friend"}] = Recommendations.list_feed()
      await_supervised_tasks()
    end

    test "a newer event replaces, an older one is ignored, the same one is a no-op" do
      {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, first} = Recommendations.ingest(friend_event(title(), "one", 1_700_000_000))
      assert {:ok, newer} = Recommendations.ingest(friend_event(title(), "two", 1_700_000_100))
      assert newer.id == first.id and newer.note == "two"
      assert :ignored = Recommendations.ingest(friend_event(title(), "stale", 1_699_999_000))
      assert :ignored = Recommendations.ingest(friend_event(title(), "two", 1_700_000_100))
      assert [%{recommendation: %{note: "two"}}] = Recommendations.list_feed()
      await_supervised_tasks()
    end

    test "rejects a non-friend author and an invalid signature" do
      event = friend_event(title(), "x", 1_700_000_000)
      assert {:error, :unknown_author} = Recommendations.ingest(event)
      {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      assert {:error, :bad_signature} = Recommendations.ingest(%{event | sig: String.duplicate("0", 128)})
      assert Recommendations.list_feed() == []
    end

    test "own events arriving from a relay are stored as sent, not shown in the feed" do
      {:ok, _} = Recommendations.recommend(title(), "mine")
      [event] = Recommendations.own_events()
      assert :ignored = Recommendations.ingest(event)
      assert Recommendations.list_feed() == []
      await_supervised_tasks()
    end
  end

  test "feed rows come newest first" do
    {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
    {:ok, _} = Recommendations.ingest(friend_event(title(1), "a", 1_700_000_000))
    {:ok, _} = Recommendations.ingest(friend_event(title(2), "b", 1_700_000_500))
    assert [%{recommendation: %{tmdb_id: 2}}, %{recommendation: %{tmdb_id: 1}}] = Recommendations.list_feed()
    await_supervised_tasks()
  end

  test "artwork holds cover every stored title" do
    {:ok, _} = Recommendations.recommend(title(9), nil)
    assert MapSet.member?(Recommendations.TmdbArtworkHolds.holds(), {:movie, 9})
    await_supervised_tasks()
  end
end
```

- [ ] **Step 2: Migration**

```elixir
defmodule MediaCentaur.Repo.Migrations.AddRecommendations do
  @moduledoc "Sent and received recommendations — one row per author + title; a newer event for the same address replaces the row."
  use Ecto.Migration

  def change do
    create table(:recommendations, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :event_id, :text, null: false
      add :author_pubkey, :text, null: false
      add :tmdb_id, :integer, null: false
      add :media_type, :text, null: false
      add :title, :map, null: false
      add :note, :text
      add :recommended_at, :utc_datetime, null: false
      add :raw_event, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:recommendations, [:event_id])
    create unique_index(:recommendations, [:author_pubkey, :tmdb_id, :media_type])
    create index(:recommendations, [:recommended_at])
  end
end
```

- [ ] **Step 3: Schema**

```elixir
defmodule MediaCentaur.Recommendations.Recommendation do
  @moduledoc """
  One recommendation: a signed kind-32160 event translated into a row.
  Identity is `(author_pubkey, tmdb_id, media_type)` — the event's
  address — so a newer event for the same title from the same author
  replaces the row (`recommended_at` decides). `raw_event` keeps the
  signed wire form for republishing. Sent vs received is derived by
  comparing `author_pubkey` with the identity.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MediaCentaur.TMDB.Title

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "recommendations" do
    field :event_id, :string
    field :author_pubkey, :string
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    embeds_one :title, Title, on_replace: :update
    field :note, :string
    field :recommended_at, :utc_datetime
    field :raw_event, :map
    timestamps()
  end

  @type t :: %__MODULE__{}

  @fields [:event_id, :author_pubkey, :tmdb_id, :media_type, :note, :recommended_at, :raw_event]

  def changeset(rec \\ %__MODULE__{}, attrs) do
    rec
    |> cast(Map.delete(attrs, :title), @fields)
    |> put_embed(:title, attrs.title)
    |> validate_required(@fields -- [:note])
    |> unique_constraint(:event_id)
    |> unique_constraint([:author_pubkey, :tmdb_id, :media_type])
  end
end
```

(`on_replace: :update` is right here — the embed *is* replaced on a newer event.)

- [ ] **Step 4: Translation**

```elixir
defmodule MediaCentaur.Recommendations.Translation do
  @moduledoc """
  The anti-corruption layer between Nostr events and recommendation
  records. Kind 32160 (addressable): `d` = `tmdb:<media_type>:<tmdb_id>`;
  content = JSON `{"title": <TMDB.Title fields>, "note": string|null}`.
  An optional `p` (recipient) tag is defined by the spec and never set
  here.
  """

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.TMDB.Title

  @kind 32160
  def kind, do: @kind

  @doc "The address tag value for a title."
  @spec address(Title.t()) :: String.t()
  def address(%Title{tmdb_id: id, media_type: type}), do: "tmdb:#{type}:#{id}"

  @doc "An unsigned recommendation event from `pubkey`."
  @spec to_event(Title.t(), String.t() | nil, String.t()) :: Event.t()
  def to_event(%Title{} = title, note, pubkey) do
    Event.new(%{
      pubkey: pubkey,
      created_at: System.os_time(:second),
      kind: @kind,
      tags: [["d", address(title)]],
      content: Jason.encode!(%{"title" => title_map(title), "note" => blank_to_nil(note)})
    })
  end

  @type attrs :: %{
          event_id: String.t(), author_pubkey: String.t(), tmdb_id: integer(), media_type: Title.media_type(),
          title: Title.t(), note: String.t() | nil, recommended_at: DateTime.t(), raw_event: map()
        }

  @doc "Record attrs from a *verified* event; shape and address checks only."
  @spec from_event(Event.t()) :: {:ok, attrs()} | {:error, :wrong_kind | :bad_address | :bad_content | :identity_mismatch}
  def from_event(%Event{kind: @kind} = event) do
    with {:ok, {media_type, tmdb_id}} <- parse_address(Event.tag_value(event, "d")),
         {:ok, %{"title" => title_attrs} = content} <- decode_content(event.content),
         {:ok, title} <- build_title(title_attrs),
         :ok <- match_identity(title, media_type, tmdb_id) do
      {:ok,
       %{
         event_id: event.id, author_pubkey: event.pubkey, tmdb_id: tmdb_id, media_type: media_type,
         title: title, note: blank_to_nil(content["note"]), recommended_at: DateTime.from_unix!(event.created_at),
         raw_event: Event.to_map(event)
       }}
    end
  end

  def from_event(%Event{}), do: {:error, :wrong_kind}

  defp parse_address("tmdb:movie:" <> id), do: parse_id(:movie, id)
  defp parse_address("tmdb:tv_series:" <> id), do: parse_id(:tv_series, id)
  defp parse_address(_other), do: {:error, :bad_address}

  defp parse_id(type, id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> {:ok, {type, int}}
      _ -> {:error, :bad_address}
    end
  end

  defp decode_content(content) do
    case Jason.decode(content) do
      {:ok, %{"title" => %{}} = map} -> {:ok, map}
      _ -> {:error, :bad_content}
    end
  end

  defp build_title(attrs) when is_map(attrs) do
    case Ecto.Changeset.apply_action(Title.changeset(attrs), :insert) do
      {:ok, title} -> {:ok, title}
      {:error, _} -> {:error, :bad_content}
    end
  end

  defp match_identity(%Title{tmdb_id: id, media_type: type}, type, id), do: :ok
  defp match_identity(_title, _type, _id), do: {:error, :identity_mismatch}

  defp title_map(%Title{} = title), do: title |> Map.from_struct() |> Map.drop([:__meta__]) |> Map.new(fn {k, v} -> {Atom.to_string(k), dump(v)} end)

  defp dump(%Date{} = date), do: Date.to_iso8601(date)
  defp dump(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom), do: Atom.to_string(atom)
  defp dump(other), do: other

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)
end
```

`Title.changeset/2` casts string-keyed maps (`"media_type" => "movie"` → atom via `Ecto.Enum`, `"release_date" => "1999-03-31"` → `Date`). Check `Map.from_struct/1` on an embedded schema — it carries no `__meta__` for embeds, so the `Map.drop` is a no-op safeguard; keep the key set to the eight fields explicitly if anything else leaks.

- [ ] **Step 5: Events, topic, context, holds**

`topics.ex`: `def recommendations_updates, do: "recommendations:updates"` + table row.

`recommendations/events.ex`: `Received{id, author_pubkey}` → `{:recommendation_received, e}`; `Sent{id}` → `{:recommendation_sent, e}`; chokepoint `publish/1`.

`recommendations/tmdb_artwork_holds.ex`: copy `discovery/tmdb_artwork_holds.ex` over `Recommendation` (`select: {r.media_type, r.tmdb_id}`). `config/config.exs` `:tmdb_artwork_hold_providers` gains `MediaCentaur.Recommendations.TmdbArtworkHolds`.

`lib/media_centaur/recommendations.ex`:

```elixir
defmodule MediaCentaur.Recommendations do
  use Boundary,
    deps: [MediaCentaur.Nostr, MediaCentaur.Friends, MediaCentaur.TMDB, MediaCentaur.TmdbArtwork],
    exports: [Recommendation, Translation, Events, Events.Received, Events.Sent, TmdbArtworkHolds]

  @moduledoc """
  Recommendations: what this install sends and what its friends sent.
  Records are translated from signed kind-32160 events (`Translation`),
  kept one per author + title (newest wins), and synced with relays by
  `Recommendations.Sync`. Knows nothing about the watchlist or the
  library — the web layer joins those.
  """

  import Ecto.Query

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Recommendations.{Events, Recommendation, Translation}
  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.Topics

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.recommendations_updates())

  @doc "Builds, signs, stores and publishes a recommendation from this identity."
  @spec recommend(Title.t(), String.t() | nil) :: {:ok, Recommendation.t()} | {:error, term()}
  def recommend(%Title{} = title, note) do
    secret = Identity.ensure()
    event = title |> Translation.to_event(note, Identity.pubkey()) |> Event.sign(secret)

    with {:ok, attrs} <- Translation.from_event(event),
         {:ok, rec} <- upsert(attrs) do
      Friends.Connections.publish(event)
      Events.broadcast(%Events.Sent{id: rec.id})
      {:ok, rec}
    end
  end

  @doc """
  Stores a relay-delivered event: must verify, and the author must be a
  friend or self. `:ignored` when it is not newer than what is stored
  (or is our own event coming back).
  """
  @spec ingest(Event.t()) :: {:ok, Recommendation.t()} | :ignored | {:error, term()}
  def ingest(%Event{} = event) do
    with :ok <- verify(event),
         :ok <- known_author(event.pubkey),
         {:ok, attrs} <- Translation.from_event(event) do
      case upsert_if_newer(attrs) do
        {:ok, rec} ->
          ensure_artwork_async(rec)
          if rec.author_pubkey != Identity.pubkey(), do: Events.broadcast(%Events.Received{id: rec.id, author_pubkey: rec.author_pubkey})
          {:ok, rec}

        :ignored ->
          :ignored
      end
    end
  end

  @doc "Received recommendations, newest first, with the friend's nickname."
  @spec list_feed() :: [%{recommendation: Recommendation.t(), nickname: String.t()}]
  def list_feed do
    me = Identity.pubkey()
    friends = Map.new(Friends.list_friends(), &{&1.pubkey, &1.nickname})

    Repo.all(from(r in Recommendation, where: r.author_pubkey != ^me, order_by: [desc: r.recommended_at]))
    |> Enum.map(&%{recommendation: &1, nickname: Map.get(friends, &1.author_pubkey, "a former friend")})
  end

  @spec list_sent() :: [Recommendation.t()]
  def list_sent do
    me = Identity.pubkey()
    Repo.all(from(r in Recommendation, where: r.author_pubkey == ^me, order_by: [desc: r.recommended_at]))
  end

  @doc "This identity's signed events, for republishing to relays that lack them."
  @spec own_events() :: [Event.t()]
  def own_events do
    Enum.map(list_sent(), fn rec -> {:ok, event} = Event.from_map(rec.raw_event); event end)
  end

  @spec get(Ecto.UUID.t()) :: Recommendation.t() | nil
  def get(id), do: Repo.get(Recommendation, id)

  # --- internals ---

  defp verify(event) do
    case Event.verify(event) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp known_author(pubkey) do
    if pubkey == Identity.pubkey() or Friends.friend_by_pubkey(pubkey), do: :ok, else: {:error, :unknown_author}
  end

  defp upsert(attrs) do
    case existing(attrs) do
      nil -> Repo.insert(Recommendation.changeset(attrs))
      rec -> Repo.update(Recommendation.changeset(rec, attrs))
    end
  end

  defp upsert_if_newer(attrs) do
    case existing(attrs) do
      nil -> Repo.insert(Recommendation.changeset(attrs))
      %Recommendation{recommended_at: at} = rec ->
        if DateTime.compare(attrs.recommended_at, at) == :gt, do: Repo.update(Recommendation.changeset(rec, attrs)), else: :ignored
    end
  end

  defp existing(%{author_pubkey: a, tmdb_id: id, media_type: type}),
    do: Repo.get_by(Recommendation, author_pubkey: a, tmdb_id: id, media_type: type)

  # A recommended title is standing interest: warm its artwork (network,
  # context-layer task — ADR-049).
  defp ensure_artwork_async(rec) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn -> TmdbArtwork.ensure(rec.media_type, rec.tmdb_id) end)
    :ok
  end
end
```

`Friends.Connections.publish/1` must exist (layer 4). Ensure `Friends` exports `Connections`. The unique-constraint race branch (as in Discovery) is unnecessary here — Sync is the single writer for inbound; keep `upsert` simple.

- [ ] **Step 6:** `mix test test/media_centaur/recommendations && mix compile --warnings-as-errors && mix format && mix credo --strict && mix boundaries`; `mix ecto.migrate` on the dev DB. Commit `feat(recommendations): records, event translation, artwork holds`.

---

### Task 2: `Recommendations.Sync`

**Files:** `lib/media_centaur/recommendations/sync.ex`, `application.ex`, `config/test.exs`, `global_state_sandbox.ex`, `test/media_centaur/recommendations/sync_test.exs`

- [ ] **Step 1: Failing tests** (Connections owner + Sync started by hand against fake relays, as in `connections_test.exs`):

```elixir
defmodule MediaCentaur.Recommendations.SyncTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.{Connections, Identity}
  alias MediaCentaur.Nostr.{Event, FakeRelay}
  alias MediaCentaur.Recommendations
  alias MediaCentaur.Recommendations.{Sync, Translation}
  alias MediaCentaur.Secret
  alias MediaCentaur.TMDB.Title

  @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  setup do
    MediaCentaur.TmdbStubs.setup_tmdb_client()
    Identity.ensure()
    {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
    start_supervised!({Connections.Owner, backoff_ms: 50})
    start_supervised!(Sync)
    Recommendations.subscribe()
    :ok
  end

  defp title(id), do: Title.new!(%{tmdb_id: id, media_type: :movie, name: "Sample Movie #{id}"})
  defp friend_event(id), do: Event.sign(Translation.to_event(title(id), "from a friend", @friend_pubkey), @friend_secret)

  test "on connect, a friend's stored recommendation lands in the feed" do
    relay = FakeRelay.start(events: [friend_event(1)])
    {:ok, _} = Friends.add_relay(relay.url)

    assert_receive {:recommendation_received, _}, 5_000
    assert [%{recommendation: %{tmdb_id: 1}, nickname: "Sample Friend"}] = Recommendations.list_feed()
    await_supervised_tasks()
  end

  test "own recommendations the relay lacks are published after its EOSE" do
    {:ok, _} = Recommendations.recommend(title(7), "mine")
    relay = FakeRelay.start()
    {:ok, _} = Friends.add_relay(relay.url)

    assert_receive {:relay_in, ["EVENT", %{"kind" => 32160, "tags" => [["d", "tmdb:movie:7"]]}]}, 5_000
    await_supervised_tasks()
  end

  test "own recommendations the relay already has are not republished" do
    {:ok, _} = Recommendations.recommend(title(7), "mine")
    [own] = Recommendations.own_events()
    relay = FakeRelay.start(events: [own])
    {:ok, _} = Friends.add_relay(relay.url)

    assert_receive {:relay_in, ["REQ", "own:" <> _, _]}, 5_000
    refute_receive {:relay_in, ["EVENT", _]}, 1_000
    await_supervised_tasks()
  end

  test "a live event from a friend arrives through the feed subscription" do
    relay = FakeRelay.start()
    {:ok, _} = Friends.add_relay(relay.url)
    assert_receive {:relay_in, ["REQ", "feed", %{"authors" => authors, "kinds" => [32160]}]}, 5_000
    assert @friend_pubkey in authors and Identity.pubkey() in authors

    FakeRelay.push(relay, ["EVENT", "feed", Event.to_map(friend_event(2))])
    assert_receive {:recommendation_received, _}, 5_000
    await_supervised_tasks()
  end

  test "adding a friend resubscribes the feed with the new author" do
    relay = FakeRelay.start()
    {:ok, _} = Friends.add_relay(relay.url)
    assert_receive {:relay_in, ["REQ", "feed", _]}, 5_000

    other = MediaCentaur.Nostr.Keys.generate()
    {:ok, _} = Friends.add_friend(MediaCentaur.Nostr.Keys.pubkey(other), "Another")
    assert_receive {:relay_in, ["REQ", "feed", %{"authors" => authors}]}, 5_000
    assert MediaCentaur.Nostr.Keys.pubkey(other) in authors
  end

  test "events from strangers on the relay are ignored" do
    stranger = MediaCentaur.Nostr.Keys.generate()
    event = Event.sign(Translation.to_event(title(3), nil, MediaCentaur.Nostr.Keys.pubkey(stranger)), stranger)
    relay = FakeRelay.start()
    {:ok, _} = Friends.add_relay(relay.url)
    assert_receive {:relay_in, ["REQ", "feed", _]}, 5_000

    FakeRelay.push(relay, ["EVENT", "feed", Event.to_map(event)])
    refute_receive {:recommendation_received, _}, 500
    assert Recommendations.list_feed() == []
  end
end
```

- [ ] **Step 2: Sync**

```elixir
defmodule MediaCentaur.Recommendations.Sync do
  @moduledoc """
  Keeps recommendations in step with the relays. Consumes
  `friends:connections`:

    * `:connected` for a relay → subscribe `"feed"` (authors = friends
      ++ self, kind 32160) and `"own:<url>"` (authors = [self]) on that
      relay; collect the event ids the relay sends on the own sub.
    * `{:eose, "own:<url>"}` → publish to that relay every stored own
      event it did not send (per-relay diff; addressable events are few).
    * `{:event, _, event}` → `Recommendations.ingest/1` (verified, friend
      or self, newest wins).

  Consumes `friends:updates`: a roster change resubscribes `"feed"` on
  every relay with the new author list. Gated off under `:test`
  (`:start_recommendations_sync`); tests start it by hand.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.{Connections, Identity}
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Recommendations
  alias MediaCentaur.Recommendations.Translation

  defstruct seen: %{}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc false
  def __sync_for_test__(server \\ __MODULE__), do: GenServer.call(server, :sync)

  @impl true
  def init(_opts) do
    Friends.subscribe_connections()
    Friends.subscribe()
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({:relay_connection, url, :connected}, state) do
    Connections.subscribe(url, "feed", [feed_filter()])
    Connections.subscribe(url, own_sub(url), [own_filter()])
    {:noreply, %{state | seen: Map.put(state.seen, url, MapSet.new())}}
  end

  def handle_info({:relay_connection, url, {:event, sub_id, event}}, state) do
    state = if sub_id == own_sub(url), do: %{state | seen: Map.update(state.seen, url, MapSet.new([event.id]), &MapSet.put(&1, event.id))}, else: state

    case Recommendations.ingest(event) do
      {:ok, _} -> :ok
      :ignored -> :ok
      {:error, reason} -> Log.debug(:friends, "#{url}: dropped event #{event.id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info({:relay_connection, url, {:eose, sub_id}}, state) do
    if sub_id == own_sub(url) do
      seen = Map.get(state.seen, url, MapSet.new())
      missing = Enum.reject(Recommendations.own_events(), &MapSet.member?(seen, &1.id))
      for event <- missing, do: Connections.publish(url, event)
      if missing != [], do: Log.info(:friends, "#{url}: published #{length(missing)} recommendation(s) it lacked")
    end

    {:noreply, state}
  end

  def handle_info({:friend_added, _}, state), do: resubscribe(state)
  def handle_info({:friend_removed, _}, state), do: resubscribe(state)
  def handle_info(_other, state), do: {:noreply, state}

  defp resubscribe(state) do
    Connections.subscribe_all("feed", [feed_filter()])
    {:noreply, state}
  end

  defp feed_filter, do: Filter.new(authors: Enum.uniq([Identity.pubkey() | Friends.friend_pubkeys()]), kinds: [Translation.kind()])
  defp own_filter, do: Filter.new(authors: [Identity.pubkey()], kinds: [Translation.kind()])
  defp own_sub(url), do: "own:" <> url
end
```

`Identity.pubkey/0` may be nil before an identity exists; `Connections` starts no connections without one, so `:connected` never arrives then — still, guard `feed_filter/0` with `Enum.reject(&is_nil/1)`.

- [ ] **Step 3: Wiring** — `application.ex`: child `MediaCentaur.Recommendations.Sync` after `Friends.Connections`, gated: `if Application.get_env(:media_centaur, :start_recommendations_sync, true), do: [Sync], else: []` (mirror how `Friends.Connections` gates its owner, or gate at the app level like `:start_playback_recovery`); `config/test.exs`: `config :media_centaur, :start_recommendations_sync, false`; `global_state_sandbox.ex` `@dispositions`: `MediaCentaur.Recommendations.Sync => {:stateless, "not started under :test"}` (only if it is a top-level child); application Boundary deps add `MediaCentaur.Recommendations`.

- [ ] **Step 4:** tests + gates; commit `feat(recommendations): Sync — per-relay feed subscription and own-events diff`.

---

### Task 3: Recommend modal (detail page + watchlist rows)

**Files:** `lib/media_centaur_web/live/recommend_flow.ex`, `lib/media_centaur_web/live/discovery_live/recommend_modal.ex`, `entity_modal.ex`, `components/detail/view_controls.ex` (+ story), `components/detail_panel.ex`, `home_live.ex`, `library_live.ex`, `components/discovery/watchlist_row.ex` (+ story), `discovery_live.ex`, `lib/media_centaur_web.ex` (dep), tests.

- [ ] **Step 1: Failing tests**

`discovery_live_test.exs` (watchlist tab):

```elixir
  describe "recommend from a watchlist row" do
    setup do
      Identity.ensure()
      :ok
    end

    test "opens the modal, sends with a note, and flashes", %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))
      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      view |> element("#watchlist-item-movie-777 button", "Recommend") |> render_click()
      assert has_element?(view, "#recommend-modal[data-state='open']", "Sample Movie")
      assert has_element?(view, "#recommend-modal", "No relay configured")

      view |> form("#recommend-form", %{"note" => "Watch it."}) |> render_submit()
      assert render(view) =~ "Saved — it will send when a relay connects"
      refute has_element?(view, "#recommend-modal[data-state='open']")
      assert [%{note: "Watch it.", tmdb_id: 777}] = Recommendations.list_sent()
      await_supervised_tasks()
    end

    test "cancel closes without sending", %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))
      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      view |> element("#watchlist-item-movie-777 button", "Recommend") |> render_click()
      view |> element("#recommend-cancel") |> render_click()
      refute has_element?(view, "#recommend-modal[data-state='open']")
      assert Recommendations.list_sent() == []
      await_supervised_tasks()
    end
  end
```

`library_live_test.exs` — next to the existing `#detail-watchlist-toggle` test (find it), with `show_discovery` on:

```elixir
  test "the detail page's Recommend control opens the modal and sends", %{conn: conn} do
    MediaCentaur.Settings.find_or_create_entry!(%{key: DiscoveryVisibility.setting_key(), value: %{"enabled" => true}})
    MediaCentaur.Friends.Identity.ensure()
    movie = create_standalone_movie(%{name: "Sample Movie"})
    create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
    {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

    view |> element("#detail-recommend") |> render_click()
    assert has_element?(view, "#recommend-modal[data-state='open']", "Sample Movie")
    view |> form("#recommend-form", %{"note" => ""}) |> render_submit()
    assert [%{tmdb_id: 777, note: nil}] = MediaCentaur.Recommendations.list_sent()
    await_supervised_tasks()
  end

  test "the Recommend control is absent while Discovery is off", %{conn: conn} do
    movie = create_standalone_movie(%{name: "Sample Movie"})
    create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
    {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")
    refute has_element?(view, "#detail-recommend")
  end
```

(Mirror the existing detail-toggle test's fixtures exactly — `grep -n "detail-watchlist-toggle" test/media_centaur_web/live/library_live_test.exs`.)

- [ ] **Step 2: `RecommendFlow`** — `lib/media_centaur_web/live/recommend_flow.ex`:

```elixir
defmodule MediaCentaurWeb.Live.RecommendFlow do
  @moduledoc """
  The Recommend modal's state, shared by every host that renders it
  (library detail hosts via `EntityModal`'s injected handlers, the
  Discovery page for watchlist rows). Assigns: `recommend_subject`
  (`Title.t()` or nil = closed). Send goes through
  `Recommendations.recommend/2`; the flash names whether a relay was
  connected at the time.
  """
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias MediaCentaur.Friends.Connections
  alias MediaCentaur.Recommendations
  alias MediaCentaur.TMDB.Title

  def init(socket), do: assign(socket, recommend_subject: nil)
  def open(socket, %Title{} = title), do: assign(socket, recommend_subject: title)
  def close(socket), do: assign(socket, recommend_subject: nil)

  def send(%{assigns: %{recommend_subject: %Title{} = title}} = socket, note) do
    case Recommendations.recommend(title, note) do
      {:ok, _} ->
        message = if connected_count() > 0, do: "Recommended to your friends", else: "Saved — it will send when a relay connects"
        socket |> close() |> put_flash(:info, message)

      {:error, _} ->
        socket |> close() |> put_flash(:error, "Could not send the recommendation")
    end
  end

  def send(socket, _note), do: socket

  @doc "`{connected, total}` for the modal's relay line."
  def relay_counts do
    status = Connections.status()
    {Enum.count(status, fn {_url, %{state: state}} -> state == :connected end), map_size(status)}
  end

  defp connected_count, do: elem(relay_counts(), 0)
end
```

- [ ] **Step 3: The modal component** — `lib/media_centaur_web/live/discovery_live/recommend_modal.ex` (rendered by every host in `<:overlays>` with `style="z-index: 60;"` like the Incoming confirmations):

```elixir
defmodule MediaCentaurWeb.DiscoveryLive.RecommendModal do
  @moduledoc "The Recommend modal: the title, an optional note, the relay state, Send/Cancel. Events `recommend_send` (form) and `recommend_cancel` bubble to the host. Iteration-phase component."
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Modal, only: [modal: 1]
  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.TMDB.Title

  attr :subject, Title, default: nil, doc: "nil = closed"
  attr :relay_counts, :any, required: true, doc: "`{connected, total}`"

  def recommend_modal(assigns) do
    ~H"""
    <.modal id="recommend-modal" open={!is_nil(@subject)} dismiss={:persistent} size={:sm} panel_class="p-6" style="z-index: 60;">
      <div :if={@subject} class="space-y-4">
        <h2 class="text-sm font-semibold">Recommend to your friends</h2>
        <.title_summary title={@subject} poster_url={title_poster_url(@subject)} />
        <form id="recommend-form" phx-submit="recommend_send" class="space-y-3">
          <textarea name="note" rows="3" placeholder="Why they should watch it (optional)" class="textarea textarea-bordered w-full text-sm"></textarea>
          <p class="text-xs text-base-content/50">{relay_line(@relay_counts)}</p>
          <div class="flex justify-end gap-2">
            <.button id="recommend-cancel" type="button" variant="dismiss" size="sm" phx-click="recommend_cancel">Cancel</.button>
            <.button id="recommend-send" type="submit" variant="neutral" size="sm">Send</.button>
          </div>
        </form>
      </div>
    </.modal>
    """
  end

  defp relay_line({_connected, 0}), do: "No relay configured — it will send when you add one"
  defp relay_line({connected, total}), do: "Connected to #{connected} of #{total} relays"
end
```

Read `components/modal.ex` for the exact attrs (`open`, `dismiss`, `size`, `panel_class`, `rest` → backdrop) and adapt; `:persistent` needs no `on_close`. `title_summary` inside a modal: fine (spans).

- [ ] **Step 4: Hosts**

- `entity_modal.ex` `__using__`: inject
  ```elixir
      def handle_event("modal_recommend_open", _params, socket), do: {:noreply, EntityModal.open_recommend(socket)}
      def handle_event("recommend_cancel", _params, socket), do: {:noreply, RecommendFlow.close(socket)}
      def handle_event("recommend_send", %{"note" => note}, socket), do: {:noreply, RecommendFlow.send(socket, note)}
  ```
  and `EntityModal.open_recommend/1`: resolves the subject like `toggle_watchlist/1` (`watchlist_subject/2` + `watchlist_ref/1`), builds `Title.new!(%{tmdb_id, media_type, name: subject.name, year: watchlist_year(...), release_date: subject[:date_published], overview: subject[:description]})` (no poster path — receivers fetch art), then `RecommendFlow.open(socket, title)`; no-op when no ref. The on_mount hook (`{EntityModal, :default}`) calls `RecommendFlow.init/1` so the assign exists.
- `view_controls.ex`: new `attr :recommend?, :boolean, default: false` and, when true, a button after the bookmark: `id="detail-recommend"`, `variant="dismiss" size="sm" shape="circle"`, `phx-click="modal_recommend_open"`, `title="Recommend"`, icon `hero-paper-airplane`, `data-nav-item tabindex="0"`; moduledoc "## Recommend" section; story variation. `detail_panel.ex`: `attr :recommend?` threaded through; the entity modal renderer passes `recommend?={@show_discovery}` (the session-wide assign exists on every host).
- `home_live.ex`, `library_live.ex`: in the `Layouts.app` `<:overlays>` slot (find where each renders overlays — `grep -n "overlays" lib/media_centaur_web/live/home_live.ex library_live.ex`; if a host has none, add the slot) render `<RecommendModal.recommend_modal subject={@recommend_subject} relay_counts={RecommendFlow.relay_counts()} />`. `relay_counts/0` reads `Connections.status/0` — a `GenServer.call` on render; acceptable (one call, only when the host renders; under `:test` it returns `{0, 0}` without a process). If the no-DB-on-render test budget objects, compute it in `open/2` and store as an assign instead — do that if in doubt (simpler: `RecommendFlow.open/2` assigns `recommend_relay_counts` too; the component takes it from the assign).
- `watchlist_row.ex`: third action **Recommend** (`phx-click="watchlist_recommend"`, `phx-value-tmdb-id`/`phx-value-media-type`) between the primary action and Remove; `grid-cols-[auto_auto_auto]`; rewrite the nav-grid comment ("exactly these three nav items: primary ↔ Recommend ↔ Remove"); story: descriptions mention Recommend. `DiscoveryLive`: `RecommendFlow.init/1` in mount; `"watchlist_recommend"` → find the item → `RecommendFlow.open(socket, item.title)`; `"recommend_cancel"`/`"recommend_send"` as above; render the modal in its overlays slot.
- `lib/media_centaur_web.ex`: Boundary deps add `MediaCentaur.Recommendations`.

- [ ] **Step 5:** tests (`discovery_live_test`, `library_live_test`, `home_live_test`, storybook tests, `no_db_on_render_test`) + gates. Commit `feat(web): Recommend modal from library detail and watchlist rows`.

---

### Task 4: Feed tab at `/discovery`

**Files:** `router.ex`, `layouts.ex`, `discovery_live.ex`, `discovery_live/feed_row.ex`, tests.

- [ ] **Step 1: Failing tests**

```elixir
  describe "feed tab" do
    setup do
      Identity.ensure()
      :ok
    end

    test "empty state names the prerequisites, then the quiet empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Feed")
      assert render(view) =~ "Add a relay and a friend on the Friends tab"

      {:ok, _} = Friends.add_relay("wss://relay.example")
      {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, view, _html} = live(conn, "/discovery")
      assert render(view) =~ "Nothing from your friends yet."
    end

    test "rows show the title, who and when, the note, and add to the watchlist", %{conn: conn} do
      {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Recommendations.ingest(friend_event(777, "Watch it."))
      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, "#feed-#{rec.id}", "Sample Movie 777")
      assert has_element?(view, "#feed-#{rec.id}", "from Sample Friend")
      assert has_element?(view, "#feed-#{rec.id}", "Watch it.")

      view |> element("#feed-#{rec.id} button", "Add to watchlist") |> render_click()
      assert Discovery.on_watchlist?(777, :movie)
      assert has_element?(view, "#feed-#{rec.id}", "On watchlist")
      await_supervised_tasks()
    end

    test "a title the library has shows In library and links to it", %{conn: conn} do
      {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Recommendations.ingest(friend_event(777, nil))
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
      create_linked_file(%{movie_id: movie.id})
      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "#feed-#{rec.id} a[href='/library?selected=#{movie.id}']", "In library")
      await_supervised_tasks()
    end

    test "a received recommendation appears without a reload", %{conn: conn} do
      {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, view, _html} = live(conn, "/discovery")
      {:ok, rec} = Recommendations.ingest(friend_event(778, "live"))
      render_until(view, fn _ -> has_element?(view, "#feed-#{rec.id}") end)
      await_supervised_tasks()
    end

    test "the tab strip counts the feed", %{conn: conn} do
      {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _} = Recommendations.ingest(friend_event(777, nil))
      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a", "Feed")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a .badge", "1")
      await_supervised_tasks()
    end
  end
```

(`friend_event/2` helper as in the context tests; `@friend_pubkey`/secret constants; `TmdbStubs.setup_tmdb_client()` already in setup.)

- [ ] **Step 2: Route + sidebar** — `router.ex`: `live "/discovery", DiscoveryLive, :feed` (before the other discovery routes); `layouts.ex`: the sidebar link `navigate="/discovery"`.

- [ ] **Step 3: LiveView** — `mount/3`: `Recommendations.subscribe()` under `connected?`; `handle_params` for `:feed`: `assign(feed: load_feed())`; `tabs/2` takes both counts: `[%Tab{id: :feed, label: "Feed", navigate: "/discovery", count: feed_count}, watchlist…, friends…]` — compute `feed_count` for every action (`length(Recommendations.list_feed())` is fine; the table is small), `watchlist_count` likewise; `current_path(:feed) -> "/discovery"`; events `"feed_add_to_watchlist"` (`%{"id" => id}`) → `rec = Recommendations.get(id)`; `Discovery.add_to_watchlist(rec.title, %{note: rec.note})` (layer 7 adds `source: :friend, recommendation_id`); reload feed decorations; `handle_info({:recommendation_received, _} | {:recommendation_sent, _})` → reload feed + counts when on `:feed` (and counts always). `handle_info({:watchlist_item_added|removed, _})` already reloads items — also refresh the feed's `on_watchlist?` decoration.

```elixir
  defp load_feed do
    rows = Recommendations.list_feed()
    refs = Enum.map(rows, &{&1.recommendation.tmdb_id, &1.recommendation.media_type})
    owners = ExternalIds.tmdb_owners(refs)
    watchlisted = Discovery.watchlisted_refs()

    Enum.map(rows, fn %{recommendation: rec} = row ->
      ref = {rec.tmdb_id, rec.media_type}
      Map.merge(row, %{poster_url: title_poster_url(rec.title), library_owner_id: Map.get(owners, ref), on_watchlist?: MapSet.member?(watchlisted, ref)})
    end)
  end
```

(`Library.ExternalIds` is reachable from the web layer — `Library` is a web dep; alias as `DiscoveryLive` already aliases `Library`.)

- [ ] **Step 4: Feed row** — `lib/media_centaur_web/live/discovery_live/feed_row.ex`: `attr :row, :map, required: true, doc: "…"` (recommendation, nickname, poster_url, library_owner_id, on_watchlist?); `<div id={"feed-" <> rec.id} class="glass-surface flex w-full items-start gap-4 rounded-xl px-4 py-3">` with `<.title_summary title={rec.title} poster_url={@row.poster_url}>` — `<:markers>` a quiet `from {nickname} · {Format.relative_ago(rec.recommended_at)}` span; `<:secondary :if={rec.note}>{rec.note}</:secondary>`; action strip: `In library` link when `library_owner_id`, else `On watchlist` (`<span>` quiet, when `on_watchlist?`) else button **Add to watchlist** (`phx-click="feed_add_to_watchlist" phx-value-id={rec.id}`). Empty states per the copy decisions: choose the prerequisite line when `Friends.list_relays() == [] or Friends.list_friends() == []` (compute `prereqs_met?` in `handle_params`), else the quiet line.

- [ ] **Step 5:** tests + gates; `page-shot` of `/discovery` on the dev server (the owner has no friends yet, so expect the prerequisites empty state and the three tabs). Commit `feat(discovery): Feed tab — friends' recommendations at /discovery`.

---

### Task 5: Precommit + campaign

- [ ] `mix precommit` PASSED.
- [ ] `campaigns/friends-recommendations.md` Status: "Layer 6 (`Recommendations` records/translation/sync, Recommend modal, Feed tab at `/discovery`) landed 2026-09-02; next: layer 7 (watchlist provenance `:friend` + `recommendation_id`, Status page Friends section)." Decisions: add the three decisions fixed above (web-layer decoration; Recommend control gated by `show_discovery`; short relative time).
- [ ] Commit `docs(campaign): recommendations landed; next = watchlist provenance + Status section`.

---

## Self-review

**Spec coverage:** `Recommendations` context (schema, translation, sync, `recommend`, `list_feed`, `list_sent`, artwork holds, `recommendations:updates`) → Tasks 1–2; runtime behavior (subscribe on connect, outbound sync by comparing the relay's own-events view, inbound verify + author check + newer-wins + broadcast, sending with zero relays persists locally and the modal says so) → Tasks 2–3; Recommend modal from detail pages and watchlist rows with note + relay line + Send, re-recommend replaces → Task 3; Feed tab rows (title, nickname, time, note; Add to watchlist / In library; empty states) → Task 4; sidebar target `/discovery` → Task 4. Layer 7 owns `:friend`/`recommendation_id` and the Status section.

**Type consistency:** `Translation.kind/0`, `address/1`, `to_event/3`, `from_event/1`; `Recommendations.subscribe/0`, `recommend/2`, `ingest/1`, `list_feed/0`, `list_sent/0`, `own_events/0`, `get/1`; events `{:recommendation_received, %Received{id, author_pubkey}}`, `{:recommendation_sent, %Sent{id}}`; `Sync` subs `"feed"` and `"own:" <> url`; `Connections.subscribe/3`, `publish/2`, `subscribe_all/2`, `publish/1`, `status/0` (layer 4 as amended); `RecommendFlow.init/1`, `open/2`, `close/1`, `send/2`, `relay_counts/0`; assigns `recommend_subject`; events `modal_recommend_open`, `recommend_cancel`, `recommend_send`, `watchlist_recommend`, `feed_add_to_watchlist`; ids `recommend-modal`, `recommend-form`, `recommend-cancel`, `recommend-send`, `detail-recommend`, `feed-<uuid>`.

**Placeholders:** none. One open verification for the implementer: the `no_db_on_render` budget for hosts that call `Connections.status/0` in render — the plan names the fallback (assign at open time).
