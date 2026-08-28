# Apps Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An "Apps" main-nav section — a fire-and-forget launcher for external applications (Steam games + manual commands), per the approved spec `docs/superpowers/specs/2026-08-28-apps-launcher-design.md`.

**Architecture:** New `MediaCentaur.Apps` bounded context (uniform App rows filled by add-time importers). Artwork follows the TmdbArtwork idiom: disk-as-ledger under `{data_dir}/images/apps/{app_id}/`, served by the existing ImageServer. UI is a banner-card grid LiveView at `/apps`, nav entry gated by a `show_apps` preference (Watchlist precedent).

**Tech Stack:** Phoenix LiveView, Ecto (SQLite), Boundary, Phoenix Storybook, bun (input-system JS tests).

**House rules that bind every task:** test-first (red before green), zero warnings, `MediaCentaur.TestFactory` for persistence in tests, no real game titles in fixtures (generic placeholders), no network in tests, MC0024 (`has_element?` not `=~` for attributes), commit after each task.

---

### Task 1: Migration + `Apps.App` schema + context CRUD

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_apps.exs` (generate with `mix ecto.gen.migration add_apps`)
- Create: `lib/media_centaur/apps/app.ex`
- Create: `lib/media_centaur/apps.ex`
- Modify: `lib/media_centaur_web.ex` (add `MediaCentaur.Apps` to the Boundary `deps:` list)
- Test: `test/media_centaur/apps_test.exs`
- Modify: `test/support/factory.ex` (add `create_app/1`)

- [ ] **Step 1: Write the failing context test**

```elixir
defmodule MediaCentaur.AppsTest do
  use MediaCentaur.DataCase

  import MediaCentaur.TestFactory

  alias MediaCentaur.Apps

  describe "add_app/1" do
    test "creates an app with name, command, and origin" do
      assert {:ok, app} =
               Apps.add_app(%{
                 name: "Sample Game",
                 command: "sample-game --fullscreen",
                 origin: %{"source" => "manual"}
               })

      assert app.name == "Sample Game"
      assert app.command == "sample-game --fullscreen"
      assert app.origin == %{"source" => "manual"}
    end

    test "requires name and command" do
      assert {:error, changeset} = Apps.add_app(%{})
      assert %{name: ["can't be blank"], command: ["can't be blank"]} = errors_on(changeset)
    end

    test "re-adding the same steam origin returns the existing app" do
      {:ok, first} =
        Apps.add_app(%{
          name: "Sample Game",
          command: "steam steam://rungameid/100",
          origin: %{"source" => "steam", "app_id" => 100}
        })

      assert {:ok, second} =
               Apps.add_app(%{
                 name: "Sample Game Renamed",
                 command: "steam steam://rungameid/100",
                 origin: %{"source" => "steam", "app_id" => 100}
               })

      assert second.id == first.id
      assert Apps.list_apps() |> length() == 1
    end
  end

  describe "list_apps/0" do
    test "sorts alphabetically by name, case-insensitive" do
      create_app(%{name: "zebra tool"})
      create_app(%{name: "Alpha Game"})
      create_app(%{name: "beta App"})

      assert Enum.map(Apps.list_apps(), & &1.name) == ["Alpha Game", "beta App", "zebra tool"]
    end
  end

  describe "added_steam_ids/0" do
    test "returns the set of steam app ids already added" do
      create_app(%{origin: %{"source" => "steam", "app_id" => 100}})
      create_app(%{name: "Manual One", origin: %{"source" => "manual"}})

      assert Apps.added_steam_ids() == MapSet.new([100])
    end
  end

  describe "update_app/2" do
    test "updates name and command" do
      app = create_app(%{})
      assert {:ok, updated} = Apps.update_app(app, %{name: "New Name", command: "new-cmd"})
      assert updated.name == "New Name"
      assert updated.command == "new-cmd"
    end
  end

  describe "remove_app/1" do
    test "deletes the row" do
      app = create_app(%{})
      assert :ok = Apps.remove_app(app)
      assert Apps.list_apps() == []
    end
  end
end
```

- [ ] **Step 2: Add the factory builder** (in `test/support/factory.ex`, alongside the other `create_*` helpers — grep for `def create_movie` to find the section):

```elixir
@doc "Persists an app (launcher entry) via the Apps context."
def create_app(attrs) do
  defaults = %{
    name: "Sample App #{System.unique_integer([:positive])}",
    command: "sample-app",
    origin: %{"source" => "manual"}
  }

  {:ok, app} = MediaCentaur.Apps.add_app(Map.merge(defaults, attrs))
  app
end
```

- [ ] **Step 3: Run the test — expect compile failure** (`MediaCentaur.Apps` undefined): `mix test test/media_centaur/apps_test.exs`

- [ ] **Step 4: Generate and write the migration** (`mix ecto.gen.migration add_apps`):

```elixir
defmodule MediaCentaur.Repo.Migrations.AddApps do
  use Ecto.Migration

  def change do
    create table(:apps, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :command, :text, null: false
      add :origin, :map, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
```

- [ ] **Step 5: Write the schema** (`lib/media_centaur/apps/app.ex`):

```elixir
defmodule MediaCentaur.Apps.App do
  @moduledoc """
  A launchable entry in the Apps launcher — name, one-line shell command,
  and provenance.

  Every app has the same shape regardless of how it was added; add-methods
  (the Steam picker, the manual form) resolve to these fields at add time.
  `origin` records provenance for dedup and artwork refresh:

    * `%{"source" => "steam", "app_id" => 413150}` — added via the Steam picker
    * `%{"source" => "manual"}` — typed into the manual form

  Artwork is not stored here — disk is the ledger (see
  `MediaCentaur.Apps.Artwork`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "apps" do
    field :name, :string
    field :command, :string
    field :origin, :map, default: %{}

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :command, :origin])
    |> validate_required([:name, :command])
  end

  def update_changeset(app, attrs) do
    app
    |> cast(attrs, [:name, :command])
    |> validate_required([:name, :command])
  end
end
```

- [ ] **Step 6: Write the context facade** (`lib/media_centaur/apps.ex`). `Artwork.delete/1` arrives in Task 4 — for this task `remove_app/1` only deletes the row; Task 4 adds the artwork cleanup line.

```elixir
defmodule MediaCentaur.Apps do
  use Boundary,
    deps: [MediaCentaur.Settings, MediaCentaur.Library],
    exports: [App]

  @moduledoc """
  Bounded context for the Apps launcher — user-curated external
  applications (Steam games, emulators, anything with a shell command)
  launched fire-and-forget from the UI.

  An `App` is a uniform row (see `MediaCentaur.Apps.App`); add-methods are
  importers that fill it at add time. Launching knows nothing about
  sources — one code path (`MediaCentaur.Apps.Launcher`).
  """

  import Ecto.Query

  alias MediaCentaur.Apps.App
  alias MediaCentaur.Repo

  @doc "All apps, alphabetical by name (case-insensitive)."
  @spec list_apps() :: [App.t()]
  def list_apps do
    Repo.all(from(a in App, order_by: fragment("lower(?)", a.name)))
  end

  @spec get_app!(Ecto.UUID.t()) :: App.t()
  def get_app!(id), do: Repo.get!(App, id)

  @doc """
  Adds an app. Idempotent per steam origin — re-adding an existing
  `%{"source" => "steam", "app_id" => id}` returns the existing app
  unchanged.
  """
  @spec add_app(map()) :: {:ok, App.t()} | {:error, Ecto.Changeset.t()}
  def add_app(attrs) do
    case existing_by_origin(attrs[:origin] || attrs["origin"]) do
      %App{} = existing -> {:ok, existing}
      nil -> attrs |> App.create_changeset() |> Repo.insert()
    end
  end

  @spec update_app(App.t(), map()) :: {:ok, App.t()} | {:error, Ecto.Changeset.t()}
  def update_app(%App{} = app, attrs) do
    app |> App.update_changeset(attrs) |> Repo.update()
  end

  @spec remove_app(App.t()) :: :ok
  def remove_app(%App{} = app) do
    Repo.delete(app)
    :ok
  end

  @doc "Steam app ids already added — the picker marks these."
  @spec added_steam_ids() :: MapSet.t(integer())
  def added_steam_ids do
    list_apps()
    |> Enum.filter(&(&1.origin["source"] == "steam"))
    |> MapSet.new(& &1.origin["app_id"])
  end

  defp existing_by_origin(%{"source" => "steam", "app_id" => app_id}) do
    Enum.find(list_apps(), fn app ->
      app.origin["source"] == "steam" and app.origin["app_id"] == app_id
    end)
  end

  defp existing_by_origin(_origin), do: nil
end
```

- [ ] **Step 7: Migrate the test DB and run** — `mix ecto.migrate && mix test test/media_centaur/apps_test.exs`. Expected: PASS. (`App.t()` has no `@type` — add `@type t :: %__MODULE__{}` to the schema if the compiler warns on the specs.)

- [ ] **Step 8: Add `MediaCentaur.Apps` to the web boundary** — in `lib/media_centaur_web.ex`, add `MediaCentaur.Apps` to the `use Boundary, deps: [...]` list (alphabetical position).

- [ ] **Step 9: Commit** — `git add -A && git commit -m "feat(apps): Apps context — schema, CRUD, steam-origin dedup"`

---

### Task 2: `Apps.Launcher` — detached fire-and-forget spawn

**Files:**
- Create: `lib/media_centaur/apps/launcher.ex`
- Test: `test/media_centaur/apps/launcher_test.exs`
- Modify: `lib/media_centaur/apps.ex` (delegate `launch/1`)

Check first: `MediaCentaur.Log` component tags — grep `lib/media_centaur/log.ex` for the allowed component list; if tags are a closed set, add `:apps` to it in this task.

- [ ] **Step 1: Write the failing test** (pure spec construction only — never actually spawn; ADR-030 extraction):

```elixir
defmodule MediaCentaur.Apps.LauncherTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Apps.Launcher

  describe "spawn_spec/1" do
    test "wraps the command in a detached setsid + sh invocation" do
      assert Launcher.spawn_spec("sample-app --flag") ==
               {"setsid", ["-f", "sh", "-c", "sample-app --flag"]}
    end

    test "passes the command through as a single opaque string" do
      command = ~s(env FOO="a b" sample-app 'quoted arg' && echo done)
      assert {"setsid", ["-f", "sh", "-c", ^command]} = Launcher.spawn_spec(command)
    end
  end
end
```

- [ ] **Step 2: Run — expect failure** (module undefined): `mix test test/media_centaur/apps/launcher_test.exs`

- [ ] **Step 3: Implement** (`lib/media_centaur/apps/launcher.ex`):

```elixir
defmodule MediaCentaur.Apps.Launcher do
  @moduledoc """
  Fire-and-forget launching of an app's shell command.

  `setsid -f` forks the command into its own session: the intermediate
  process exits immediately, the port closes, and the launched app
  survives Media Centaur restarts. There is no session tracking — for
  Steam URIs the spawned process exits at once anyway (the Steam client
  owns the game), so identical fire-and-forget semantics for every app
  is the only honest contract.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Apps.App

  @doc "The `{executable, argv}` pair `launch/1` spawns. Pure — unit-tested."
  @spec spawn_spec(String.t()) :: {String.t(), [String.t()]}
  def spawn_spec(command) do
    {"setsid", ["-f", "sh", "-c", command]}
  end

  @doc "Spawns the app's command detached. Returns `:ok` or `{:error, :launcher_unavailable}`."
  @spec launch(App.t()) :: :ok | {:error, :launcher_unavailable}
  def launch(%App{} = app) do
    {executable, args} = spawn_spec(app.command)

    case System.find_executable(executable) do
      nil ->
        Log.warning(:apps, "launch failed for #{app.name} — #{executable} not on PATH")
        {:error, :launcher_unavailable}

      path ->
        Port.open({:spawn_executable, to_charlist(path)}, [:binary, args: args])
        Log.info(:apps, "launched #{app.name}")
        :ok
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**: `mix test test/media_centaur/apps/launcher_test.exs`

- [ ] **Step 5: Delegate from the facade** — add to `lib/media_centaur/apps.ex` (and `Launcher` to the alias block; do NOT export `Launcher` — the web layer calls `Apps.launch/1`):

```elixir
@doc "Launches an app fire-and-forget. See `MediaCentaur.Apps.Launcher`."
@spec launch(App.t()) :: :ok | {:error, :launcher_unavailable}
defdelegate launch(app), to: MediaCentaur.Apps.Launcher
```

- [ ] **Step 6: Commit** — `git commit -am "feat(apps): detached fire-and-forget launcher"`

---

### Task 3: Steam discovery — VDF pairs, manifests, commands, art lookup

**Files:**
- Create: `lib/media_centaur/apps/steam.ex`
- Test: `test/media_centaur/apps/steam_test.exs`

All functions take an explicit `root` path so tests build Steam layouts in tmp dirs. `detect_root/0` alone touches the real filesystem.

- [ ] **Step 1: Write the failing tests**:

```elixir
defmodule MediaCentaur.Apps.SteamTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Apps.Steam

  defp tmp_steam_root(context_name) do
    root = Path.join(System.tmp_dir!(), "mc-steam-#{context_name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "steamapps"))
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp write_manifest(root, app_id, name) do
    File.write!(Path.join([root, "steamapps", "appmanifest_#{app_id}.acf"]), """
    "AppState"
    {
    \t"appid"\t\t"#{app_id}"
    \t"name"\t\t"#{name}"
    \t"installdir"\t\t"#{name}"
    }
    """)
  end

  describe "string_pairs/1" do
    test "extracts quoted key-value pairs from VDF text" do
      vdf = ~s("AppState"\n{\n\t"appid"\t\t"100"\n\t"name"\t\t"Sample Game"\n})
      pairs = Steam.string_pairs(vdf)
      assert {"appid", "100"} in pairs
      assert {"name", "Sample Game"} in pairs
    end

    test "handles escaped quotes inside values" do
      assert [{"name", ~s(Sample \\"Quoted\\" Game)}] = Steam.string_pairs(~s("name" "Sample \\"Quoted\\" Game"))
    end
  end

  describe "installed_games/1" do
    test "lists games from appmanifest files across library folders" do
      root = tmp_steam_root("games")
      write_manifest(root, 100, "Sample Game")

      extra = Path.join(root, "extra-library")
      File.mkdir_p!(Path.join(extra, "steamapps"))
      write_manifest(extra, 200, "Movie Tie-In Game")

      File.write!(Path.join([root, "steamapps", "libraryfolders.vdf"]), """
      "libraryfolders"
      {
      \t"0"
      \t{
      \t\t"path"\t\t"#{root}"
      \t}
      \t"1"
      \t{
      \t\t"path"\t\t"#{extra}"
      \t}
      }
      """)

      games = Steam.installed_games(root)
      assert %{app_id: 100, name: "Sample Game"} in games
      assert %{app_id: 200, name: "Movie Tie-In Game"} in games
    end

    test "works without a libraryfolders.vdf (root steamapps only)" do
      root = tmp_steam_root("novdf")
      write_manifest(root, 100, "Sample Game")
      assert [%{app_id: 100, name: "Sample Game"}] = Steam.installed_games(root)
    end

    test "filters runtimes and redistributables" do
      root = tmp_steam_root("filter")
      write_manifest(root, 228_980, "Steamworks Common Redistributables")
      write_manifest(root, 1_628_350, "Steam Linux Runtime 3.0 (sniper)")
      write_manifest(root, 2_348_590, "Proton 8.0")
      write_manifest(root, 100, "Sample Game")

      assert [%{app_id: 100}] = Steam.installed_games(root)
    end

    test "sorts by name" do
      root = tmp_steam_root("sort")
      write_manifest(root, 2, "Zebra Game")
      write_manifest(root, 1, "Alpha Game")
      assert ["Alpha Game", "Zebra Game"] = Enum.map(Steam.installed_games(root), & &1.name)
    end
  end

  describe "command_for/2" do
    test "native install launches via the steam binary" do
      assert Steam.command_for(100, "/home/user/.local/share/Steam") ==
               "steam steam://rungameid/100"
    end

    test "flatpak install launches via flatpak run" do
      root = "/home/user/.var/app/com.valvesoftware.Steam/.local/share/Steam"
      assert Steam.command_for(100, root) ==
               "flatpak run com.valvesoftware.Steam steam://rungameid/100"
    end
  end

  describe "local_art_path/3" do
    test "finds art in the flat librarycache layout" do
      root = tmp_steam_root("flat-art")
      cache = Path.join([root, "appcache", "librarycache"])
      File.mkdir_p!(cache)
      File.write!(Path.join(cache, "100_header.jpg"), "jpg")

      assert Steam.local_art_path(root, 100, :banner) == Path.join(cache, "100_header.jpg")
      assert Steam.local_art_path(root, 100, :poster) == nil
    end

    test "finds art in the per-appid librarycache layout" do
      root = tmp_steam_root("dir-art")
      cache = Path.join([root, "appcache", "librarycache", "100"])
      File.mkdir_p!(cache)
      File.write!(Path.join(cache, "library_600x900.jpg"), "jpg")

      assert Steam.local_art_path(root, 100, :poster) == Path.join(cache, "library_600x900.jpg")
    end
  end

  describe "cdn_art_url/2" do
    test "builds the store asset URL per role" do
      assert Steam.cdn_art_url(100, :banner) ==
               "https://shared.steamstatic.com/store_item_assets/steam/apps/100/header.jpg"

      assert Steam.cdn_art_url(100, :poster) ==
               "https://shared.steamstatic.com/store_item_assets/steam/apps/100/library_600x900.jpg"
    end
  end
end
```

- [ ] **Step 2: Run — expect failure**: `mix test test/media_centaur/apps/steam_test.exs`

- [ ] **Step 3: Implement** (`lib/media_centaur/apps/steam.ex`):

```elixir
defmodule MediaCentaur.Apps.Steam do
  @moduledoc """
  Steam add-method: discovers installed games and resolves them to
  uniform App attributes (command + artwork) at add time.

  Reads Steam's on-disk state directly — `steamapps/libraryfolders.vdf`
  for library folders, `appmanifest_*.acf` per installed game. Both are
  VDF text; `string_pairs/1` is a tolerant flat extraction of quoted
  key-value pairs (no recursive parser — the keys we need are unique
  per file).

  All functions take the Steam root explicitly; `detect_root/0` probes
  the conventional install locations (native, XDG, flatpak).
  """

  @roots [
    ".steam/steam",
    ".local/share/Steam",
    ".var/app/com.valvesoftware.Steam/.local/share/Steam"
  ]

  # Non-game manifests Steam installs alongside games.
  @non_game_name ~r/^(Steamworks Common Redistributables|Steam Linux Runtime|Proton)/

  @art_files %{banner: "header.jpg", poster: "library_600x900.jpg"}
  @flat_art_files %{banner: "header.jpg", poster: "library_600x900.jpg"}
  @cdn "https://shared.steamstatic.com/store_item_assets/steam/apps"

  @doc "First conventional Steam root that exists, or nil."
  @spec detect_root() :: String.t() | nil
  def detect_root do
    home = System.user_home()
    home && Enum.find(Enum.map(@roots, &Path.join(home, &1)), &File.dir?/1)
  end

  @doc "Flat list of `{key, value}` string pairs in a VDF document."
  @spec string_pairs(String.t()) :: [{String.t(), String.t()}]
  def string_pairs(content) do
    ~r/"((?:\\.|[^"\\])*)"\s+"((?:\\.|[^"\\])*)"/
    |> Regex.scan(content)
    |> Enum.map(fn [_all, key, value] -> {key, value} end)
  end

  @doc "Installed games across all library folders, sorted by name."
  @spec installed_games(String.t()) :: [%{app_id: integer(), name: String.t()}]
  def installed_games(root) do
    root
    |> library_folders()
    |> Enum.flat_map(&folder_games/1)
    |> Enum.uniq_by(& &1.app_id)
    |> Enum.reject(&Regex.match?(@non_game_name, &1.name))
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  @doc "The launch command for a game — flatpak-aware, resolved at add time."
  @spec command_for(integer(), String.t()) :: String.t()
  def command_for(app_id, root) do
    if String.contains?(root, ".var/app/com.valvesoftware.Steam") do
      "flatpak run com.valvesoftware.Steam steam://rungameid/#{app_id}"
    else
      "steam steam://rungameid/#{app_id}"
    end
  end

  @doc """
  Path to locally-cached Steam art for a role, or nil. Checks both
  librarycache layouts: per-appid subdirectory (current Steam) and the
  legacy flat `{appid}_header.jpg` naming.
  """
  @spec local_art_path(String.t(), integer(), :banner | :poster) :: String.t() | nil
  def local_art_path(root, app_id, role) do
    cache = Path.join([root, "appcache", "librarycache"])

    candidates = [
      Path.join([cache, to_string(app_id), Map.fetch!(@art_files, role)]),
      Path.join(cache, "#{app_id}_#{Map.fetch!(@flat_art_files, role)}")
    ]

    Enum.find(candidates, &File.regular?/1)
  end

  @doc "Steam CDN fallback URL for a role's art."
  @spec cdn_art_url(integer(), :banner | :poster) :: String.t()
  def cdn_art_url(app_id, role) do
    "#{@cdn}/#{app_id}/#{Map.fetch!(@art_files, role)}"
  end

  defp library_folders(root) do
    vdf = Path.join([root, "steamapps", "libraryfolders.vdf"])

    extra =
      case File.read(vdf) do
        {:ok, content} ->
          for {"path", path} <- string_pairs(content), File.dir?(path), do: path

        {:error, _reason} ->
          []
      end

    Enum.uniq([root | extra])
  end

  defp folder_games(folder) do
    [folder, "steamapps", "appmanifest_*.acf"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.flat_map(fn manifest ->
      case File.read(manifest) do
        {:ok, content} -> manifest_game(content)
        {:error, _reason} -> []
      end
    end)
  end

  defp manifest_game(content) do
    pairs = Map.new(string_pairs(content))

    with %{"appid" => id_string, "name" => name} <- pairs,
         {app_id, ""} <- Integer.parse(id_string) do
      [%{app_id: app_id, name: name}]
    else
      _mismatch -> []
    end
  end
end
```

Note: `@flat_art_files` duplicates `@art_files` today — collapse to one attribute; it exists in the test only to document that both layouts use the same filenames *except* the flat layout prefixes `{appid}_`. Use a single `@art_files` in the real implementation.

- [ ] **Step 4: Run — expect PASS**: `mix test test/media_centaur/apps/steam_test.exs`

- [ ] **Step 5: Commit** — `git commit -am "feat(apps): Steam discovery — manifests, launch commands, art lookup"`

---### Task 4: `Apps.Artwork` — disk-as-ledger cache + ImageServer banner stem

**Files:**
- Create: `lib/media_centaur/apps/artwork.ex`
- Modify: `lib/media_centaur/apps.ex` (`remove_app/1` deletes art; add `add_steam_app/2`; `urls/1` passthrough)
- Modify: `lib/media_centaur_web/plugs/image_server.ex` (add `"banner"` placeholder stem)
- Test: `test/media_centaur/apps/artwork_test.exs`
- Test: `test/media_centaur_web/plugs/image_server_test.exs` (append a banner-stem case; find the existing placeholder test to mirror)

Before writing: read `lib/media_centaur/image_files.ex` `download/3` head to confirm test-env isolation (`:image_downloader` Noop per ADR-016). The CDN fallback goes through it; local-copy is plain `File.cp`. Check how existing tests override `Config.get(:data_dir)` (grep `test/` for `data_dir` — follow that pattern; it's a `:persistent_term`-backed Config override, so the test must be sync DataCase or manage cleanup, and GlobalStateSandbox restores it).

- [ ] **Step 1: Write the failing tests**:

```elixir
defmodule MediaCentaur.Apps.ArtworkTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Apps.Artwork

  setup do
    data_dir = Path.join(System.tmp_dir!(), "mc-apps-art-#{System.unique_integer([:positive])}")
    File.mkdir_p!(data_dir)
    # Follow the existing Config-override pattern found in step 0 —
    # GlobalStateSandbox restores the baseline after each sync test.
    MediaCentaur.Settings.Config.put_test_override(:data_dir, data_dir)
    on_exit(fn -> File.rm_rf!(data_dir) end)
    %{data_dir: data_dir}
  end

  test "urls/1 resolves only roles that exist on disk", %{data_dir: data_dir} do
    app_id = Ecto.UUID.generate()
    dir = Path.join([data_dir, "images", "apps", app_id])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "banner.jpg"), "jpg")

    assert %{banner_url: "/media-images/images/apps/" <> _rest, poster_url: nil} =
             Artwork.urls(app_id)
  end

  test "urls/1 is all-nil for an app with no art" do
    assert %{banner_url: nil, poster_url: nil} = Artwork.urls(Ecto.UUID.generate())
  end

  test "store_file/3 copies a source file into the cache", %{data_dir: data_dir} do
    app_id = Ecto.UUID.generate()
    source = Path.join(data_dir, "source.jpg")
    File.write!(source, "jpg-bytes")

    assert :ok = Artwork.store_file(:banner, app_id, source)
    assert File.read!(Path.join([data_dir, "images", "apps", app_id, "banner.jpg"])) == "jpg-bytes"
  end

  test "delete/1 removes the app's art directory", %{data_dir: data_dir} do
    app_id = Ecto.UUID.generate()
    dir = Path.join([data_dir, "images", "apps", app_id])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "banner.jpg"), "jpg")

    assert :ok = Artwork.delete(app_id)
    refute File.dir?(dir)
  end
end
```

If `Config.put_test_override/2` doesn't exist under that name, use whatever the existing data_dir-overriding test uses verbatim — do not invent a new override mechanism.

- [ ] **Step 2: Run — expect failure**: `mix test test/media_centaur/apps/artwork_test.exs`

- [ ] **Step 3: Implement** (`lib/media_centaur/apps/artwork.ex`):

```elixir
defmodule MediaCentaur.Apps.Artwork do
  @moduledoc """
  App artwork cache — the Apps instance of the app-wide non-library
  artwork idiom (see `MediaCentaur.TmdbArtwork`): identity-keyed
  directory under `data_dir`, disk as the ledger, URLs resolved from
  disk at read time, served by `MediaCentaurWeb.Plugs.ImageServer` with
  the `?w=` derivative ladder.

  Layout: `{data_dir}/images/apps/{app_id}/banner.jpg` (460×215 Steam
  header — the card art) and `poster.jpg` (600×900 capsule — cached at
  add time for a future poster view). No TTL, no holds: app art is
  permanent while its app exists and is deleted synchronously with it.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.ImageFiles
  alias MediaCentaur.Library.Image
  alias MediaCentaur.Settings.Config

  @subdir "images/apps"
  @filenames %{banner: "banner.jpg", poster: "poster.jpg"}

  @type role :: :banner | :poster

  @doc "The data_dir-relative path for a role — what ImageServer serves."
  @spec relative_path(role(), String.t()) :: String.t()
  def relative_path(role, app_id) do
    Path.join([@subdir, app_id, Map.fetch!(@filenames, role)])
  end

  @spec on_disk_path(role(), String.t()) :: String.t()
  def on_disk_path(role, app_id), do: Path.join(data_dir(), relative_path(role, app_id))

  @doc "Web URLs for the roles that exist on disk; missing roles are nil."
  @spec urls(String.t()) :: %{banner_url: String.t() | nil, poster_url: String.t() | nil}
  def urls(app_id) do
    %{banner_url: role_url(:banner, app_id), poster_url: role_url(:poster, app_id)}
  end

  @doc "Copies a local file (e.g. Steam's librarycache art) into the cache."
  @spec store_file(role(), String.t(), String.t()) :: :ok | {:error, term()}
  def store_file(role, app_id, source_path) do
    dest = on_disk_path(role, app_id)
    File.mkdir_p!(Path.dirname(dest))

    case File.cp(source_path, dest) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Downloads a URL into the cache via the shared ImageFiles service."
  @spec store_url(role(), String.t(), String.t()) :: :ok | {:error, term()}
  def store_url(role, app_id, url) do
    case ImageFiles.download_raw(url, on_disk_path(role, app_id)) do
      {:ok, _path} -> :ok
      {:error, _category, reason} -> {:error, reason}
    end
  end

  @doc "Removes the app's art directory and any derivatives. Idempotent."
  @spec delete(String.t()) :: :ok
  def delete(app_id) do
    dir = Path.join([data_dir(), @subdir, app_id])

    case File.ls(dir) do
      {:ok, files} -> Enum.each(files, &ImageFiles.purge_derivatives_for(Path.join(dir, &1)))
      {:error, _reason} -> :ok
    end

    File.rm_rf(dir)
    :ok
  end

  defp role_url(role, app_id) do
    if File.exists?(on_disk_path(role, app_id)) do
      Image.web_path(relative_path(role, app_id))
    end
  end

  defp data_dir, do: Config.get(:data_dir) || "data"
end
```

(Confirm `ImageFiles.download_raw/2`'s error shape — the grep showed `download/3` and `download_raw/2`; if `download_raw` returns 2-tuples, adjust the case. If the app art dir may not exist when `delete/1` runs, `File.rm_rf` already tolerates that.)

- [ ] **Step 4: Run — expect PASS**, then add the facade orchestration to `lib/media_centaur/apps.ex`:

```elixir
@doc """
Adds a Steam game: resolves the launch command, inserts the row, and
caches both art shapes — local Steam librarycache copy first, CDN
fallback async (network stays off the caller per ADR-049).
"""
@spec add_steam_app(%{app_id: integer(), name: String.t()}, String.t()) ::
        {:ok, App.t()} | {:error, Ecto.Changeset.t()}
def add_steam_app(%{app_id: app_id, name: name}, steam_root) do
  attrs = %{
    name: name,
    command: Steam.command_for(app_id, steam_root),
    origin: %{"source" => "steam", "app_id" => app_id}
  }

  with {:ok, app} <- add_app(attrs) do
    cache_steam_artwork(app, app_id, steam_root)
    {:ok, app}
  end
end

@doc "Web URLs for an app's cached artwork. See `MediaCentaur.Apps.Artwork`."
defdelegate artwork_urls(app_id), to: Artwork, as: :urls

defp cache_steam_artwork(app, steam_app_id, steam_root) do
  for role <- [:banner, :poster],
      is_nil(Artwork.urls(app.id)[:"#{role}_url"]) do
    case Steam.local_art_path(steam_root, steam_app_id, role) do
      nil ->
        Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
          Artwork.store_url(role, app.id, Steam.cdn_art_url(steam_app_id, role))
        end)

      local_path ->
        Artwork.store_file(role, app.id, local_path)
    end
  end

  :ok
end
```

Also change `remove_app/1` to clean the cache:

```elixir
def remove_app(%App{} = app) do
  Repo.delete(app)
  Artwork.delete(app.id)
  :ok
end
```

Add aliases (`Apps.{App, Artwork, Steam}`) and extend the existing `remove_app` test: create art dir under the overridden data_dir, assert it's gone after `remove_app` (that test moves to sync DataCase with the same setup as ArtworkTest). Add a facade test for `add_steam_app/2` using a tmp steam root with librarycache art (local-copy path — no network):

```elixir
test "add_steam_app/2 resolves command and caches local art", %{data_dir: _} do
  root = Path.join(System.tmp_dir!(), "mc-steam-add-#{System.unique_integer([:positive])}")
  cache = Path.join([root, "appcache", "librarycache", "100"])
  File.mkdir_p!(cache)
  File.write!(Path.join(cache, "header.jpg"), "banner-bytes")
  File.write!(Path.join(cache, "library_600x900.jpg"), "poster-bytes")
  on_exit(fn -> File.rm_rf!(root) end)

  assert {:ok, app} = Apps.add_steam_app(%{app_id: 100, name: "Sample Game"}, root)
  assert app.command == "steam steam://rungameid/100"
  assert %{banner_url: banner, poster_url: poster} = Apps.artwork_urls(app.id)
  assert is_binary(banner) and is_binary(poster)
end
```

- [ ] **Step 5: ImageServer banner stem** — append to the existing plug test a case mirroring its placeholder tests (find the file; if none exists, add `test/media_centaur_web/plugs/image_server_test.exs` with a ConnCase request to `/media-images/images/apps/nope/banner.jpg` asserting a 200 SVG whose viewBox is `0 0 320 150`), then in `lib/media_centaur_web/plugs/image_server.ex`:
  - `@placeholder_dims` gains `"banner" => {320, 150}`
  - `role_from_filename/1` gains `"banner" -> "banner"`

- [ ] **Step 6: Run the full Apps + plug tests — expect PASS**: `mix test test/media_centaur/apps test/media_centaur/apps_test.exs test/media_centaur_web/plugs/image_server_test.exs`

- [ ] **Step 7: Commit** — `git commit -am "feat(apps): disk-ledger artwork cache + steam add orchestration"`

---

### Task 5: `show_apps` preference — module, router, Settings UI

**Files:**
- Create: `lib/media_centaur/settings/preferences/apps_visibility.ex`
- Modify: `lib/media_centaur/settings/preferences.ex` (exports)
- Modify: `lib/media_centaur_web/router.ex` (SettingAware tuple)
- Modify: `lib/media_centaur_web/live/settings_live/preferences.ex` (attr + row)
- Modify: `lib/media_centaur_web/live/settings_live.ex` (toggle handler + pass-through of `show_apps` to the Preferences component — find where `show_watchlist` is passed and mirror it)
- Test: extend `test/media_centaur_web/live/settings_live_test.exs` (mirror the existing `toggle_show_watchlist` test — grep for it; if none exists, add one)

- [ ] **Step 1: Write the failing test** (in `settings_live_test.exs`, mirroring the watchlist toggle test's exact shape — same helpers, same assertions style):

```elixir
test "toggle_show_apps flips the preference", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/settings")

  refute MediaCentaur.Settings.Preferences.AppsVisibility.enabled?()
  render_click(element(view, "[phx-click='toggle_show_apps']"))
  assert MediaCentaur.Settings.Preferences.AppsVisibility.enabled?()
end
```

- [ ] **Step 2: Run — expect failure** (module undefined).

- [ ] **Step 3: Implement the preference module**:

```elixir
defmodule MediaCentaur.Settings.Preferences.AppsVisibility do
  @moduledoc """
  Typed accessor for the `show_apps` Settings entry.

  Controls whether the Apps launcher surfaces in the sidebar.
  Default-**off**: most installs are pure media centers; the launcher is
  opted into via Settings → Preferences. Only the nav entry is gated —
  `/apps` stays reachable by URL.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "show_apps", default: false
end
```

- [ ] **Step 4: Wire the four sites**:
  1. `preferences.ex` exports list: add `AppsVisibility` (alphabetical).
  2. `router.ex` `on_mount` list — add after the watchlist tuple:
     ```elixir
     {MediaCentaurWeb.Live.SettingAware,
      {MediaCentaur.Settings.Preferences.AppsVisibility, :show_apps, :setting_aware_show_apps}}
     ```
  3. `settings_live/preferences.ex`: `attr :show_apps, :boolean, required: true` and after the Watchlist row:
     ```heex
     <.settings_row
       label="Apps"
       description="Show the Apps launcher in the sidebar"
       checked={@show_apps}
       event="toggle_show_apps"
       color="info"
     />
     ```
  4. `settings_live.ex`: pass `show_apps={@show_apps}` where the Preferences component is rendered, and add the handler next to `toggle_show_watchlist`:
     ```elixir
     def handle_event("toggle_show_apps", _params, socket) do
       enabled = !socket.assigns.show_apps

       Settings.find_or_create_entry!(%{
         key: MediaCentaur.Settings.Preferences.AppsVisibility.setting_key(),
         value: %{"enabled" => enabled}
       })

       {:noreply, assign(socket, show_apps: enabled)}
     end
     ```

- [ ] **Step 5: Run — expect PASS**: `mix test test/media_centaur_web/live/settings_live_test.exs`

- [ ] **Step 6: Commit** — `git commit -am "feat(apps): show_apps preference, settings toggle, session-wide assign"`

---

### Task 6: Banner card component + storybook story

**Files:**
- Create: `lib/media_centaur_web/components/app_cards.ex`
- Create: `storybook/app_cards/banner_card.story.exs`
- Create: `storybook/app_cards/_app_cards.index.exs`

Stories are the acceptance criterion for a new component (storybook skill) — no unit test asserts markup (automated-testing: never test rendered HTML). `storybook_compile_test` / `storybook_render_test` pick the story up automatically.

- [ ] **Step 1: Write the component**:

```elixir
defmodule MediaCentaurWeb.Components.AppCards do
  @moduledoc """
  Cards for the Apps launcher page.

  `banner_card/1` renders one app as a landscape card at Steam header
  art's native 460:215 ratio (spec: forcing 16:9 would crop ~17% of the
  art) while sharing the established card chrome (`card-hover`,
  `glass-inset`) and the art-less fallback idiom from
  `ContinueWatchingRow` — a centered monogram when no banner is cached.

  In manage mode the card stops launching: clicking it opens the edit
  modal instead, and a remove button appears.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  attr :id, :string, required: true, doc: "DOM id (stable across renders)"
  attr :app_id, :string, required: true
  attr :name, :string, required: true
  attr :banner_url, :string, default: nil, doc: "cached banner web path; nil renders the monogram fallback"

  attr :manage, :boolean,
    default: false,
    doc: "manage mode: click edits instead of launching, remove button shown"

  def banner_card(assigns) do
    ~H"""
    <div
      id={@id}
      phx-click={if @manage, do: "edit_app", else: "launch_app"}
      phx-value-app-id={@app_id}
      phx-throttle="1000"
      class="card-hover relative aspect-[460/215] rounded-lg overflow-hidden glass-inset block w-full text-left cursor-pointer"
      data-nav-item
      data-app-id={@app_id}
      tabindex="0"
    >
      <img
        :if={@banner_url}
        src={sized_image_url(@banner_url, 640)}
        alt={@name}
        class="absolute inset-0 w-full h-full object-cover"
        loading="eager"
        decoding="sync"
      />
      <div
        :if={!@banner_url}
        class="absolute inset-0 flex flex-col items-center justify-center gap-1 text-base-content/60"
      >
        <span class="text-4xl font-semibold">{String.first(@name) |> String.upcase()}</span>
        <span class="text-sm font-medium truncate max-w-[90%]">{@name}</span>
      </div>
      <button
        :if={@manage}
        phx-click="remove_app"
        phx-value-app-id={@app_id}
        class="absolute top-2 right-2 z-10 btn btn-ghost btn-square btn-sm text-error cursor-pointer"
        data-nav-item
        tabindex="0"
        aria-label={"Remove #{@name}"}
      >
        <.icon name="hero-trash" class="size-4" />
      </button>
    </div>
    """
  end
end
```

Note: the remove button uses the raw `btn btn-ghost text-error` classes ONLY if `<.button>` cannot nest here — it can: prefer `<.button variant="destructive_inline" shape="square" size="sm" ...>`. Check `core_components.ex` `button/1` attrs for the exact `shape` attr name; UIDR-003 requires the component (raw `class="btn ..."` fails the RawButtonClass Credo check). But a `<button>` cannot nest inside another interactive element — the card is a `div` (same reason as ContinueWatchingRow), so nesting is legal.

- [ ] **Step 2: Write the story**:

`storybook/app_cards/_app_cards.index.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.AppCards do
  use PhoenixStorybook.Index

  def entry("banner_card"), do: [icon: {:hero, "rocket-launch"}, name: "App banner card"]
end
```

`storybook/app_cards/banner_card.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.AppCards.BannerCard do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.AppCards.banner_card/1
  def render_source, do: :function

  def template do
    ~s|<div class="max-w-sm"><.psb-variation/></div>|
  end

  def variations do
    [
      %Variation{
        id: :with_banner,
        description: "Cached Steam header art (placeholder SVG served on this miss)",
        attributes: %{
          id: "app-card-demo-1",
          app_id: "demo-1",
          name: "Sample Game",
          banner_url: "/media-images/images/apps/demo-1/banner.jpg"
        }
      },
      %Variation{
        id: :monogram_fallback,
        description: "Manual app without artwork — monogram fallback",
        attributes: %{
          id: "app-card-demo-2",
          app_id: "demo-2",
          name: "Emulator",
          banner_url: nil
        }
      },
      %Variation{
        id: :manage_mode,
        description: "Manage mode — click edits, remove button visible",
        attributes: %{
          id: "app-card-demo-3",
          app_id: "demo-3",
          name: "Sample Game",
          banner_url: "/media-images/images/apps/demo-3/banner.jpg",
          manage: true
        }
      }
    ]
  end
end
```

- [ ] **Step 3: Verify** — `mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`. Expected: PASS (the render test smokes the story URL).

- [ ] **Step 4: Commit** — `git commit -am "feat(apps): banner card component + story"`

---

### Task 7: `AppsLive` — page, manage mode, add/edit modals, route, sidebar

**Files:**
- Create: `lib/media_centaur_web/live/apps_live.ex`
- Modify: `lib/media_centaur_web/router.ex` (route)
- Modify: `lib/media_centaur_web/components/layouts.ex` (attr + nav link)
- Modify: every LiveView that calls `Layouts.app` with `show_watchlist=` — add `show_apps={@show_apps}` (grep `show_watchlist={` under `lib/media_centaur_web/live/`; the assign is seeded session-wide by Task 5's SettingAware tuple)
- Test: `test/media_centaur_web/live/apps_live_test.exs`
- Modify: `test/media_centaur_web/page_smoke_test.exs` (`{"/apps", "apps"}` entry + a populated-branch describe)

- [ ] **Step 1: Write the failing LiveView tests**:

```elixir
defmodule MediaCentaurWeb.AppsLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  describe "grid" do
    test "renders every app as a card", %{conn: conn} do
      app = create_app(%{name: "Sample Game"})
      {:ok, view, _html} = live(conn, "/apps")

      assert has_element?(view, "[data-app-id='#{app.id}']")
    end

    test "empty state points at Manage", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/apps")
      assert html =~ "No apps yet"
    end
  end

  describe "manage mode" do
    test "toggles remove affordance on cards", %{conn: conn} do
      app = create_app(%{})
      {:ok, view, _html} = live(conn, "/apps")

      refute has_element?(view, "[phx-click='remove_app']")
      render_click(element(view, "[phx-click='toggle_manage']"))
      assert has_element?(view, "[phx-click='remove_app'][phx-value-app-id='#{app.id}']")
    end

    test "remove_app deletes the app", %{conn: conn} do
      app = create_app(%{})
      {:ok, view, _html} = live(conn, "/apps")

      render_click(element(view, "[phx-click='toggle_manage']"))
      render_click(element(view, "[phx-click='remove_app'][phx-value-app-id='#{app.id}']"))

      assert MediaCentaur.Apps.list_apps() == []
      refute has_element?(view, "[data-app-id='#{app.id}']")
    end
  end

  describe "manual add" do
    test "save_manual creates an app and closes the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/apps")

      render_click(element(view, "[phx-click='toggle_manage']"))
      render_click(element(view, "[phx-click='open_add']"))
      render_click(element(view, "[phx-click='set_add_tab'][phx-value-tab='manual']"))

      view
      |> form("#app-manual-form", app: %{name: "Sample App", command: "sample-app"})
      |> render_submit()

      assert [app] = MediaCentaur.Apps.list_apps()
      assert app.origin == %{"source" => "manual"}
      assert has_element?(view, "[data-app-id='#{app.id}']")
    end

    test "invalid manual form re-renders with errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/apps")

      render_click(element(view, "[phx-click='toggle_manage']"))
      render_click(element(view, "[phx-click='open_add']"))
      render_click(element(view, "[phx-click='set_add_tab'][phx-value-tab='manual']"))

      html =
        view
        |> form("#app-manual-form", app: %{name: "", command: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert MediaCentaur.Apps.list_apps() == []
    end
  end

  describe "edit" do
    test "edit_app opens the form prefilled and save updates", %{conn: conn} do
      app = create_app(%{name: "Old Name", command: "old-cmd"})
      {:ok, view, _html} = live(conn, "/apps")

      render_click(element(view, "[phx-click='toggle_manage']"))
      render_click(element(view, "[phx-click='edit_app'][phx-value-app-id='#{app.id}']"))

      view
      |> form("#app-manual-form", app: %{name: "New Name", command: "new-cmd"})
      |> render_submit()

      assert MediaCentaur.Apps.get_app!(app.id).name == "New Name"
    end
  end

  describe "steam picker" do
    test "lists discovered games with already-added marking and adds on click", %{conn: conn} do
      root = Path.join(System.tmp_dir!(), "mc-steam-live-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "steamapps"))

      for {id, name} <- [{100, "Sample Game"}, {200, "Other Game"}] do
        File.write!(Path.join([root, "steamapps", "appmanifest_#{id}.acf"]), """
        "AppState"
        {
        \t"appid"\t\t"#{id}"
        \t"name"\t\t"#{name}"
        }
        """)

        cache = Path.join([root, "appcache", "librarycache", "#{id}"])
        File.mkdir_p!(cache)
        File.write!(Path.join(cache, "header.jpg"), "jpg")
        File.write!(Path.join(cache, "library_600x900.jpg"), "jpg")
      end

      on_exit(fn -> File.rm_rf!(root) end)
      Process.put(:mc_test_steam_root, root)

      # Steam root injection: AppsLive resolves the root through
      # steam_root/0, overridable in tests — see Step 3.
      {:ok, view, _html} = live(conn, "/apps?steam_root=#{URI.encode_www_form(root)}")

      render_click(element(view, "[phx-click='toggle_manage']"))
      render_click(element(view, "[phx-click='open_add']"))

      assert has_element?(view, "[phx-click='add_steam_game'][phx-value-app-id='100']")

      render_click(element(view, "[phx-click='add_steam_game'][phx-value-app-id='100']"))

      assert [app] = MediaCentaur.Apps.list_apps()
      assert app.origin == %{"source" => "steam", "app_id" => 100}
      # Already-added games show a marker instead of an add control.
      assert has_element?(view, "[data-steam-added='100']")
    end
  end

  describe "launch" do
    test "launch_app flashes an acknowledgment", %{conn: conn} do
      app = create_app(%{name: "Sample Game", command: "true"})
      {:ok, view, _html} = live(conn, "/apps")

      render_click(element(view, "[phx-click='launch_app'][phx-value-app-id='#{app.id}']"))
      assert render(view) =~ "Launching Sample Game"
    end
  end
end
```

Steam-root injection decision (locked here so the test and code agree): `/apps` accepts an optional `?steam_root=` param used **only** to override `Steam.detect_root/0` — it exists for tests and power users pointing at a nonstandard install. `handle_params` stores it; `detect_root/0` is the fallback. No config key, no process dictionary (drop the `Process.put` line above — the query param is the mechanism).

The `launch` test spawns `setsid -f sh -c true` for real — instant-exit, harmless, no orphan. If CI lacks `setsid`, the flash still renders (launch error is logged, flash shows a failure copy — see Step 3) so assert on the success copy only if `System.find_executable("setsid")`; otherwise skip the flash-copy assertion. Keep it simple: assert the flash only, not the spawn.

- [ ] **Step 2: Run — expect failure** (route missing): `mix test test/media_centaur_web/live/apps_live_test.exs`

- [ ] **Step 3: Implement `AppsLive`**:

```elixir
defmodule MediaCentaurWeb.AppsLive do
  @moduledoc """
  The Apps launcher — a banner-card grid of user-curated external
  applications, launched fire-and-forget (`MediaCentaur.Apps`).

  Launch-only by default; the toolbar's Manage toggle reveals add /
  edit / remove. The Add modal has two tabs: the Steam picker (installed
  games discovered from the local Steam root, header art hotlinked from
  Steam's CDN at browsing tier) and the manual form (name + command +
  optional artwork URL/path). Modal state lives in assigns — no URL
  params, so nothing for `data-nav-transient-params`.

  `?steam_root=` overrides `Steam.detect_root/0` (tests, nonstandard
  installs).
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Apps
  alias MediaCentaur.Apps.App
  alias MediaCentaur.Apps.Steam
  alias MediaCentaurWeb.Components.AppCards

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Apps", manage: false, modal: :closed, add_tab: :steam)
     |> assign(:steam_root_override, nil)
     |> load_apps()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :steam_root_override, params["steam_root"])}
  end

  @impl true
  def handle_event("launch_app", %{"app-id" => id}, socket) do
    app = Apps.get_app!(id)

    case Apps.launch(app) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Launching #{app.name}…")}

      {:error, :launcher_unavailable} ->
        {:noreply, put_flash(socket, :error, "Couldn't launch #{app.name} — setsid not found on PATH.")}
    end
  end

  def handle_event("toggle_manage", _params, socket) do
    {:noreply, assign(socket, manage: !socket.assigns.manage, modal: :closed)}
  end

  def handle_event("open_add", _params, socket) do
    {:noreply,
     socket
     |> assign(modal: :add, add_tab: :steam)
     |> assign_steam_games()
     |> assign_manual_form(App.create_changeset(%{}))}
  end

  def handle_event("set_add_tab", %{"tab" => tab}, socket) when tab in ~w(steam manual) do
    {:noreply, assign(socket, add_tab: String.to_existing_atom(tab))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: :closed)}
  end

  def handle_event("add_steam_game", %{"app-id" => app_id}, socket) do
    app_id = String.to_integer(app_id)
    game = Enum.find(socket.assigns.steam_games, &(&1.app_id == app_id))

    case game && Apps.add_steam_app(game, steam_root(socket)) do
      {:ok, _app} ->
        {:noreply, socket |> load_apps() |> assign_steam_games()}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_app", %{"app-id" => id}, socket) do
    app = Apps.get_app!(id)

    {:noreply,
     socket
     |> assign(modal: {:edit, app})
     |> assign_manual_form(App.update_changeset(app, %{}))}
  end

  def handle_event("remove_app", %{"app-id" => id}, socket) do
    Apps.remove_app(Apps.get_app!(id))
    {:noreply, load_apps(socket)}
  end

  def handle_event("save_manual", %{"app" => params}, socket) do
    result =
      case socket.assigns.modal do
        {:edit, app} -> Apps.update_app(app, params)
        :add -> Apps.add_app(Map.put(params, "origin", %{"source" => "manual"}))
      end

    case result do
      {:ok, _app} ->
        {:noreply, socket |> assign(modal: :closed) |> load_apps()}

      {:error, changeset} ->
        {:noreply, assign_manual_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      show_watchlist={@show_watchlist}
      show_apps={@show_apps}
      flash={@flash}
      current_path="/apps"
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      status_errors={assigns[:status_errors] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
    >
      <div class="relative" data-page-behavior="apps" data-nav-default-zone="apps">
        <div class="space-y-4" data-nav-zone="toolbar">
          <div class="flex items-center justify-between">
            <h1 class="text-lg font-semibold">Apps</h1>
            <.button variant={if @manage, do: "secondary", else: "dismiss"} size="sm" phx-click="toggle_manage" data-nav-item tabindex="0">
              <.icon name={if @manage, do: "hero-check", else: "hero-cog-6-tooth"} class="size-4" />
              {if @manage, do: "Done", else: "Manage"}
            </.button>
          </div>
        </div>

        <div
          :if={@apps == []}
          id="apps-empty"
          class="mt-4 glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/40"
        >
          No apps yet. Open Manage to add a Steam game or any command.
        </div>

        <div :if={@apps != []} class="mt-4" data-nav-zone="grid">
          <div
            id="apps-grid"
            data-nav-grid
            class="grid gap-3 grid-cols-[repeat(auto-fill,minmax(230px,1fr))]"
          >
            <AppCards.banner_card
              :for={app <- @apps}
              id={"app-card-#{app.id}"}
              app_id={app.id}
              name={app.name}
              banner_url={app.banner_url}
              manage={@manage}
            />
          </div>
        </div>

        <div :if={@manage} class="mt-4">
          <.button variant="action" size="sm" phx-click="open_add" data-nav-item tabindex="0">
            <.icon name="hero-plus" class="size-4" /> Add app
          </.button>
        </div>
      </div>

      <:overlays>
        <div class="modal-backdrop" data-state={if @modal == :closed, do: "closed", else: "open"}>
          <div class="modal-panel" phx-click-away={@modal != :closed && "close_modal"}>
            <div :if={@modal != :closed} class="p-5 space-y-4">
              <div class="flex items-center justify-between">
                <h2 class="text-lg font-semibold">
                  {if match?({:edit, _app}, @modal), do: "Edit app", else: "Add app"}
                </h2>
                <.button variant="dismiss" size="sm" shape="square" phx-click="close_modal">
                  <.icon name="hero-x-mark" class="size-4" />
                </.button>
              </div>

              <div :if={@modal == :add} class="flex gap-1">
                <.button
                  variant={if @add_tab == :steam, do: "secondary", else: "dismiss"}
                  size="sm"
                  phx-click="set_add_tab"
                  phx-value-tab="steam"
                >
                  Steam
                </.button>
                <.button
                  variant={if @add_tab == :manual, do: "secondary", else: "dismiss"}
                  size="sm"
                  phx-click="set_add_tab"
                  phx-value-tab="manual"
                >
                  Manual
                </.button>
              </div>

              <div :if={@modal == :add && @add_tab == :steam}>
                <p :if={@steam_games == :unavailable} class="text-sm text-base-content/50">
                  Steam wasn't found on this machine. Use the Manual tab to add any app by command.
                </p>
                <p :if={@steam_games == []} class="text-sm text-base-content/50">
                  Steam is installed, but no games were found.
                </p>
                <div
                  :if={is_list(@steam_games) && @steam_games != []}
                  class="grid gap-2 grid-cols-2 max-h-[50vh] overflow-y-auto thin-scrollbar"
                >
                  <%= for game <- @steam_games do %>
                    <div
                      :if={MapSet.member?(@added_steam_ids, game.app_id)}
                      data-steam-added={game.app_id}
                      class="relative aspect-[460/215] rounded-lg overflow-hidden glass-inset opacity-50"
                    >
                      <img
                        src={Steam.cdn_art_url(game.app_id, :banner)}
                        alt={game.name}
                        class="absolute inset-0 w-full h-full object-cover"
                        loading="lazy"
                        decoding="async"
                      />
                      <span class="absolute bottom-1 left-2 text-xs text-white text-on-image">
                        {game.name} — added
                      </span>
                    </div>
                    <div
                      :if={!MapSet.member?(@added_steam_ids, game.app_id)}
                      phx-click="add_steam_game"
                      phx-value-app-id={game.app_id}
                      class="card-hover relative aspect-[460/215] rounded-lg overflow-hidden glass-inset cursor-pointer"
                      data-nav-item
                      tabindex="0"
                    >
                      <img
                        src={Steam.cdn_art_url(game.app_id, :banner)}
                        alt={game.name}
                        class="absolute inset-0 w-full h-full object-cover"
                        loading="lazy"
                        decoding="async"
                      />
                      <span class="absolute bottom-1 left-2 text-xs text-white text-on-image">
                        {game.name}
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>

              <.form
                :if={@modal != :closed && (@add_tab == :manual || match?({:edit, _app}, @modal))}
                for={@manual_form}
                id="app-manual-form"
                phx-submit="save_manual"
                class="space-y-3"
              >
                <.input field={@manual_form[:name]} label="Name" />
                <.input
                  field={@manual_form[:command]}
                  label="Command"
                  placeholder="e.g. minecraft-launcher"
                />
                <div class="flex justify-end gap-2">
                  <.button variant="dismiss" size="sm" type="button" phx-click="close_modal">
                    Cancel
                  </.button>
                  <.button variant="primary" size="sm" type="submit">Save</.button>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </:overlays>
    </Layouts.app>
    """
  end

  defp load_apps(socket) do
    apps =
      Enum.map(Apps.list_apps(), fn app ->
        Map.put(app, :banner_url, Apps.artwork_urls(app.id).banner_url)
      end)

    assign(socket, :apps, apps)
  end

  defp assign_steam_games(socket) do
    case steam_root(socket) do
      nil ->
        assign(socket, steam_games: :unavailable, added_steam_ids: MapSet.new())

      root ->
        assign(socket,
          steam_games: Steam.installed_games(root),
          added_steam_ids: Apps.added_steam_ids()
        )
    end
  end

  defp assign_manual_form(socket, changeset) do
    assign(socket, :manual_form, to_form(changeset, as: :app))
  end

  defp steam_root(socket) do
    socket.assigns.steam_root_override || Steam.detect_root()
  end
end
```

Implementation cautions for this step:
- `Map.put(app, :banner_url, ...)` on a struct fails — `App` has no `:banner_url` key. Build a plain map for the view instead: `%{id: app.id, name: app.name, banner_url: ...}` (and the card takes those three). Fix the `load_apps` above accordingly.
- The Steam-picker `<img>` uses `loading="lazy" decoding="async"` — that's a **bounded reveal-on-demand surface** (a scrollable modal of CDN hotlinks), the exemption MC0016 carves out. If MC0016 flags it, extend the exempt list with this justification (per the check's own comment convention).
- The spec's optional manual-artwork field: **include it only if trivially cheap with `<.input field={@manual_form[:artwork]} label="Artwork URL or file path (optional)" />`** plus a `save_manual` branch — on `{:ok, app}`, if `params["artwork"]` is non-blank: URL → async `Artwork.store_url(:banner, app.id, url)` via `Task.Supervisor` in the context (add `Apps.attach_manual_artwork(app, value)` to the facade — never `Task.Supervisor` in the web layer, MC0019); existing local file → `Artwork.store_file(:banner, app.id, path)`. The field is not in the changeset — read it from raw params. Add one test: manual add with a local tmp file path caches the banner.
- `String.to_existing_atom(tab)` is safe — `:steam`/`:manual` exist in this module.
- Check `<.input>` component attrs in `core_components.ex` before using (`field`, `label`, `placeholder` are the standard trio).

- [ ] **Step 4: Route + sidebar**:
  - `router.ex`: `live "/apps", AppsLive, :index` (alphabetical — after `live "/", HomeLive`).
  - `layouts.ex`: after the `show_watchlist` attr:
    ```elixir
    attr :show_apps, :boolean,
      default: false,
      doc: """
      Whether the sidebar shows the Apps entry — the `show_apps`
      preference (`MediaCentaur.Settings.Preferences.AppsVisibility`, default off).
      Seeded app-wide by the `SettingAware` on_mount; only the nav entry
      is gated — `/apps` stays reachable by URL.
      """
    ```
    and after the Incoming link in the Watch group:
    ```heex
    <.link
      :if={@show_apps}
      navigate="/apps"
      class={sidebar_link_class(@current_path, "/apps")}
      data-tip="Apps"
      data-nav-item
      data-nav-remember
      tabindex="0"
    >
      <.icon name="hero-rocket-launch" class="size-5 flex-shrink-0" />
      <span class="sidebar-label">Apps</span>
    </.link>
    ```
  - Every LiveView already passing `show_watchlist={@show_watchlist}` to `Layouts.app` gains `show_apps={@show_apps}` on the next line (grep `show_watchlist={` in `lib/media_centaur_web/live/` — home, library, watchlist, incoming, status, review, reconcile, guide, watch_history, settings, and any others the grep finds).

- [ ] **Step 5: Smoke entries** — in `page_smoke_test.exs` add `{"/apps", "apps"}` to the route list, plus a populated-branch describe:

```elixir
describe "/apps with apps present" do
  setup do
    create_app(%{name: "Sample Smoke App"})
    :ok
  end

  test "renders the card grid", %{conn: conn} do
    assert {:ok, _view, html} = live_async!(conn, "/apps")
    assert html =~ "Sample Smoke App"
  end
end
```

- [ ] **Step 6: Run — expect PASS**: `mix test test/media_centaur_web/live/apps_live_test.exs test/media_centaur_web/page_smoke_test.exs`

- [ ] **Step 7: Sidebar gating test** — append to `apps_live_test.exs`:

```elixir
describe "sidebar entry" do
  test "hidden by default, shown when the preference is on", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    refute has_element?(view, "[data-tip='Apps']")

    MediaCentaur.Settings.find_or_create_entry!(%{
      key: MediaCentaur.Settings.Preferences.AppsVisibility.setting_key(),
      value: %{"enabled" => true}
    })

    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "[data-tip='Apps']")
  end
end
```

- [ ] **Step 8: Commit** — `git commit -am "feat(apps): /apps page — banner grid, manage mode, steam picker, manual form"`

---

### Task 8: Input-system wiring

**Files:**
- Modify: `assets/js/input/config.js` (layouts + cursorStartPriority)
- Create: `assets/js/input/apps_behavior.js`
- Modify: `assets/js/input/page_behavior.js` (registry)
- Create: `assets/js/input/__tests__/apps_behavior.test.js` (mirror `watchlist_behavior.test.js` — read it first and copy its shape exactly)

The page declares `data-nav-zone="toolbar"` and `data-nav-zone="grid"`; the modal is a flat MODAL overlay (no `data-nav-overlay` — right for small forms per the input-system skill). `toolbar` and `grid` are existing context instances — no `instanceTypes`/`contextSelectors` changes.

- [ ] **Step 1: Write the failing behavior test** (mirroring `watchlist_behavior.test.js`; adjust to its actual shape after reading it):

```js
import { describe, expect, test } from "bun:test"
import { createAppsBehavior } from "../apps_behavior"

describe("apps behavior", () => {
  test("returns an empty behavior — framework defaults cover the page", () => {
    expect(createAppsBehavior()).toEqual({})
  })
})
```

- [ ] **Step 2: Run — expect failure**: `bun test assets/js/input/__tests__/apps_behavior.test.js`

- [ ] **Step 3: Implement**:

`assets/js/input/apps_behavior.js`:

```js
/**
 * Apps launcher page behavior.
 *
 * Layout: a toolbar (Manage toggle) above a banner-card grid. The
 * add/edit modal is a flat MODAL overlay. No page-specific actions —
 * the framework defaults cover it.
 */
export function createAppsBehavior() {
  return {}
}
```

`page_behavior.js`: import + registry entry `apps: () => createAppsBehavior(),`.

`config.js` — layouts (next to `watchlist`):

```js
apps: {
  toolbar: { down: ["grid"] },
  grid:    { up: ["toolbar"] },
  sidebar: { right: ["grid", "toolbar"] },
},
```

and cursorStartPriority: `apps: ["grid", "toolbar", "sidebar"],`.

- [ ] **Step 4: Run the full JS suite** — `bun test assets/js/input/`. Expected: PASS (including `config_coverage.test.js`, which cross-checks registry/layout completeness — follow its failure message if it demands a matching entry anywhere else).

- [ ] **Step 5: Build assets** (watchers are OFF in dev — manual build required): `mix assets.build`

- [ ] **Step 6: Commit** — `git commit -am "feat(apps): input-system nav wiring for /apps"`

---

### Task 9: Precommit, live verification, docs

**Files:**
- Modify: `docs/architecture.md` (add `Apps` to the bounded-context list, one line, mirroring neighbors)
- Modify: `docs/GLOSSARY.md` (App, add-method, origin — check the file's format first; create the entries in its existing style)
- Wiki (sibling repo `~/src/media-centaur/media-centaur.wiki`): new `Apps.md` page (what it is, adding a Steam game, adding a manual command, the show_apps toggle) + `Settings-Reference.md` row for the Apps toggle. Use the writing-copy skill for all wiki prose.

- [ ] **Step 1: `mix precommit`** — fix everything it reports: format, credo (MC0009 story coverage, MC0016 img attrs, MC0019 task ownership, MC0023 factory use, MC0024 attr assertions), boundaries (the new `MediaCentaur.Apps` dep edges), full test suite, zero warnings.

- [ ] **Step 2: Live verification (real browser, not render_click)** — dev server on :2160:
  1. Enable the preference: Settings → Preferences → Apps toggle (real click via `chromium-probe` or `page-shot` inspection; wait for `phx-connected` on `[data-phx-main]` before clicking).
  2. `/apps`: empty state renders; Manage → Add app → Manual: create `name="Terminal Clock", command="foot -e watch date"` (or any harmless installed command); card appears with monogram.
  3. If Steam is installed on this machine: open the Steam tab, verify discovered games render with CDN art, add one, verify the card gets local art (banner file lands under `{data_dir}/images/apps/{id}/`).
  4. Click the card (real click): verify the command actually spawns and the flash shows.
  5. Keyboard nav: `~/scripts/agents/mc-nav-trace` over the page — sidebar → grid → toolbar transitions, no clipped focus.
  6. Remove the test app via Manage; verify the art directory is deleted.

- [ ] **Step 3: Contributor + user docs** — architecture list line, GLOSSARY entries, wiki page + settings reference (commit the wiki repo separately: `wiki: document the Apps launcher`).

- [ ] **Step 4: Final commit** — `git commit -am "docs(apps): architecture entry, glossary, wiki sync"`. Do not push/tag — per the review-before-shipping rule this is freshly built work; the user says when to ship.

---

## Self-Review Notes

- **Spec coverage:** context/boundary → T1; data model → T1; steam discovery → T3; artwork (disk-ledger, ImageServer stem, deletion) → T4; launching → T2; preference + nav + settings → T5/T7; page/manage/modal/cards/story → T6/T7; input system → T8; error handling (steam absent → picker copy, art failure → fallback card, launcher unavailable → flash+log) → T3/T4/T7; testing policies → every task; docs/wiki → T9. CHANGELOG happens at ship time (house `/ship` flow), deliberately not a task.
- **Type consistency:** `Apps.add_app/1`, `add_steam_app/2`, `artwork_urls/1`, `launch/1`, `added_steam_ids/0` used identically in T1/T4/T7. Roles are `:banner`/`:poster` everywhere. `spawn_spec/1` name consistent T2.
- **Known judgment calls surfaced in-line:** struct-vs-map for card view models (T7), `<.button>` nesting inside the card div (T6), `ImageFiles.download_raw` arity check (T4), Config test-override mechanism name (T4), lazy-img exemption (T7).
