# Plan 001 — Foundation

> **Status:** Pending
> **Created:** 2026-02-20
> **Scope:** Add core dependencies, implement Config GenServer, Ash resources, Watcher GenServer, and JsonWriter GenServer. Smoke test: drop a file → `WatchedFile` with `:detected` state appears in SQLite.

---

## Context

This is the Freedia Center `media-manager` — a Phoenix/Elixir application that is the write-side of the media center system. It watches a configured `media_dir` for new video files, scrapes TMDB metadata, and maintains `media.json` in a `shared_library_dir` that the `user-interface` reads.

**Key design decisions (see `DESIGN.md` for full detail):**

- **SQLite is canonical.** `media.json` is a derived export. SQLite database lives at `~/.local/share/freedia-center/media-manager.db`.
- **Ash framework** (already in `mix.exs`) is used for all SQLite resources via `ash_sqlite`.
- **Config** is read from `~/.config/freedia-center/media-manager.toml` (TOML format) and merged over runtime env defaults.
- **Mount resilience:** `media_dir` and `shared_library_dir` may be on removable/network drives. Never remove library data based on a raw deletion event without confirming the drive is healthy.
- **Broadway pipeline** processes file additions through stages: parse → search TMDB → route → fetch metadata → download images → write JSON.
- **`:file_system`** library (wraps inotify) watches `media_dir`.

**Relevant files to read before implementing:**

- `DESIGN.md` — full architecture (in this repo)
- `AGENTS.md` — Elixir/Phoenix/Ash/LiveView coding rules (in this repo)
- `../specifications/DATA-FORMAT.md` — `media.json` format
- `../specifications/IMAGE-CACHING.md` — image path conventions

---

## Goal

After this plan is implemented and verified, the following smoke test must pass:

1. Drop any video file (`.mkv`, `.mp4`, `.avi`) into the configured `media_dir`.
2. A `WatchedFile` record appears in SQLite with `state: :detected` and the correct `file_path`.
3. Dashboard at `http://localhost:4000` shows the new item in the activity feed.
4. Unmounting `media_dir` shows a red warning banner on the dashboard.
5. `media.json` can be regenerated from SQLite via `MediaManager.JsonWriter.regenerate_all()` (produces a valid empty array `[]` if no completed entities yet).

---

## Step-by-Step Implementation

### Step 1 — Add Dependencies

Edit `mix.exs`. Add to the `deps` list:

```elixir
{:file_system, "~> 1.0"},
{:broadway, "~> 1.1"},
{:toml, "~> 0.7"},
```

Then run:

```bash
mix deps.get
```

**Notes:**
- Use `toml` (hex package `toml`) not `toml_elixir` — `toml` is the maintained hex package.
- `:file_system` wraps inotify on Linux; ensure it is in `extra_applications` if needed.

---

### Step 2 — Create `defaults/media-manager.toml`

Create the `defaults/` directory and write `defaults/media-manager.toml`. This file is git-tracked and ships with the repo. It must contain **every** configuration key recognised by `MediaManager.Config`, with a logical default value and a comment for each. It is never written to at runtime — the running app reads user config from `~/.config/freedia-center/media-manager.toml` and falls back to compiled application env defaults.

```toml
# defaults/media-manager.toml
#
# Shipped default configuration for Freedia Center — Media Manager.
# Copy this file to ~/.config/freedia-center/media-manager.toml and edit as needed.
# This file must contain every recognised config key; keep it up to date as new
# keys are added to MediaManager.Config.

# Directory containing video/media files (e.g. torrent downloads folder).
# Watched for additions and removals. May be on a removable or network drive.
media_dir = "/mnt/videos/Videos"

# Shared library directory: media.json lives here + images/ subdirectory.
# Must match the path the user-interface is configured to read from.
# May be on a removable or network drive.
shared_library_dir = "~/.local/share/freedia-center/data"

[tmdb]
# TMDB API key. Required for metadata scraping. Get one at https://www.themoviedb.org/settings/api
api_key = ""

[pipeline]
# Confidence score threshold (0.0–1.0). Matches at or above this score are
# written automatically. Below it, the item is queued for human review.
auto_approve_threshold = 0.85
```

This is the canonical reference for what keys exist. When adding a new config key in a future plan, update this file at the same time.

---

### Step 3 — Runtime Configuration Defaults

Edit `config/runtime.exs`. Add at the top of the file (before any existing `if config_env() == :prod` block):

```elixir
config :media_manager,
  media_dir: System.get_env("MEDIA_DIR", "/mnt/videos/Videos"),
  shared_library_dir:
    System.get_env(
      "SHARED_LIBRARY_DIR",
      Path.expand("~/.local/share/freedia-center/data")
    ),
  tmdb_api_key: System.get_env("TMDB_API_KEY", ""),
  auto_approve_threshold: 0.85
```

---

### Step 4 — `MediaManager.Config` GenServer

**File:** `lib/media_manager/config.ex`

A GenServer that:
1. Reads `~/.config/freedia-center/media-manager.toml` on `init/1` (non-fatal if missing).
2. Merges TOML values over the compiled application env defaults.
3. Stores the merged map in its state.
4. Exposes `MediaManager.Config.get(:key)` for retrieving values.

```elixir
defmodule MediaManager.Config do
  use GenServer

  @config_path "~/.config/freedia-center/media-manager.toml"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @impl true
  def init(_) do
    config = load_config()
    {:ok, config}
  end

  @impl true
  def handle_call({:get, key}, _from, config) do
    {:reply, Map.get(config, key), config}
  end

  defp load_config do
    defaults = %{
      media_dir: Application.get_env(:media_manager, :media_dir),
      shared_library_dir: Application.get_env(:media_manager, :shared_library_dir),
      tmdb_api_key: Application.get_env(:media_manager, :tmdb_api_key),
      auto_approve_threshold: Application.get_env(:media_manager, :auto_approve_threshold)
    }

    path = Path.expand(@config_path)

    case File.read(path) do
      {:ok, contents} ->
        case Toml.decode(contents) do
          {:ok, toml} -> merge_toml(defaults, toml)
          {:error, _} -> defaults
        end

      {:error, _} ->
        defaults
    end
  end

  defp merge_toml(defaults, toml) do
    %{
      media_dir: get_in(toml, ["media_dir"]) || defaults.media_dir,
      shared_library_dir: get_in(toml, ["shared_library_dir"]) || defaults.shared_library_dir,
      tmdb_api_key: get_in(toml, ["tmdb", "api_key"]) || defaults.tmdb_api_key,
      auto_approve_threshold:
        get_in(toml, ["pipeline", "auto_approve_threshold"]) || defaults.auto_approve_threshold
    }
  end
end
```

Add `MediaManager.Config` to the supervision tree in `lib/media_manager/application.ex` **before** any other children that depend on config.

---

### Step 5 — Ash Domain and Resources

**Domain file:** `lib/media_manager/library.ex`

```elixir
defmodule MediaManager.Library do
  use Ash.Domain

  resources do
    resource MediaManager.Library.Entity
    resource MediaManager.Library.WatchedFile
    resource MediaManager.Library.Image
    resource MediaManager.Library.Identifier
    resource MediaManager.Library.Season
    resource MediaManager.Library.Episode
  end
end
```

Add the domain to `config/config.exs`:

```elixir
config :media_manager, :ash_domains, [MediaManager.Library]
```

#### 5a — `MediaManager.Library.Entity`

**File:** `lib/media_manager/library/entity.ex`

Fields (all optional except `id` and `type`):

| Ash attribute | Type | Notes |
|---------------|------|-------|
| `id` | `:uuid_primary_key` | stable `@id` for `media.json` |
| `type` | `:atom` in `[:movie, :tv_series, :video_object]` | |
| `name` | `:string` | |
| `description` | `:string` | |
| `date_published` | `:string` | year or ISO date |
| `genres` | `{:array, :string}` | |
| `content_url` | `:string` | local playback path |
| `url` | `:string` | remote info page |
| `duration` | `:string` | ISO 8601 |
| `director` | `:string` | movies |
| `content_rating` | `:string` | movies |
| `number_of_seasons` | `:integer` | TVSeries |
| `aggregate_rating_value` | `:float` | |
| `pending_write` | `:boolean`, default `false` | write queued but not yet persisted to disk |
| `inserted_at` | `:utc_datetime_usec` | |
| `updated_at` | `:utc_datetime_usec` | |

Relationships:
- `has_many :images, MediaManager.Library.Image`
- `has_many :identifiers, MediaManager.Library.Identifier`
- `has_many :seasons, MediaManager.Library.Season`
- `has_many :watched_files, MediaManager.Library.WatchedFile`

Actions: standard CRUD (`create`, `read`, `update`, `destroy`), plus a custom `read` action `:with_associations` that loads images, identifiers, seasons (with episodes).

#### 5b — `MediaManager.Library.WatchedFile`

**File:** `lib/media_manager/library/watched_file.ex`

Fields:

| Ash attribute | Type | Notes |
|---------------|------|-------|
| `id` | `:uuid_primary_key` | |
| `file_path` | `:string` | unique; used for removal lookup |
| `entity_id` | `:uuid` | FK → Entity; nil until Stage 4 |
| `parsed_title` | `:string` | |
| `parsed_year` | `:integer` | |
| `parsed_type` | `:atom` in `[:movie, :tv, :unknown]` | |
| `season_number` | `:integer` | TV episode files |
| `episode_number` | `:integer` | TV episode files |
| `tmdb_id` | `:string` | |
| `confidence_score` | `:float` | |
| `state` | `:atom` in state machine values | see below |
| `error_message` | `:string` | |
| `inserted_at` | `:utc_datetime_usec` | |
| `updated_at` | `:utc_datetime_usec` | |

State machine values (in order):
`:detected`, `:searching`, `:pending_review`, `:approved`, `:fetching_metadata`, `:fetching_images`, `:complete`, `:error`, `:removed`

Relationships:
- `belongs_to :entity, MediaManager.Library.Entity`

Actions: standard CRUD plus a custom `create` action `:detect` that accepts `file_path`, sets `state: :detected`.

#### 5c — `MediaManager.Library.Image`

**File:** `lib/media_manager/library/image.ex`

Fields: `id` (uuid pk), `entity_id` (uuid FK), `role` (string), `url` (string), `content_url` (string), `extension` (string), timestamps.

Relationships: `belongs_to :entity, MediaManager.Library.Entity`

#### 5d — `MediaManager.Library.Identifier`

**File:** `lib/media_manager/library/identifier.ex`

Fields: `id` (uuid pk), `entity_id` (uuid FK), `property_id` (string), `value` (string), timestamps.

Relationships: `belongs_to :entity, MediaManager.Library.Entity`

#### 5e — `MediaManager.Library.Season`

**File:** `lib/media_manager/library/season.ex`

Fields: `id` (uuid pk), `entity_id` (uuid FK), `season_number` (integer), `number_of_episodes` (integer), `name` (string, optional), timestamps.

Relationships:
- `belongs_to :entity, MediaManager.Library.Entity`
- `has_many :episodes, MediaManager.Library.Episode`

#### 5f — `MediaManager.Library.Episode`

**File:** `lib/media_manager/library/episode.ex`

Fields: `id` (uuid pk), `season_id` (uuid FK), `episode_number` (integer), `name` (string), `description` (string), `duration` (string), `content_url` (string), timestamps.

Relationships:
- `belongs_to :season, MediaManager.Library.Season`
- `has_many :images, MediaManager.Library.Image`

---

### Step 6 — AshSqlite Configuration

Edit `config/config.exs` to configure AshSqlite:

```elixir
config :media_manager, MediaManager.Repo,
  database: Path.expand("~/.local/share/freedia-center/media-manager.db")
```

Ensure `MediaManager.Repo` is configured as an AshSqlite repo. Check `lib/media_manager/repo.ex` — it should already exist from the Phoenix generator; update it to use `AshSqlite.Repo`:

```elixir
defmodule MediaManager.Repo do
  use AshSqlite.Repo, otp_app: :media_manager
end
```

Run migrations:

```bash
mix ash.codegen initial_resources
mix ash.migrate
```

This generates and runs the initial Ash migrations for all six resources.

---

### Step 7 — `MediaManager.Watcher` GenServer

**File:** `lib/media_manager/watcher.ex`

A GenServer that:
1. Starts `:file_system` watching on `media_dir` recursively.
2. Implements the state machine: `:initializing` → `:watching` → `:media_dir_unavailable` → `:reconciling` → `:watching`.
3. Broadcasts state changes via `Phoenix.PubSub` to topic `"watcher:state"`.
4. On `:file_added` events: checks file extension (`.mkv`, `.mp4`, `.avi`, `.mov`, `.wmv`, `.m4v`) and file size stability (poll every 5 seconds until size is stable for two consecutive checks), then creates a `WatchedFile` with `:detected` state via `MediaManager.Library.WatchedFile`.
5. On `:file_removed` events: gates on mount health before forwarding.
6. Runs a periodic 30-second health check via `Process.send_after/3`.
7. Handles `[:unmounted]` events from `:file_system`.

**Burst detection:** maintain a counter of removal events in the last 2 seconds using a sliding window. If ≥50 in 2 seconds, broadcast a `:suspicious_burst` alert.

**Key functions:**
- `MediaManager.Watcher.start_link/1`
- `MediaManager.Watcher.state/0` — returns current state atom
- `MediaManager.Watcher.media_dir_healthy?/0` — returns boolean

**Skeleton:**

```elixir
defmodule MediaManager.Watcher do
  use GenServer
  require Logger

  @video_extensions ~w(.mkv .mp4 .avi .mov .wmv .m4v .ts .m2ts)
  @health_check_interval 30_000
  @size_stability_interval 5_000
  @size_stability_checks 2

  defstruct [
    :media_dir,
    :watcher_pid,
    state: :initializing,
    removal_timestamps: [],
    pending_files: %{}
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def state, do: GenServer.call(__MODULE__, :state)
  def media_dir_healthy?, do: GenServer.call(__MODULE__, :media_dir_healthy)

  @impl true
  def init(_opts) do
    media_dir = MediaManager.Config.get(:media_dir)
    send(self(), :start_watching)
    {:ok, %__MODULE__{media_dir: media_dir}}
  end

  # ... handle_info callbacks for :start_watching, {:file_event, ...},
  #     :health_check, {:check_size, path}, etc.
end
```

Add `MediaManager.Watcher` to the supervision tree in `application.ex` **after** `MediaManager.Config`.

---

### Step 8 — `MediaManager.JsonWriter` GenServer

**File:** `lib/media_manager/json_writer.ex`

A singleton GenServer that serialises all writes to `media.json`.

**Key functions:**

- `MediaManager.JsonWriter.write_entity(entity_id)` — generates and writes a single entity's JSON entry (update-or-append).
- `MediaManager.JsonWriter.remove_entity(entity_id)` — removes an entity from `media.json`.
- `MediaManager.JsonWriter.regenerate_all()` — rewrites `media.json` from scratch from all `:complete` `WatchedFile` entities in SQLite. Returns `:ok`.

**Write flow for `write_entity/1`:**

1. Load entity from SQLite with all associations.
2. Encode to schema.org JSON map (per `DATA-FORMAT.md`).
3. Read current `media.json` at `shared_library_dir/media.json` (or `[]` if missing/invalid).
4. Find entry by `"@id"` matching `entity.id`; replace or append.
5. Encode full list to JSON.
6. Write to `shared_library_dir/media.json.tmp`.
7. `File.rename("media.json.tmp", "media.json")` — atomic on Linux.
8. On `{:error, _}` from any file operation → set `entity.pending_write = true` in SQLite, schedule retry.

**Pending write retry:** on `:shared_library_dir_available` PubSub event (broadcast by Watcher when it detects the dir is accessible), flush all entities with `pending_write: true`.

**Skeleton:**

```elixir
defmodule MediaManager.JsonWriter do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def write_entity(entity_id) do
    GenServer.call(__MODULE__, {:write_entity, entity_id})
  end

  def remove_entity(entity_id) do
    GenServer.call(__MODULE__, {:remove_entity, entity_id})
  end

  def regenerate_all do
    GenServer.call(__MODULE__, :regenerate_all)
  end

  @impl true
  def init(_) do
    # Subscribe to PubSub for shared_library_dir availability
    Phoenix.PubSub.subscribe(MediaManager.PubSub, "watcher:state")
    {:ok, %{}}
  end

  # ... handle_call callbacks
end
```

For this plan, `write_entity` can be a stub that logs but does not yet encode full schema.org JSON — full encoding is implemented in a later plan after the Ash resources are confirmed working.

`regenerate_all/0` must be fully functional: it queries all entities that have at least one `WatchedFile` with `state: :complete`, then writes their JSON. Since no entities will be `:complete` at this stage, it should produce `[]` in `media.json`.

Add `MediaManager.JsonWriter` to the supervision tree **after** `MediaManager.Config`.

---

### Step 9 — Update Application Supervision Tree

Edit `lib/media_manager/application.ex`. The children list should start with:

```elixir
children = [
  MediaManagerWeb.Telemetry,
  MediaManager.Repo,
  {DNSCluster, query: Application.get_env(:media_manager, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: MediaManager.PubSub},
  MediaManager.Config,       # must be first; others depend on config
  MediaManager.JsonWriter,   # before Watcher; Watcher may trigger writes
  MediaManager.Watcher,      # after Config and JsonWriter
  {Finch, name: MediaManager.Finch},
  MediaManagerWeb.Endpoint
]
```

---

### Step 10 — Dashboard LiveView Skeleton

Create a minimal Dashboard LiveView at `lib/media_manager_web/live/dashboard_live.ex`:

```elixir
defmodule MediaManagerWeb.DashboardLive do
  use MediaManagerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MediaManager.PubSub, "watcher:state")
    end

    {:ok,
     assign(socket,
       watcher_state: MediaManager.Watcher.state(),
       recent_files: []
     )}
  end

  @impl true
  def handle_info({:watcher_state_changed, new_state}, socket) do
    {:noreply, assign(socket, watcher_state: new_state)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <%= if @watcher_state == :media_dir_unavailable do %>
        <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          Media directory not accessible — removal events suppressed
        </div>
      <% end %>
      <h1 class="text-2xl font-bold mb-4">Media Manager</h1>
      <p>Watcher state: <strong><%= @watcher_state %></strong></p>
    </div>
    """
  end
end
```

Add route in `lib/media_manager_web/router.ex`:

```elixir
live "/", DashboardLive, :index
```

(Replace any existing `get "/"` route.)

---

### Step 11 — Verify with `mix precommit`

Run:

```bash
mix precommit
```

Fix all warnings and errors. The key things to verify:

- All six Ash resources compile without warnings.
- `MediaManager.Config`, `MediaManager.Watcher`, `MediaManager.JsonWriter` all compile.
- `mix test` passes (existing tests should still pass; no new tests required for this plan).
- `mix format` produces no diff.

---

## Smoke Test

After completing all steps, verify manually:

1. **Start the server:**
   ```bash
   mix phx.server
   ```

2. **Confirm watcher starts:** Check logs for `[info] Watcher: started watching /your/media_dir`.

3. **Drop a test file:**
   ```bash
   cp /dev/null /your/media_dir/Test.Movie.2024.1080p.mkv
   # Wait ~15 seconds for size-stability heuristic
   ```

4. **Check SQLite:**
   ```elixir
   # In iex -S mix:
   MediaManager.Library.WatchedFile |> Ash.read!() |> Enum.map(& &1.state)
   # Should include :detected
   ```

5. **Check dashboard:** Open `http://localhost:4000` — should show watcher state `:watching`.

6. **Regenerate test:**
   ```elixir
   MediaManager.JsonWriter.regenerate_all()
   # Check shared_library_dir/media.json — should contain []
   ```

7. **Mount resilience test:**
   - Unmount `media_dir` (or simulate by making it inaccessible)
   - Dashboard should show red warning banner within 30 seconds (next health check)

---

## Files Created / Modified

| File | Action |
|------|--------|
| `mix.exs` | Add `:file_system`, `:broadway`, `:toml` deps |
| `defaults/media-manager.toml` | New — shipped default config; every key documented |
| `config/runtime.exs` | Add `media_manager` config defaults |
| `config/config.exs` | Add `ash_domains`, AshSqlite repo config |
| `lib/media_manager/application.ex` | Update supervision tree |
| `lib/media_manager/repo.ex` | Update to use `AshSqlite.Repo` |
| `lib/media_manager/config.ex` | New — TOML config GenServer |
| `lib/media_manager/library.ex` | New — Ash domain |
| `lib/media_manager/library/entity.ex` | New — Entity resource |
| `lib/media_manager/library/watched_file.ex` | New — WatchedFile resource |
| `lib/media_manager/library/image.ex` | New — Image resource |
| `lib/media_manager/library/identifier.ex` | New — Identifier resource |
| `lib/media_manager/library/season.ex` | New — Season resource |
| `lib/media_manager/library/episode.ex` | New — Episode resource |
| `lib/media_manager/watcher.ex` | New — mount-resilient Watcher GenServer |
| `lib/media_manager/json_writer.ex` | New — atomic JSON writer GenServer |
| `lib/media_manager_web/live/dashboard_live.ex` | New — Dashboard LiveView |
| `lib/media_manager_web/router.ex` | Add `live "/"` route |
| `priv/repo/migrations/` | Generated by `mix ash.codegen` + `mix ash.migrate` |

---

## Notes on Ash Usage

- Use `use Ash.Resource, domain: MediaManager.Library, data_layer: AshSqlite.DataLayer` in each resource.
- Declare `sqlite do ... end` block with `table "watched_files"` etc.
- Use `uuid_primary_key :id` for all resources.
- Use `create_timestamp :inserted_at` and `update_timestamp :updated_at`.
- For atom enums, use `attribute :state, :atom, constraints: [one_of: [...]]`.
- Relationships between resources use `belongs_to` / `has_many` as normal Ash relationships.
- The `ash.codegen` task generates migrations; `ash.migrate` runs them.

Refer to `AGENTS.md` for project-specific Ash coding conventions.
