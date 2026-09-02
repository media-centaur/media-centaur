# Watchlist Foundation (Discovery Context) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A local watchlist — title-level "I want to watch this" intent with provenance — as the substrate every future discovery source (TMDB discover, list import, Nostr recs) lands on. Spec: `docs/superpowers/specs/2026-08-18-watchlist-foundation-design.md`.

**Architecture:** New `MediaCentaur.Discovery` bounded context (deps: Library, TmdbArtwork) owning one `watchlist_items` table. Library presence is derived at read time via `Library.ExternalIds` (never stored). UI: a 3-state watchlist action on media-search rows, a toggle in the detail modal's view controls, and a `/watchlist` page whose pursue action reuses the existing plan flow (`/incoming?plan=new&…`) and track flow (`ReleaseTracking.track_from_search_async/2`) untouched.

**Tech Stack:** Phoenix LiveView, Ecto/SQLite, Boundary, Phoenix Storybook, input-system nav (config.js zones + page behavior).

**House rules for the executor:** invoke `automated-testing` before any test/implementation; `ecto-thinking` for Tasks 1–3; `phoenix-thinking` + `user-interface` for Tasks 6–10; `storybook` for any story; `input-system` for Task 8; `writing-copy` for all user-facing text. Zero warnings. `mix precommit` before finishing. Commit per task to `main`; do not push.

## Unification decisions (unify_design pass — already adjudicated, follow as written)

1. **Title value type stays put; convergence scheduled.** Greenfield would home a decoration-free "TMDB title" struct in the TMDB adapter context; today `ReleaseTracking.TitleResult` carries that role plus RT's `tracked?` decoration. Discovery's boundary therefore takes **plain attrs** (idiomatic cross-context composition: plain data + changeset validation), not `%TitleResult{}`. **Named convergence point:** when Discovery gains its first TMDB-calling source (TMDB discover, iteration 2), move title search + a neutral title struct into `MediaCentaur.TMDB` and re-point RT and Discovery at it. Record this in the Discovery moduledoc (Task 2 includes the text). *[Converged 2026-09-02 in `docs/superpowers/plans/2026-09-02-title-convergence.md`: `MediaCentaur.TMDB.Title` + `TitleSearch`; Discovery takes the struct.]*
2. **New decorations are component attrs, not struct fields.** `watchlisted?`/in-library state on search rows arrive as MapSet attrs decorated at the web layer (live-updatable without re-searching; RT cannot own them without an illegal dep). `tracked?` stays struct-baked for now; it converges to the attr mechanism next time RT search is being changed anyway — never in a sweep. *[Converged 2026-09-02: `tracked?` is `tracked_refs`.]*
3. **One owner for "does the library know this TMDB title":** a new bulk `ExternalIds.tmdb_owners/1`. Semantics: *container exists* (both types) — distinct from the stricter file-present checks (`find_present_movie/1`) the plan modal keeps using. *[Amended 2026-08-18: implementation corrected the semantics to* presentable (file-linked) *via the `PresentableQueries` presence fragments (commits fd63a52c, b0922a63) — `Presentable.resolve` requires files, so a container-only match would have produced In-library rows that cannot open or play.]*
4. **One shared refresh mechanism:** `MediaCentaurWeb.Live.WatchlistAware` on_mount (SettingAware-family pattern) seeds `:watchlisted_refs` and keeps it live. Snapshot *resolution* stays per-surface (each surface has different local data), so toggle `handle_event`s are thin per-host clauses; the detail modal's lives in `EntityModal` so LibraryLive + HomeLive share it structurally.
5. **`release_status` generalizes rather than duplicates:** `MediaResults.release_status/2` heads relax from `%TitleResult{}` to `%{release_date: _}` so the watchlist row reuses the same released/upcoming logic and verb honesty.

---

### Task 1: Migration + WatchlistItem schema

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_watchlist_items.exs` (generate with `mix ecto.gen.migration add_watchlist_items`)
- Create: `lib/media_centaur/discovery/watchlist_item.ex`
- Test: `test/media_centaur/discovery_test.exs`

- [ ] **Step 1: Write the failing schema test**

```elixir
defmodule MediaCentaur.DiscoveryTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.Discovery.WatchlistItem

  describe "WatchlistItem.create_changeset/1" do
    test "valid with identity + name" do
      changeset =
        WatchlistItem.create_changeset(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      assert changeset.valid?
    end

    test "requires tmdb_id, media_type, name" do
      changeset = WatchlistItem.create_changeset(%{})
      refute changeset.valid?
      assert %{tmdb_id: _, media_type: _, name: _} = errors_on(changeset)
    end

    test "rejects unknown media_type" do
      changeset =
        WatchlistItem.create_changeset(%{tmdb_id: 777, media_type: :book, name: "Sample"})

      refute changeset.valid?
    end
  end
end
```

- [ ] **Step 2: Run it — expect failure** — `mix test test/media_centaur/discovery_test.exs` fails with `WatchlistItem` undefined.

- [ ] **Step 3: Migration**

```elixir
defmodule MediaCentaur.Repo.Migrations.AddWatchlistItems do
  use Ecto.Migration

  def change do
    create table(:watchlist_items, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :tmdb_id, :integer, null: false
      add :media_type, :text, null: false
      add :name, :text, null: false
      add :year, :text
      add :release_date, :date
      add :poster_path, :text
      add :overview, :text
      add :source, :text, null: false, default: "manual"
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:watchlist_items, [:tmdb_id, :media_type])
  end
end
```

- [ ] **Step 4: Schema**

```elixir
defmodule MediaCentaur.Discovery.WatchlistItem do
  @moduledoc """
  Title-level "I want to watch this" intent — a snapshot of a TMDB
  title plus provenance.

  Identity is `(tmdb_id, media_type)` — TMDB's movie and TV id spaces
  overlap, same convention as `ReleaseTracking.Item` and the TmdbArtwork
  cache. The remaining TMDB fields are a *snapshot* cached at add time so
  the item renders without TMDB reachability; the library is never
  referenced from here — presence is derived at read time via
  `Library.ExternalIds` (one source of truth, cannot go stale).

  `source` is the provenance seam every future candidate source extends
  (`:friend`, `:import`, …); directed recommendations later add nullable
  sender/recipient columns — no dead columns until then.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "watchlist_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    field :year, :string
    field :release_date, :date
    field :poster_path, :string
    field :overview, :string
    field :source, Ecto.Enum, values: [:manual], default: :manual
    field :note, :string

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:tmdb_id, :media_type, :name, :year, :release_date, :poster_path, :overview, :source, :note])
    |> validate_required([:tmdb_id, :media_type, :name])
    |> unique_constraint([:tmdb_id, :media_type])
  end
end
```

- [ ] **Step 5: Migrate + run tests** — `mix ecto.migrate && mix test test/media_centaur/discovery_test.exs` → PASS. (Reminder: bare mix targets the real dev DB — that is correct here; test DB migrates via test_helper.)

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(discovery): watchlist_items table + schema"`

---

### Task 2: Discovery context — add/remove/list/refs + Events + topic

**Files:**
- Create: `lib/media_centaur/discovery.ex`
- Create: `lib/media_centaur/discovery/events.ex`
- Modify: `lib/media_centaur/topics.ex` (new accessor + moduledoc table row)
- Test: `test/media_centaur/discovery_test.exs` (extend)

- [ ] **Step 1: Failing tests**

```elixir
  describe "watchlist" do
    @attrs %{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010", poster_path: "/p.jpg"}

    test "add_to_watchlist is idempotent" do
      assert {:ok, item} = Discovery.add_to_watchlist(@attrs)
      assert {:ok, ^item} = Discovery.add_to_watchlist(@attrs)
      assert [_] = Repo.all(WatchlistItem)
    end

    test "add broadcasts a typed event" do
      Discovery.subscribe()
      {:ok, item} = Discovery.add_to_watchlist(@attrs)
      item_id = item.id
      assert_receive {:watchlist_item_added, %Discovery.Events.ItemAdded{item_id: ^item_id, tmdb_id: 777, media_type: :movie}}
    end

    test "remove_from_watchlist deletes and broadcasts; absent is a no-op" do
      {:ok, _} = Discovery.add_to_watchlist(@attrs)
      Discovery.subscribe()
      assert :ok = Discovery.remove_from_watchlist(777, :movie)
      assert_receive {:watchlist_item_removed, %Discovery.Events.ItemRemoved{tmdb_id: 777, media_type: :movie}}
      assert :ok = Discovery.remove_from_watchlist(777, :movie)
      refute Discovery.on_watchlist?(777, :movie)
    end

    test "watchlisted_refs returns the ref set" do
      {:ok, _} = Discovery.add_to_watchlist(@attrs)
      {:ok, _} = Discovery.add_to_watchlist(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show"})
      assert Discovery.watchlisted_refs() == MapSet.new([{777, :movie}, {42, :tv_series}])
    end

    test "list_watchlist returns newest-first with nil library owner when absent" do
      {:ok, _} = Discovery.add_to_watchlist(@attrs)
      assert [%{item: %WatchlistItem{tmdb_id: 777}, library_owner_id: nil}] = Discovery.list_watchlist()
    end
  end
```

- [ ] **Step 2: Run — expect failure** (Discovery undefined).

- [ ] **Step 3: Topics** — add `def discovery_updates, do: "discovery:updates"` beside the other source topics and a moduledoc table row: `| discovery:updates | Discovery.Events | {:watchlist_item_added, _}, {:watchlist_item_removed, _} |`.

- [ ] **Step 4: Events module** (ADR-060, mirror `Review.Events`)

```elixir
defmodule MediaCentaur.Discovery.Events do
  @moduledoc """
  Typed payloads for the `discovery:updates` topic (ADR-060): one struct
  per message, `@enforce_keys`, a single `broadcast/1`.
  """

  alias MediaCentaur.Topics

  defmodule ItemAdded do
    @moduledoc "A title joined the watchlist. Subscribers refresh their ref set / list."
    @enforce_keys [:item_id, :tmdb_id, :media_type]
    defstruct [:item_id, :tmdb_id, :media_type]

    @type t :: %__MODULE__{item_id: Ecto.UUID.t(), tmdb_id: integer(), media_type: :movie | :tv_series}
  end

  defmodule ItemRemoved do
    @moduledoc "A title left the watchlist. The row is already gone — subscribers drop the ref."
    @enforce_keys [:tmdb_id, :media_type]
    defstruct [:tmdb_id, :media_type]

    @type t :: %__MODULE__{tmdb_id: integer(), media_type: :movie | :tv_series}
  end

  @type t :: ItemAdded.t() | ItemRemoved.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%ItemAdded{} = event), do: publish({:watchlist_item_added, event})
  def broadcast(%ItemRemoved{} = event), do: publish({:watchlist_item_removed, event})

  defp publish(message), do: Topics.publish(Topics.discovery_updates(), message)
end
```

- [ ] **Step 5: Context facade**

```elixir
defmodule MediaCentaur.Discovery do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.TmdbArtwork],
    exports: [WatchlistItem, Events, Events.ItemAdded, Events.ItemRemoved]

  @moduledoc """
  Bounded context for discovery: the local watchlist — title-level
  "I want to watch this" intent — and, in later iterations, the candidate
  sources that feed it (TMDB discover, list import, friend recommendations).

  Accepts plain attrs at the boundary (cross-context composition is plain
  data). Scheduled convergence: when this context grows its first
  TMDB-calling source, TMDB title search and a neutral title struct move
  from `ReleaseTracking` into `MediaCentaur.TMDB` and both contexts
  consume them (see the unification notes in
  docs/superpowers/plans/2026-08-18-watchlist-foundation.md).
  """

  import Ecto.Query

  alias MediaCentaur.Discovery.{Events, WatchlistItem}
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to watchlist update events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.discovery_updates())

  @doc """
  Adds a title to the watchlist. Idempotent — re-adding an existing
  `(tmdb_id, media_type)` returns the existing item unchanged.
  """
  def add_to_watchlist(attrs) do
    case get_item(attrs[:tmdb_id], attrs[:media_type]) do
      %WatchlistItem{} = existing ->
        {:ok, existing}

      nil ->
        with {:ok, item} <- attrs |> WatchlistItem.create_changeset() |> Repo.insert() do
          ensure_artwork_async(item)
          Events.broadcast(%Events.ItemAdded{item_id: item.id, tmdb_id: item.tmdb_id, media_type: item.media_type})
          {:ok, item}
        end
    end
  end

  @doc "Removes a title from the watchlist. Absent refs are a no-op."
  @spec remove_from_watchlist(integer(), :movie | :tv_series) :: :ok
  def remove_from_watchlist(tmdb_id, media_type) do
    case get_item(tmdb_id, media_type) do
      nil ->
        :ok

      item ->
        Repo.delete(item)
        Events.broadcast(%Events.ItemRemoved{tmdb_id: tmdb_id, media_type: media_type})
        :ok
    end
  end

  @doc """
  All watchlist items, newest first, each with the owning library
  container's id (nil when the library doesn't know the title) — derived
  live via `Library.ExternalIds.tmdb_owners/1`, never stored.
  """
  @spec list_watchlist() :: [%{item: WatchlistItem.t(), library_owner_id: Ecto.UUID.t() | nil}]
  def list_watchlist do
    items = Repo.all(from(w in WatchlistItem, order_by: [desc: w.inserted_at]))
    owners = ExternalIds.tmdb_owners(Enum.map(items, &{&1.tmdb_id, &1.media_type}))

    Enum.map(items, fn item ->
      %{item: item, library_owner_id: Map.get(owners, {item.tmdb_id, item.media_type})}
    end)
  end

  @spec on_watchlist?(integer(), :movie | :tv_series) :: boolean()
  def on_watchlist?(tmdb_id, media_type), do: not is_nil(get_item(tmdb_id, media_type))

  @doc "The `{tmdb_id, media_type}` ref set — bulk decoration for search rows."
  @spec watchlisted_refs() :: MapSet.t({integer(), :movie | :tv_series})
  def watchlisted_refs do
    Repo.all(from(w in WatchlistItem, select: {w.tmdb_id, w.media_type})) |> MapSet.new()
  end

  defp get_item(tmdb_id, media_type) do
    Repo.one(from(w in WatchlistItem, where: w.tmdb_id == ^tmdb_id and w.media_type == ^media_type))
  end

  # Watchlist items persist, so their artwork moves from TMDB-hotlink to
  # the local referenced tier. Network — context-layer task (ADR-049).
  defp ensure_artwork_async(item) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      TmdbArtwork.ensure(item.media_type, item.tmdb_id)
    end)

    :ok
  end
end
```

**Note for Step 5:** verify TMDB client stubbing in `test/support/tmdb_stubs.ex` covers the detail-fetch `ensure/2` performs; if the async task logs stub warnings in tests (zero-warnings policy), gate `ensure_artwork_async/1` behind the same mechanism ReleaseTracking tests use for artwork (grep `test/media_centaur/release_tracking` for how `download_poster` is silenced) and mirror it.

- [ ] **Step 6: `list_watchlist` requires `ExternalIds.tmdb_owners/1` (Task 3) — stub it first or reorder: implement Task 3 Step 3 before running.** Run `mix test test/media_centaur/discovery_test.exs` → PASS.

- [ ] **Step 7: Commit** — `git commit -m "feat(discovery): watchlist context + typed events"`

---

### Task 3: `Library.ExternalIds.tmdb_owners/1`

**Files:**
- Modify: `lib/media_centaur/library/external_ids.ex`
- Test: `test/media_centaur/library/external_ids_test.exs` (extend; if absent, create)

- [ ] **Step 1: Failing test** (use `MediaCentaur.TestFactory` — `create_standalone_movie/1`, `create_tv_series/1`, `create_external_id/1`; copy attr shapes from existing factory call sites in the library tests)

```elixir
  describe "tmdb_owners/1" do
    test "maps refs to owning container ids; unknown refs are absent" do
      movie = create_standalone_movie()
      create_external_id(%{source: "tmdb", external_id: "777", owner_type: :movie, owner_id: movie.id})

      series = create_tv_series()
      create_external_id(%{source: "tmdb", external_id: "42", owner_type: :tv_series, owner_id: series.id})

      assert ExternalIds.tmdb_owners([{777, :movie}, {42, :tv_series}, {999, :movie}]) ==
               %{{777, :movie} => movie.id, {42, :tv_series} => series.id}
    end

    test "movie and tv ids do not cross-match" do
      movie = create_standalone_movie()
      create_external_id(%{source: "tmdb", external_id: "550", owner_type: :movie, owner_id: movie.id})

      assert ExternalIds.tmdb_owners([{550, :tv_series}]) == %{}
    end
  end
```

- [ ] **Step 2: Run — expect failure** (undefined function).

- [ ] **Step 3: Implement** (in `external_ids.ex`, beside the other bulk helpers)

```elixir
  @doc """
  Bulk "does the library know this TMDB title" — maps each
  `{tmdb_id, media_type}` ref to the owning container's id; refs the
  library has no container for are absent from the result.

  Semantics: *container exists* — deliberately looser than
  `find_present_movie/1`'s file-linked check. Detail pages render
  containers regardless of files, so this is the right authority for
  "link to it" decorations (watchlist, search rows).
  """
  @spec tmdb_owners([{integer(), :movie | :tv_series}]) ::
          %{{integer(), :movie | :tv_series} => Ecto.UUID.t()}
  def tmdb_owners([]), do: %{}

  def tmdb_owners(refs) when is_list(refs) do
    ids = refs |> Enum.map(fn {tmdb_id, _type} -> to_string(tmdb_id) end) |> Enum.uniq()

    lookup =
      from(e in ExternalId,
        where: e.source == "tmdb" and e.owner_type in [:movie, :tv_series] and e.external_id in ^ids,
        select: {e.external_id, e.owner_type, e.owner_id}
      )
      |> Repo.all()
      |> Map.new(fn {external_id, owner_type, owner_id} -> {{external_id, owner_type}, owner_id} end)

    refs
    |> Enum.flat_map(fn {tmdb_id, media_type} = ref ->
      case Map.get(lookup, {to_string(tmdb_id), media_type}) do
        nil -> []
        owner_id -> [{ref, owner_id}]
      end
    end)
    |> Map.new()
  end
```

- [ ] **Step 4: Run tests** — external_ids + discovery tests → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(library): bulk tmdb_owners lookup for TMDB refs"`

---

### Task 4: Artwork hold provider

**Files:**
- Create: `lib/media_centaur/discovery/tmdb_artwork_holds.ex`
- Modify: `config/config.exs:150` (append to `:tmdb_artwork_hold_providers`)
- Test: `test/media_centaur/discovery_test.exs` (extend)

- [ ] **Step 1: Failing test**

```elixir
    test "TmdbArtworkHolds holds every watchlist ref" do
      {:ok, _} = Discovery.add_to_watchlist(@attrs)
      assert MediaCentaur.Discovery.TmdbArtworkHolds.holds() == MapSet.new([{:movie, 777}])
    end
```

- [ ] **Step 2: Implement** (mirror `ReleaseTracking.TmdbArtworkHolds` exactly)

```elixir
defmodule MediaCentaur.Discovery.TmdbArtworkHolds do
  @moduledoc """
  Every watchlist item holds its TMDB artwork cache entry — the item is
  a standing interest in the title, so its artwork never ages out while
  the item exists.
  """
  @behaviour MediaCentaur.TmdbArtwork.HoldProvider

  import Ecto.Query

  alias MediaCentaur.Discovery.WatchlistItem
  alias MediaCentaur.Repo

  @impl true
  def holds do
    from(w in WatchlistItem, select: {w.media_type, w.tmdb_id})
    |> Repo.all()
    |> MapSet.new()
  end
end
```

Config: append `MediaCentaur.Discovery.TmdbArtworkHolds` to the `:tmdb_artwork_hold_providers` list.

- [ ] **Step 3: Run tests → PASS. Commit** — `git commit -m "feat(discovery): artwork hold provider"`

---

### Task 5: `WatchlistAware` on_mount

**Files:**
- Create: `lib/media_centaur_web/live/watchlist_aware.ex`
- Test: covered through host LiveView tests in Tasks 9–10 (no isolated test — it is glue; interaction coverage lives in `*_live_test.exs` per project policy).

- [ ] **Step 1: Implement**

```elixir
defmodule MediaCentaurWeb.Live.WatchlistAware do
  @moduledoc """
  Shared `:watchlisted_refs` lifecycle for any LiveView that renders a
  watchlist affordance (Incoming search rows, the detail modal hosts).
  Subscribes to `discovery:updates`, seeds the ref set, and refreshes it
  on watchlist events — halting them so hosts need no clauses. Hosts
  MUST NOT call `Discovery.subscribe/0` themselves.

  `WatchlistLive` does NOT use this module — it needs the full item list
  and subscribes directly.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias MediaCentaur.Discovery

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Discovery.subscribe()

    socket =
      socket
      |> assign(:watchlisted_refs, Discovery.watchlisted_refs())
      |> attach_hook(:watchlist_refresh, :handle_info, &refresh/2)

    {:cont, socket}
  end

  defp refresh({tag, _event}, socket) when tag in [:watchlist_item_added, :watchlist_item_removed] do
    {:halt, assign(socket, :watchlisted_refs, Discovery.watchlisted_refs())}
  end

  defp refresh(_message, socket), do: {:cont, socket}
end
```

- [ ] **Step 2: Compile clean (`mix compile --warnings-as-errors`). Commit** — `git commit -m "feat(web): WatchlistAware shared lifecycle"`

---

### Task 6: WatchlistRow component + story

**Files:**
- Create: `lib/media_centaur_web/components/discovery/watchlist_row.ex`
- Create: `storybook/discovery/_discovery.index.exs` (mirror `storybook/acquisition/_acquisition.index.exs`)
- Create: `storybook/discovery/watchlist_row.story.exs`
- Modify: `lib/media_centaur_web/components/acquisition/media_results.ex` (generalize `release_status/2`)

- [ ] **Step 1: Generalize `release_status/2`** — relax the two heads in `media_results.ex:250-254` from `%TitleResult{...}` to map-matching so any `%{release_date: Date.t() | nil}` (TitleResult or WatchlistItem) works:

```elixir
  @spec release_status(%{release_date: Date.t() | nil}, Date.t()) :: :released | :upcoming
  def release_status(%{release_date: nil}, _today), do: :upcoming

  def release_status(%{release_date: release_date}, today) do
    if Date.after?(release_date, today), do: :upcoming, else: :released
  end
```

Run `mix test` for media-results/incoming tests — must stay green.

- [ ] **Step 2: Component.** Same visual grammar as a media-search row (poster thumb / identity line / quiet metadata), one state-dependent primary action, quiet Remove. Invoke `user-interface` + `writing-copy` before writing markup; typed attrs per MC0008.

```elixir
defmodule MediaCentaurWeb.Components.Discovery.WatchlistRow do
  @moduledoc """
  One watchlist entry: poster thumb, identity line, provenance note, and
  the single state-dependent primary action — link to the library detail
  when the library knows the title, Download (plan flow) when released
  and an indexer exists, Track release otherwise. Remove is the quiet
  secondary action. Pure rendering; `watchlist_remove` bubbles to the
  host, navigation is by link.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Discovery.WatchlistItem
  alias MediaCentaurWeb.Components.Acquisition.MediaResults

  attr :item, WatchlistItem, required: true
  attr :library_owner_id, :string, default: nil, doc: "owning container id when the library knows the title"
  attr :poster_url, :string, default: nil, doc: "resolved by the host: local TmdbArtwork url or TMDB hotlink"
  attr :release_mode_available, :boolean, required: true
  attr :today, :any, default: nil, doc: "`Date.t()` for the released/upcoming split — nil means today (fixed in stories)."

  def watchlist_row(assigns) do
    today = assigns.today || Date.utc_today()
    assigns = assign(assigns, :status, MediaResults.release_status(assigns.item, today))

    ~H"""
    <div
      id={"watchlist-item-#{@item.media_type}-#{@item.tmdb_id}"}
      class="glass-surface flex w-full items-start gap-4 rounded-xl px-4 py-3"
      data-component="watchlist-row"
    >
      <span class="flex h-[72px] w-12 flex-shrink-0 items-center justify-center overflow-hidden rounded-md bg-base-content/10">
        <img :if={@poster_url} src={@poster_url} alt="" class="h-full w-full object-cover" loading="eager" decoding="sync" />
        <.icon
          :if={!@poster_url}
          name={if @item.media_type == :movie, do: "hero-film-mini", else: "hero-tv-mini"}
          class="size-5 text-base-content/25"
        />
      </span>

      <span class="min-w-0 flex-1 space-y-0.5 self-center">
        <span class="flex items-baseline gap-2">
          <span class="truncate text-sm font-semibold">{@item.name}</span>
          <span class="shrink-0 text-xs text-base-content/50">
            {if @item.media_type == :movie, do: "Movie", else: "TV"}<span :if={@item.year}> · {@item.year}</span>
          </span>
        </span>
        <span :if={@item.note} class="line-clamp-2 block text-xs leading-relaxed text-base-content/55">{@item.note}</span>
        <span :if={!@item.note && @item.overview} class="line-clamp-2 block text-xs leading-relaxed text-base-content/55">
          {@item.overview}
        </span>
      </span>

      <span class="flex shrink-0 items-center gap-3 self-center">
        <.primary_action
          item={@item}
          status={@status}
          library_owner_id={@library_owner_id}
          release_mode_available={@release_mode_available}
        />
        <button
          type="button"
          class="cursor-pointer text-xs text-base-content/30 transition-colors hover:text-base-content/60"
          phx-click="watchlist_remove"
          phx-value-tmdb-id={@item.tmdb_id}
          phx-value-media-type={@item.media_type}
          data-nav-item
          tabindex="0"
        >
          Remove
        </button>
      </span>
    </div>
    """
  end

  attr :item, WatchlistItem, required: true
  attr :status, :atom, required: true, values: [:upcoming, :released]
  attr :library_owner_id, :string, default: nil
  attr :release_mode_available, :boolean, required: true

  defp primary_action(%{library_owner_id: owner_id} = assigns) when not is_nil(owner_id) do
    ~H"""
    <.link
      navigate={"/library?selected=#{@library_owner_id}"}
      class="inline-flex items-center gap-1 text-xs font-medium text-primary/70"
      data-nav-item
      tabindex="0"
    >
      In library <.icon name="hero-chevron-right-mini" class="size-3.5" />
    </.link>
    """
  end

  defp primary_action(%{status: :released, release_mode_available: true} = assigns) do
    ~H"""
    <.link
      navigate={"/incoming?plan=new&tmdb_id=#{@item.tmdb_id}&tmdb_type=#{plan_type(@item.media_type)}"}
      class="inline-flex items-center gap-1 text-xs font-medium text-primary/70"
      data-nav-item
      tabindex="0"
    >
      Download <.icon name="hero-chevron-right-mini" class="size-3.5" />
    </.link>
    """
  end

  defp primary_action(assigns) do
    ~H"""
    <button
      type="button"
      class="inline-flex cursor-pointer items-center gap-1 text-xs font-medium text-primary/70"
      phx-click="watchlist_track"
      phx-value-tmdb-id={@item.tmdb_id}
      phx-value-media-type={@item.media_type}
      data-nav-item
      tabindex="0"
    >
      Track release <.icon name="hero-chevron-right-mini" class="size-3.5" />
    </button>
    """
  end

  defp plan_type(:movie), do: "movie"
  defp plan_type(:tv_series), do: "tv"
end
```

Verify before finalizing: the `/library?selected=` param name against `LibraryLive.apply_modal_params/2` (grep `selected` in `lib/media_centaur_web/live/library_live.ex` — the transient-param list at line ~351 says `selected,view`; confirm the value is the container/entity id our `tmdb_owners/1` returns — if the library grid keys entities by a different id (entry id vs container id), adjust `tmdb_owners` to return whatever id the detail route needs; write the LiveView test in Task 7 against a real factory container to prove the link opens the modal).

- [ ] **Step 3: Story** (`storybook/discovery/watchlist_row.story.exs`) — variations: `:in_library` (library_owner_id set → In library link), `:download` (released + release_mode_available), `:track_release` (upcoming), `:track_only` (released, no indexer), `:with_note` (note shown over overview). Fixed `today: ~D[2026-08-18]`, generic titles (`Sample Movie`, `Sample Show`), fake poster paths with `poster_url: nil` to show the icon fallback. Mirror the attribute-map shape of `storybook/acquisition/media_results.story.exs`.

- [ ] **Step 4: `mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs` → PASS (MC0009 satisfied). Commit** — `git commit -m "feat(discovery): watchlist row component + story"`

---

### Task 7: WatchlistLive page + route + sidebar

**Files:**
- Create: `lib/media_centaur_web/live/watchlist_live.ex`
- Modify: `lib/media_centaur_web/router.ex` (add `live "/watchlist", WatchlistLive, :index` after the `/status` line)
- Modify: `lib/media_centaur_web/components/layouts.ex` (sidebar entry between Library and Incoming)
- Test: `test/media_centaur_web/live/watchlist_live_test.exs`

- [ ] **Step 1: Failing LiveView tests**

```elixir
defmodule MediaCentaurWeb.WatchlistLiveTest do
  use MediaCentaurWeb.ConnCase, async: true

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Discovery

  test "empty watchlist renders the empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/watchlist")
    assert html =~ "watchlist-empty"
  end

  test "renders rows with the honest action per state", %{conn: conn} do
    {:ok, _} = Discovery.add_to_watchlist(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", release_date: ~D[2020-01-01]})
    {:ok, _} = Discovery.add_to_watchlist(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show", release_date: ~D[2999-01-01]})

    movie = create_standalone_movie()
    create_external_id(%{source: "tmdb", external_id: "777", owner_type: :movie, owner_id: movie.id})

    {:ok, _view, html} = live(conn, "/watchlist")
    assert html =~ "In library"
    assert html =~ "Track release"
  end

  test "remove deletes the item live", %{conn: conn} do
    {:ok, _} = Discovery.add_to_watchlist(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
    {:ok, view, _html} = live(conn, "/watchlist")

    view
    |> element("#watchlist-item-movie-777 button", "Remove")
    |> render_click()

    refute has_element?(view, "#watchlist-item-movie-777")
  end

  test "watchlist events refresh the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/watchlist")
    {:ok, _} = Discovery.add_to_watchlist(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
    assert render(view) =~ "Sample Movie"
  end
end
```

- [ ] **Step 2: Run — expect route failure.**

- [ ] **Step 3: Implement LiveView**

```elixir
defmodule MediaCentaurWeb.WatchlistLive do
  @moduledoc """
  The watchlist — title-level intent, triaged. Rows come from
  `Discovery.list_watchlist/0` (library presence derived live); the
  primary action per row is the honest one for its state (see
  `WatchlistRow`). Refreshes on `discovery:updates` and
  `library:updates` (a completed pursuit flips a row to In library
  without a reload).
  """
  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.LiveHelpers, only: [tmdb_cdn_url: 2]

  alias MediaCentaur.Discovery
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.Topics
  alias MediaCentaurWeb.Components.Discovery.WatchlistRow

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Discovery.subscribe()
      Topics.subscribe(Topics.library_updates())
    end

    {:ok, socket |> assign(:page_title, "Watchlist") |> load_items()}
  end

  @impl true
  def handle_event("watchlist_remove", %{"tmdb-id" => tmdb_id, "media-type" => media_type}, socket)
      when media_type in ~w(movie tv_series) do
    Discovery.remove_from_watchlist(String.to_integer(tmdb_id), String.to_existing_atom(media_type))
    {:noreply, socket}
  end

  def handle_event("watchlist_track", %{"tmdb-id" => tmdb_id, "media-type" => media_type}, socket)
      when media_type in ~w(movie tv_series) do
    ref = {String.to_integer(tmdb_id), String.to_existing_atom(media_type)}

    case Enum.find(socket.assigns.items, &(&1.item.tmdb_id == elem(ref, 0) && &1.item.media_type == elem(ref, 1))) do
      nil ->
        {:noreply, socket}

      %{item: item} ->
        ReleaseTracking.track_from_search_async(%{
          tmdb_id: item.tmdb_id,
          media_type: item.media_type,
          name: item.name,
          poster_path: item.poster_path
        })

        {:noreply, put_flash(socket, :info, "Tracking #{item.name} for release.")}
    end
  end

  @impl true
  def handle_info({tag, _event}, socket) when tag in [:watchlist_item_added, :watchlist_item_removed] do
    {:noreply, load_items(socket)}
  end

  def handle_info({:entities_changed, _event}, socket), do: {:noreply, load_items(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_items(socket) do
    items =
      Enum.map(Discovery.list_watchlist(), fn %{item: item} = row ->
        Map.put(row, :poster_url, poster_url(item))
      end)

    assign(socket, :items, items)
  end

  # Referenced-tier artwork when the ensure has landed; TMDB hotlink as
  # the browsing-tier fallback (same ladder as everywhere else).
  defp poster_url(item) do
    TmdbArtwork.urls(item.media_type, item.tmdb_id).poster_url ||
      (item.poster_path && tmdb_cdn_url(item.poster_path, :w92))
  end

  @impl true
  def render(assigns) do
    # [Amended 2026-08-18: shipped as data-nav-default-zone="watchlist", not "grid".]
    ~H"""
    <div class="relative" data-page-behavior="watchlist" data-nav-default-zone="grid">
      <div class="mx-auto w-full max-w-3xl space-y-2 pt-10" data-nav-zone="grid">
        <h1 class="px-1 text-lg font-semibold">Watchlist</h1>

        <div :if={@items == []} id="watchlist-empty" class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/40">
          Nothing on your watchlist yet. Titles you save from a search land here.
        </div>

        <WatchlistRow.watchlist_row
          :for={row <- @items}
          item={row.item}
          library_owner_id={row.library_owner_id}
          poster_url={row.poster_url}
          release_mode_available={@prowlarr_ready}
        />
      </div>
    </div>
    """
  end
end
```

Verify while implementing: `TmdbArtwork.urls/2` arity/shape (`lib/media_centaur/tmdb_artwork.ex` — returns `%{poster_url: _, backdrop_url: _, logo_url: _}`); `@prowlarr_ready` is seeded by the session-wide `CapabilitiesAware` on_mount (it is — `router.ex:22-31`); flash copy through `writing-copy`.

- [ ] **Step 4: Router + sidebar.** Router: `live "/watchlist", WatchlistLive, :index` (alphabetical, after `/status`). Sidebar (`layouts.ex`, between the Library and Incoming links, same markup shape):

```heex
          <.link
            navigate="/watchlist"
            class={sidebar_link_class(@current_path, "/watchlist")}
            data-tip="Watchlist"
            data-nav-item
            data-nav-remember
            tabindex="0"
          >
            <.icon name="hero-bookmark" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Watchlist</span>
          </.link>
```

- [ ] **Step 5: Run tests → PASS.** Also add `/watchlist` to the page smoke test (grep `test/media_centaur_web` for the existing all-pages smoke list — the `automated-testing` skill names it — and append the route).
- [ ] **Step 6: Commit** — `git commit -m "feat(watchlist): /watchlist page, route, sidebar entry"`

---

### Task 8: Input-system registration

**Files:**
- Modify: `assets/js/input/config.js` (zones map + `cursorStartPriority`)
- Create: `assets/js/input/watchlist_behavior.js` (copy the shape of `watch_history_behavior.js`)
- Modify: `assets/js/input/page_behavior.js` (import + registry entry — no `withWipNotice` wrapper; the page ships complete)
- Test: `assets/js/input/__tests__/` — run `bun test assets/js` and update any config-shape tests that enumerate pages.

- [ ] **Step 1:** config.js zones (after the `watch_history` block):

```js
    watchlist: {
      grid:    { left: ["sidebar"] },
      sidebar: { right: ["grid"] },
    },
```

and `cursorStartPriority`: `watchlist: ["grid", "sidebar"],`

- [ ] **Step 2:** `watchlist_behavior.js` mirroring `watch_history_behavior.js` (read it first; expected to be a thin `createXBehavior` returning zone defaults). Register in `page_behavior.js` as `"watchlist": () => createWatchlistBehavior()`.
- [ ] **Step 3:** `mix assets.build` (dev watchers are OFF), `bun test assets/js` → PASS, `mix boundaries` (dependency-cruiser) → PASS.
- [ ] **Step 4:** Runtime verify with `mc-nav-trace` against the dev server: arrows reach the rows and sidebar from `/watchlist`.
- [ ] **Step 5: Commit** — `git commit -m "feat(watchlist): input-system navigation"`

---

### Task 9: Search-row watchlist action (+ in-library marker)

**Files:**
- Modify: `lib/media_centaur_web/components/acquisition/media_results.ex`
- Modify: `storybook/acquisition/media_results.story.exs`
- Modify: `lib/media_centaur_web/live/incoming_live.ex`
- Test: `test/media_centaur_web/live/incoming_live_test.exs` (extend)

- [ ] **Step 1: Failing test** (locate the existing omnibox/media-search tests in `incoming_live_test.exs` and extend beside them; use their setup for getting `@omnibox_results` populated — TMDB stubbed via `tmdb_stubs.ex`)

```elixir
  test "search row watchlist toggle adds then removes", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/incoming")
    # drive the omnibox to results using the existing test helper/pattern in this file
    search_media(view, "sample")

    view |> element("[id^='omnibox-watchlist-']") |> render_click()
    assert [{_, _}] = MediaCentaur.Discovery.watchlisted_refs() |> MapSet.to_list()

    view |> element("[id^='omnibox-watchlist-']") |> render_click()
    assert MediaCentaur.Discovery.watchlisted_refs() == MapSet.new()
  end
```

(`search_media/2` = whatever idiom the existing media-mode tests use; copy it, don't invent one.)

- [ ] **Step 2: Component changes.** `media_results/1` gains two attrs:

```elixir
  attr :watchlisted_refs, :any, default: MapSet.new(), doc: "`{tmdb_id, media_type}` refs on the watchlist."
  attr :in_library_refs, :any, default: MapSet.new(), doc: "`{tmdb_id, media_type}` refs the library has a container for."
```

`result_row` gains `watchlisted?` / `in_library?` boolean attrs (computed in the `:for` via `MapSet.member?(@watchlisted_refs, {result.tmdb_id, result.media_type})` etc.). Restructure the row — the whole row is currently one `<button>`; nested interactive elements are invalid — into a wrapper `<div class="glass-surface flex w-full items-start gap-4 rounded-xl">` containing (a) the existing main `<button phx-click="omnibox_pick">` reduced to `flex-1` with its id and inner content unchanged, and (b) a sibling bookmark toggle:

```heex
      <button
        id={"omnibox-watchlist-#{@result.media_type}-#{@result.tmdb_id}"}
        type="button"
        class={[
          "cursor-pointer self-center px-2 py-2 transition-colors",
          @watchlisted? && "text-primary",
          !@watchlisted? && "text-base-content/30 hover:text-base-content/60"
        ]}
        phx-click="watchlist_toggle"
        phx-value-tmdb-id={@result.tmdb_id}
        phx-value-media-type={@result.media_type}
        aria-pressed={to_string(@watchlisted?)}
        title={if @watchlisted?, do: "Remove from watchlist", else: "Add to watchlist"}
        data-nav-item
        tabindex="0"
      >
        <.icon name={if @watchlisted?, do: "hero-bookmark-solid", else: "hero-bookmark"} class="size-4" />
      </button>
```

In-library marker: next to the `Tracked` marker, `<span :if={@in_library?} class="shrink-0 text-xs text-base-content/50">In library</span>` (quiet text, not color — color stays reserved for state/health). Verify the hero icon names exist (`grep -r "hero-bookmark" assets/ lib/` — CoreComponents' icon set; if the solid variant isn't available use `hero-bookmark` + fill styling per the `user-interface` skill).

- [ ] **Step 3: IncomingLive wiring.** `use`/on_mount `MediaCentaurWeb.Live.WatchlistAware` (adds `:watchlisted_refs`); compute `:in_library_refs` wherever `@omnibox_results` is assigned (find the assign site — the omnibox search result handler): `ExternalIds.tmdb_owners(Enum.map(results, &{&1.tmdb_id, &1.media_type})) |> Map.keys() |> MapSet.new()`. Pass both attrs at the `MediaResults.media_results` call site (`incoming_live.ex:954`). Toggle handler (beside `omnibox_pick`):

```elixir
  def handle_event("watchlist_toggle", %{"tmdb-id" => tmdb_id, "media-type" => media_type}, socket)
      when media_type in ~w(movie tv_series) do
    ref = {String.to_integer(tmdb_id), String.to_existing_atom(media_type)}

    if MapSet.member?(socket.assigns.watchlisted_refs, ref) do
      Discovery.remove_from_watchlist(elem(ref, 0), elem(ref, 1))
    else
      case Enum.find(socket.assigns.omnibox_results, &({&1.tmdb_id, &1.media_type} == ref)) do
        nil ->
          :ok

        result ->
          Discovery.add_to_watchlist(%{
            tmdb_id: result.tmdb_id,
            media_type: result.media_type,
            name: result.name,
            year: result.year,
            release_date: result.release_date,
            poster_path: result.poster_path,
            overview: result.overview
          })
      end
    end

    {:noreply, socket}
  end
```

(No assign update here — the WatchlistAware PubSub hook refreshes `:watchlisted_refs`, proving the event loop.)

- [ ] **Step 4: Story update** — add `watchlisted_refs` / `in_library_refs` to the existing variations (e.g. mark `{777, :movie}` watchlisted and `{246_810, :tv_series}` in library in the `:results` variation) and extend the `:results` description to name the bookmark toggle + In library marker.
- [ ] **Step 5: Run** incoming_live tests + storybook tests → PASS. Real-browser check on the dev server (memory: green `render_click` ≠ working control): click the bookmark on a real search, confirm the icon flips and the row lands on `/watchlist`.
- [ ] **Step 6: Commit** — `git commit -m "feat(incoming): watchlist toggle + in-library marker on media search rows"`

---

### Task 10: Detail-modal watchlist toggle

**Files:**
- Modify: `lib/media_centaur_web/components/detail/view_controls.ex`
- Modify: `lib/media_centaur_web/live/entity_modal.ex` (injected handler + snapshot helper)
- Modify: `lib/media_centaur_web/live/library_live.ex` + `lib/media_centaur_web/live/home_live.ex` (adopt `WatchlistAware`)
- Modify: the view_controls story under `storybook/detail*` (locate via `grep -rl view_controls storybook/`)
- Test: `test/media_centaur_web/live/library_live_test.exs` (extend)

- [ ] **Step 1: Verify the entity view-model vocabulary.** `grep -n "type:" lib/media_centaur_web/components/detail/logic.ex | head` and grep for where `@entity[:tmdb_id]` is built. Expected: subject types include `:movie` and a TV-series type (`:tv_series` or `:series` — use what's actually there) and `tmdb_id` is a **string**. Confirm the entity map carries `name`/`title` and `year` fields for the snapshot; note their actual keys.

- [ ] **Step 2: Failing test** in `library_live_test.exs` (beside the existing detail-modal tests, reusing their open-the-modal setup): open a movie's detail, click `#detail-watchlist-toggle`, assert `Discovery.on_watchlist?(tmdb_id, :movie)`; click again, assert removed.

- [ ] **Step 3: view_controls button** (next to the Letterboxd link, `view_controls.ex:86`; gate on the verified type vocabulary — both movie and TV, unlike Letterboxd's movie-only):

```heex
    <button
      :if={@entity[:tmdb_id] && @entity.type in [:movie, :tv_series]}
      id="detail-watchlist-toggle"
      type="button"
      class={[
        "cursor-pointer transition-colors",
        @watchlisted? && "text-primary",
        !@watchlisted? && "text-base-content/40 hover:text-base-content/70"
      ]}
      phx-click="modal_watchlist_toggle"
      aria-pressed={to_string(@watchlisted?)}
      title={if @watchlisted?, do: "Remove from watchlist", else: "Add to watchlist"}
      data-nav-item
      tabindex="0"
    >
      <.icon name={if @watchlisted?, do: "hero-bookmark-solid", else: "hero-bookmark"} class="size-4" />
    </button>
```

with `attr :watchlisted?, :boolean, default: false` — match the surrounding view_controls markup conventions (read the Letterboxd link's classes and mirror them; the block above is the shape, the classes defer to what's there).

- [ ] **Step 4: EntityModal.** Inject one clause among the existing modal `handle_event`s and add a public helper:

```elixir
      def handle_event("modal_watchlist_toggle", _params, socket) do
        {:noreply, MediaCentaurWeb.Live.EntityModal.toggle_watchlist(socket)}
      end
```

```elixir
  @doc """
  Adds/removes the selected entity's title on the watchlist, resolving
  the snapshot from `:selected_entry`. No assign update — hosts carry
  `:watchlisted_refs` via `WatchlistAware`, refreshed by the event.
  """
  def toggle_watchlist(socket) do
    entity = socket.assigns.selected_entry
    tmdb_id = String.to_integer(entity.tmdb_id)
    media_type = watchlist_media_type(entity.type)

    if MapSet.member?(socket.assigns.watchlisted_refs, {tmdb_id, media_type}) do
      MediaCentaur.Discovery.remove_from_watchlist(tmdb_id, media_type)
    else
      MediaCentaur.Discovery.add_to_watchlist(%{
        tmdb_id: tmdb_id,
        media_type: media_type,
        name: entity.name,
        year: entity[:year]
      })
    end

    socket
  end
```

Adjust field access (`entity.tmdb_id` vs `entity[:tmdb_id]`, `name` vs `title`, the type mapping in `watchlist_media_type/1`) to what Step 1 found. Pass `watchlisted?` down from the modal render into `view_controls` (`MapSet.member?(@watchlisted_refs, …)` computed where view_controls is called). `use MediaCentaurWeb.Live.WatchlistAware` in LibraryLive and HomeLive.

- [ ] **Step 5: Story update** for view_controls (new `watchlisted?` attr — one variation on, one off). Run library_live + home_live + storybook tests → PASS. Real-browser check: toggle from a detail panel, row appears on `/watchlist` with the In library link.
- [ ] **Step 6: Commit** — `git commit -m "feat(detail): watchlist toggle in view controls"`

---

### Task 11: Ship-out — precommit, changelog, wiki, campaign

- [ ] **Step 1:** `mix precommit` — fix everything (zero warnings; Boundary check will validate the new Discovery deps; Credo MC0009 confirms stories).
- [ ] **Step 2:** Flake check on the new LiveView tests: `mix test test/media_centaur_web/live/watchlist_live_test.exs --repeat-until-failure 20`.
- [ ] **Step 3:** CHANGELOG entry (user-facing, `writing-copy` voice; mention the new table migration per the safe-migration-per-release rule). "Watchlist" is the user-facing term; code says `WatchlistItem` (guide vocabulary: user copy "entry" applies to library entries, not here).
- [ ] **Step 4:** Wiki (`~/src/media-centaur/media-centaur.wiki`): add a Watchlist section to the *Using Media Centaur* flow pages (saving from search, the detail toggle, the three row actions); commit + push the wiki per its own git flow.
- [ ] **Step 5:** Update `campaigns/friends-recommendations.md` status note if wording is now stale, and `decisions/README.md` only if an ADR was added (none planned — Discovery's contracts live in moduledocs per the moduledoc-first rule).
- [ ] **Step 6:** Final commit. Do **not** push or tag — freshly built work ships only on explicit say-so.

---

## Self-review notes (already applied)

- Spec coverage: schema/API/artwork (Tasks 1–4), Aware + surfaces (5–10), liveness (7 §mount, 5, 9), testing (throughout + smoke + flake check), migration safety + wiki (11). Out-of-scope items from the spec stay out.
- Task 2/3 ordering dependency is called out explicitly (Task 2 Step 6).
- Types consistent: `{tmdb_id :: integer, media_type :: :movie | :tv_series}` refs everywhere; DOM values are strings and converted at each handler boundary; `tmdb_owners/1` compares stringified ids against `ExternalId.external_id`.
- Deliberate verify-first steps (entity view-model fields, `/library?selected=` id, icon names, behavior-js shape) are marked with expected findings — they are verification steps with concrete fallbacks, not placeholders.

---

## Release note draft

*(Drafted at ship-out 2026-08-18. CHANGELOG.md has no Unreleased section — entries are written per-release by the /ship flow, which should pick this up.)*

### New

- **Save titles for later with the watchlist.** A bookmark button on media-search results and on a title's detail panel saves it to the new **Watchlist** page in the sidebar. Each saved row offers the action its state calls for: **Download** opens the plan flow, **Track release** follows an upcoming title, and titles already in your library are marked **In library** and link to their page. Remove takes a row off the list. Search results now also mark titles you already have. This update adds a new database table, migrated automatically.
