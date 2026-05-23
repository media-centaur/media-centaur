# Per-movie "Refresh artwork" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-entity "Refresh artwork" action to the detail → manage view that re-fetches TMDB metadata and re-downloads artwork for one movie/series, replacing existing art and filling gaps.

**Architecture:** Reuse the *import* enqueue path (not the repair path). Extract the TMDB→image-list mapper and the entity→(tmdb id, watch_dir) lookups into shared units, add a thin `ImageRefresh` core that broadcasts `{:enqueue_images, …}`, drive it from an Oban job (ADR-049: work that must outlive the LiveView), and wire a button + flash into the detail panel.

**Tech Stack:** Elixir, Phoenix LiveView, Oban (Lite engine, inline test mode), Broadway image pipeline, Req.Test TMDB stubs.

---

## File structure

- `lib/media_centaur/tmdb/mapper.ex` — **modify**: add public `image_list/1` (+ private `logo_path/1`).
- `lib/media_centaur/pipeline/stages/fetch_metadata.ex` — **modify**: `build_images/1` delegates to `Mapper.image_list/1`; drop local `find_logo_path/1`.
- `lib/media_centaur/pipeline/entity_image_context.ex` — **create**: `find_tmdb_context/2`, `find_watch_dir/2` (moved from `ImageRepair`).
- `lib/media_centaur/pipeline/image_repair.ex` — **modify**: delegate to `EntityImageContext`, delete the moved privates.
- `lib/media_centaur/pipeline/image_refresh.ex` — **create**: `refresh_entity/2`, `enqueue_refresh/2`.
- `lib/media_centaur/pipeline/image_refresh_worker.ex` — **create**: Oban worker.
- `config/config.exs` — **modify**: add `images: 2` queue.
- `lib/media_centaur_web/live/entity_modal.ex` — **modify**: `refresh_artwork_flash/1` (public, pure) + `handle_event("refresh_artwork", …)` in the `__using__` quote.
- `lib/media_centaur_web/components/detail_panel.ex` — **modify**: add Refresh-artwork button in the Actions section of `info_view/1`.

Tests:
- `test/media_centaur/tmdb/mapper_test.exs` (modify/create)
- `test/media_centaur/pipeline/entity_image_context_test.exs` (create)
- `test/media_centaur/pipeline/image_refresh_test.exs` (create)
- `test/media_centaur/pipeline/image_refresh_worker_test.exs` (create)
- `test/media_centaur_web/live/entity_modal_test.exs` or nearest existing modal test (modify/create)

---

### Task 1: Shared TMDB image-list mapper

**Files:**
- Modify: `lib/media_centaur/tmdb/mapper.ex`
- Modify: `lib/media_centaur/pipeline/stages/fetch_metadata.ex:241-272`
- Test: `test/media_centaur/tmdb/mapper_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/media_centaur/tmdb/mapper_test.exs  (add to existing module or create)
defmodule MediaCentaur.TMDB.MapperTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.TMDB.Mapper

  describe "image_list/1" do
    test "extracts poster, backdrop, and english logo" do
      data = %{
        "poster_path" => "/p.jpg",
        "backdrop_path" => "/b.jpg",
        "images" => %{"logos" => [%{"iso_639_1" => "de", "file_path" => "/de.png"}, %{"iso_639_1" => "en", "file_path" => "/en.png"}]}
      }

      assert Mapper.image_list(data) == [
               %{role: "poster", url: "https://image.tmdb.org/t/p/original/p.jpg", extension: "jpg"},
               %{role: "backdrop", url: "https://image.tmdb.org/t/p/original/b.jpg", extension: "jpg"},
               %{role: "logo", url: "https://image.tmdb.org/t/p/original/en.png", extension: "png"}
             ]
    end

    test "omits missing roles and falls back to first logo when no english" do
      data = %{"poster_path" => "/p.jpg", "images" => %{"logos" => [%{"iso_639_1" => "fr", "file_path" => "/fr.png"}]}}

      assert Mapper.image_list(data) == [
               %{role: "poster", url: "https://image.tmdb.org/t/p/original/p.jpg", extension: "jpg"},
               %{role: "logo", url: "https://image.tmdb.org/t/p/original/fr.png", extension: "png"}
             ]
    end

    test "returns empty list when no image paths present" do
      assert Mapper.image_list(%{}) == []
    end
  end
end
```

- [ ] **Step 2: Run test, verify it fails**

Run: `mix test test/media_centaur/tmdb/mapper_test.exs`
Expected: FAIL — `image_list/1` undefined.

- [ ] **Step 3: Implement `image_list/1` in Mapper**

Add to `lib/media_centaur/tmdb/mapper.ex` (near `tmdb_image_url/1`):

```elixir
@doc """
Builds the artwork list from a TMDB movie/tv/collection payload:
poster, backdrop, and the english (or first) logo. Missing roles are
omitted. Shared by the import pipeline (`FetchMetadata`) and per-entity
artwork refresh (`Pipeline.ImageRefresh`).
"""
@spec image_list(map()) :: [%{role: String.t(), url: String.t(), extension: String.t()}]
def image_list(data) do
  Enum.reject(
    [
      data["poster_path"] && %{role: "poster", url: tmdb_image_url(data["poster_path"]), extension: "jpg"},
      data["backdrop_path"] && %{role: "backdrop", url: tmdb_image_url(data["backdrop_path"]), extension: "jpg"},
      logo_path(data) && %{role: "logo", url: tmdb_image_url(logo_path(data)), extension: "png"}
    ],
    &is_nil/1
  )
end

defp logo_path(data) do
  logos = get_in(data, ["images", "logos"]) || []
  logo = Enum.find(logos, &(&1["iso_639_1"] == "en")) || List.first(logos)
  logo && logo["file_path"]
end
```

- [ ] **Step 4: Delegate from FetchMetadata**

In `lib/media_centaur/pipeline/stages/fetch_metadata.ex`, replace `build_images/1` (lines 241-256) and delete `find_logo_path/1` (lines 268-272):

```elixir
defp build_images(data), do: MediaCentaur.TMDB.Mapper.image_list(data)
```

(Leave `build_episode_images/1` untouched.)

- [ ] **Step 5: Run tests, verify pass**

Run: `mix test test/media_centaur/tmdb/mapper_test.exs test/media_centaur/pipeline`
Expected: PASS (mapper + existing pipeline tests still green).

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/tmdb/mapper.ex lib/media_centaur/pipeline/stages/fetch_metadata.ex test/media_centaur/tmdb/mapper_test.exs
git commit -m "refactor: extract TMDB.Mapper.image_list shared by import + refresh"
```

---

### Task 2: Shared entity→context lookups

**Files:**
- Create: `lib/media_centaur/pipeline/entity_image_context.ex`
- Modify: `lib/media_centaur/pipeline/image_repair.ex`
- Test: `test/media_centaur/pipeline/entity_image_context_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/media_centaur/pipeline/entity_image_context_test.exs
defmodule MediaCentaur.Pipeline.EntityImageContextTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Pipeline.EntityImageContext, as: Context
  alias MediaCentaur.TestFactory

  describe "find_tmdb_context/2" do
    test "returns the tmdb id for an identified movie" do
      movie = TestFactory.create_movie()
      TestFactory.create_identifier(%{owner_id: movie.id, owner_type: :movie, source: :tmdb, external_id: "550"})

      assert {:ok, "550"} = Context.find_tmdb_context(movie.id, :movie)
    end

    test "skips an unidentified movie" do
      movie = TestFactory.create_movie()
      assert {:skip, :no_tmdb_id} = Context.find_tmdb_context(movie.id, :movie)
    end
  end

  describe "find_watch_dir/2" do
    test "returns the watch dir of a movie's linked file" do
      movie = TestFactory.create_movie()
      TestFactory.create_linked_file(%{owner: movie, owner_type: :movie, watch_dir: "/media/movies"})

      assert {:ok, "/media/movies"} = Context.find_watch_dir(movie.id, :movie)
    end

    test "skips a movie with no files" do
      movie = TestFactory.create_movie()
      assert {:skip, :no_watch_dir} = Context.find_watch_dir(movie.id, :movie)
    end
  end
end
```

> NOTE during execution: confirm `create_identifier/1` and `create_linked_file/1` arg shapes against `MediaCentaur.TestFactory`; adjust the attrs above to match the factory's expected keys before running.

- [ ] **Step 2: Run test, verify it fails**

Run: `mix test test/media_centaur/pipeline/entity_image_context_test.exs`
Expected: FAIL — `EntityImageContext` undefined.

- [ ] **Step 3: Create EntityImageContext by moving the privates from ImageRepair**

Create `lib/media_centaur/pipeline/entity_image_context.ex` with a moduledoc (single responsibility: locate the TMDB id + watch_dir for an entity) and **public** `find_tmdb_context/2` and `find_watch_dir/2`, moving verbatim from `image_repair.ex`:
- `find_tmdb_context/2` (all clauses incl. `:episode`) + `lookup_tmdb_id/3` (image_repair.ex:179-219)
- `find_watch_dir/2` (all clauses) + `ok_or_skip/1` (image_repair.ex:233-326)

Bring the needed aliases/imports: `import Ecto.Query`; alias `Library`, `Library.Episode`, `Library.Movie`, `Library.PlayableItem`, `Library.Season`, `Library.WatchedFile`, `Repo`.

- [ ] **Step 4: Refactor ImageRepair to delegate**

In `image_repair.ex`: change call sites in `rebuild_queue_row/3` to `EntityImageContext.find_tmdb_context(...)` / `EntityImageContext.find_watch_dir(...)`, add `alias MediaCentaur.Pipeline.EntityImageContext`, and delete the now-moved privates (`find_tmdb_context`, `lookup_tmdb_id`, `find_watch_dir`, `ok_or_skip`). Remove any aliases left unused by ImageRepair to keep zero-warnings.

- [ ] **Step 5: Run tests, verify pass**

Run: `mix test test/media_centaur/pipeline/entity_image_context_test.exs test/media_centaur/pipeline/image_repair_test.exs`
Expected: PASS (new context tests + existing repair tests, if any, green).

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/pipeline/entity_image_context.ex lib/media_centaur/pipeline/image_repair.ex test/media_centaur/pipeline/entity_image_context_test.exs
git commit -m "refactor: extract EntityImageContext shared by ImageRepair + refresh"
```

---

### Task 3: ImageRefresh core

**Files:**
- Create: `lib/media_centaur/pipeline/image_refresh.ex`
- Test: `test/media_centaur/pipeline/image_refresh_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/media_centaur/pipeline/image_refresh_test.exs
defmodule MediaCentaur.Pipeline.ImageRefreshTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Pipeline.ImageRefresh
  alias MediaCentaur.TestFactory
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.Topics

  setup do
    TmdbStubs.setup_tmdb_client(self())
    :ok
  end

  defp identified_movie do
    movie = TestFactory.create_movie()
    TestFactory.create_identifier(%{owner_id: movie.id, owner_type: :movie, source: :tmdb, external_id: "550"})
    TestFactory.create_linked_file(%{owner: movie, owner_type: :movie, watch_dir: "/media/movies"})
    movie
  end

  describe "refresh_entity/2" do
    test "broadcasts enqueue_images with the TMDB artwork for a movie" do
      movie = identified_movie()
      TmdbStubs.stub_get_movie("550", %{poster_path: "/p.jpg", backdrop_path: "/b.jpg"})
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_images())

      assert {:ok, count} = ImageRefresh.refresh_entity(movie.id, :movie)
      assert count >= 2

      assert_receive {:enqueue_images, %{entity_id: entity_id, watch_dir: "/media/movies", images: images}}
      assert entity_id == movie.id
      roles = Enum.map(images, & &1.role)
      assert "poster" in roles and "backdrop" in roles
      assert Enum.all?(images, &(&1.owner_id == movie.id and &1.owner_type == "movie"))
    end

    test "errors with :no_tmdb_id for an unidentified entity" do
      movie = TestFactory.create_movie()
      assert {:error, :no_tmdb_id} = ImageRefresh.refresh_entity(movie.id, :movie)
    end
  end

  describe "enqueue_refresh/2" do
    test "errors with :no_tmdb_id without enqueuing for an unidentified entity" do
      movie = TestFactory.create_movie()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_images())

      assert {:error, :no_tmdb_id} = ImageRefresh.enqueue_refresh(movie.id, :movie)
      refute_receive {:enqueue_images, _}, 100
    end

    test "enqueues and (inline) refreshes an identified movie" do
      movie = identified_movie()
      TmdbStubs.stub_get_movie("550", %{poster_path: "/p.jpg"})
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_images())

      assert {:ok, _job} = ImageRefresh.enqueue_refresh(movie.id, :movie)
      assert_receive {:enqueue_images, %{entity_id: entity_id}}
      assert entity_id == movie.id
    end
  end
end
```

> NOTE during execution: confirm `TmdbStubs.stub_get_movie/2` fixture key names (`poster_path`/`backdrop_path`) against `test/support/tmdb_stubs.ex` and the `movie_detail/1` fixture; adjust if the helper expects different keys.

- [ ] **Step 2: Run test, verify it fails**

Run: `mix test test/media_centaur/pipeline/image_refresh_test.exs`
Expected: FAIL — `ImageRefresh` undefined.

- [ ] **Step 3: Implement ImageRefresh**

Create `lib/media_centaur/pipeline/image_refresh.ex`:

```elixir
defmodule MediaCentaur.Pipeline.ImageRefresh do
  @moduledoc """
  Force re-fetch + re-enqueue *all* artwork for one entity from TMDB.

  Unlike `ImageRepair` (which rebuilds queue rows only for `Image`
  records whose files are missing), this reuses the **import** enqueue
  path: it derives the full artwork list straight from fresh TMDB
  metadata and broadcasts `{:enqueue_images, …}`. The image Producer
  creates/upserts queue rows and downloads; `Library.upsert_image/2`
  then replaces `content_url` on completion — so a refresh both fills a
  gap (no artwork at all) and replaces existing art.

  `enqueue_refresh/2` is the web entry point: it cheaply pre-checks that
  the entity is TMDB-identified, then schedules `ImageRefreshWorker`
  (Oban) so the work outlives the LiveView (ADR-049). `refresh_entity/2`
  is the synchronous core run by the worker.

  Scope: top-level entities shown in the detail → manage view —
  `:movie`, `:tv_series`, `:movie_series`, `:video_object`.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Pipeline.EntityImageContext
  alias MediaCentaur.Pipeline.ImageRefreshWorker
  alias MediaCentaur.TMDB
  alias MediaCentaur.TMDB.Mapper
  alias MediaCentaur.Topics

  @type entity_type :: :movie | :tv_series | :movie_series | :video_object

  @doc """
  Schedules a refresh for one entity. Returns `{:error, :no_tmdb_id}`
  (without enqueuing) when the entity is not TMDB-identified, else the
  `Oban.insert/1` result.
  """
  @spec enqueue_refresh(String.t(), entity_type()) ::
          {:ok, Oban.Job.t()} | {:error, :no_tmdb_id} | {:error, Ecto.Changeset.t()}
  def enqueue_refresh(entity_id, type) do
    case EntityImageContext.find_tmdb_context(entity_id, type) do
      {:ok, _tmdb} ->
        %{entity_id: entity_id, entity_type: to_string(type)}
        |> ImageRefreshWorker.new()
        |> Oban.insert()

      {:skip, _reason} ->
        {:error, :no_tmdb_id}
    end
  end

  @doc """
  Re-fetches TMDB metadata for one entity and broadcasts
  `{:enqueue_images, …}`. Returns `{:ok, count}` (artwork roles
  enqueued) or `{:error, reason}`.
  """
  @spec refresh_entity(String.t(), entity_type()) :: {:ok, non_neg_integer()} | {:error, term()}
  def refresh_entity(entity_id, type) do
    with {:ok, tmdb_id} <- EntityImageContext.find_tmdb_context(entity_id, type),
         {:ok, watch_dir} <- EntityImageContext.find_watch_dir(entity_id, type),
         {:ok, data} <- fetch_metadata(type, tmdb_id) do
      enqueue(entity_id, type, watch_dir, Mapper.image_list(data))
    else
      {:skip, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue(entity_id, type, _watch_dir, []) do
    Log.info(:library, "image_refresh: no TMDB artwork for #{type}:#{entity_id}")
    {:ok, 0}
  end

  defp enqueue(entity_id, type, watch_dir, images) do
    pending =
      Enum.map(images, fn image ->
        %{
          owner_id: entity_id,
          owner_type: to_string(type),
          role: image.role,
          source_url: image.url,
          extension: image.extension
        }
      end)

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.pipeline_images(),
      {:enqueue_images, %{entity_id: entity_id, watch_dir: watch_dir, images: pending}}
    )

    Log.info(:library, "image_refresh: enqueued #{length(pending)} images for #{type}:#{entity_id}")
    {:ok, length(pending)}
  end

  defp fetch_metadata(:movie, tmdb_id), do: TMDB.Client.get_movie(tmdb_id)
  defp fetch_metadata(:video_object, tmdb_id), do: TMDB.Client.get_movie(tmdb_id)
  defp fetch_metadata(:tv_series, tmdb_id), do: TMDB.Client.get_tv(tmdb_id)
  defp fetch_metadata(:movie_series, tmdb_id), do: TMDB.Client.get_collection(tmdb_id)
end
```

> NOTE: `enqueue_refresh/2` references `ImageRefreshWorker`, created in Task 4. The test file for Task 3 only exercises the `refresh_entity/2` paths and the `:no_tmdb_id` branch of `enqueue_refresh/2` (which returns before touching the worker), so Task 3 compiles only after Task 4's module exists. Implement Task 4's worker module body first if the compiler complains, or run Task 3 + Task 4 tests together at the end of Task 4.

- [ ] **Step 4: Run tests**

Run: `mix test test/media_centaur/pipeline/image_refresh_test.exs`
Expected: PASS for `refresh_entity/2` cases and the `:no_tmdb_id` enqueue case. (The "enqueues and inline refreshes" case needs Task 4 — it may fail until the worker exists; that's expected and is resolved in Task 4.)

- [ ] **Step 5: Commit** (after Task 4 makes the suite fully green — or commit core now and worker next)

---

### Task 4: Oban worker + queue

**Files:**
- Create: `lib/media_centaur/pipeline/image_refresh_worker.ex`
- Modify: `config/config.exs:49`
- Test: `test/media_centaur/pipeline/image_refresh_worker_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/media_centaur/pipeline/image_refresh_worker_test.exs
defmodule MediaCentaur.Pipeline.ImageRefreshWorkerTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Pipeline.ImageRefreshWorker
  alias MediaCentaur.TestFactory
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.Topics

  setup do
    TmdbStubs.setup_tmdb_client(self())
    :ok
  end

  test "perform/1 refreshes artwork for the entity" do
    movie = TestFactory.create_movie()
    TestFactory.create_identifier(%{owner_id: movie.id, owner_type: :movie, source: :tmdb, external_id: "550"})
    TestFactory.create_linked_file(%{owner: movie, owner_type: :movie, watch_dir: "/media/movies"})
    TmdbStubs.stub_get_movie("550", %{poster_path: "/p.jpg"})
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_images())

    job = %Oban.Job{args: %{"entity_id" => movie.id, "entity_type" => "movie"}}
    assert :ok = ImageRefreshWorker.perform(job)
    assert_receive {:enqueue_images, %{entity_id: entity_id}}
    assert entity_id == movie.id
  end

  test "perform/1 cancels (no retry) when the entity is unidentified" do
    movie = TestFactory.create_movie()
    job = %Oban.Job{args: %{"entity_id" => movie.id, "entity_type" => "movie"}}
    assert {:cancel, :no_tmdb_id} = ImageRefreshWorker.perform(job)
  end
end
```

- [ ] **Step 2: Run test, verify it fails**

Run: `mix test test/media_centaur/pipeline/image_refresh_worker_test.exs`
Expected: FAIL — `ImageRefreshWorker` undefined.

- [ ] **Step 3: Implement the worker**

Create `lib/media_centaur/pipeline/image_refresh_worker.ex`:

```elixir
defmodule MediaCentaur.Pipeline.ImageRefreshWorker do
  @moduledoc """
  Oban worker that runs a per-entity artwork refresh
  (`ImageRefresh.refresh_entity/2`) off the LiveView lifecycle.

  Unique per `entity_id` for a short window so rapid double-clicks
  coalesce. `:no_tmdb_id` cancels (the entity needs a Rematch first, not
  a retry); transient TMDB errors return `{:error, _}` so Oban retries
  with backoff.
  """
  use Oban.Worker, queue: :images, unique: [period: 60, keys: [:entity_id]]

  alias MediaCentaur.Pipeline.ImageRefresh

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entity_id" => entity_id, "entity_type" => type}}) do
    case ImageRefresh.refresh_entity(entity_id, String.to_existing_atom(type)) do
      {:ok, _count} -> :ok
      {:error, :no_tmdb_id} -> {:cancel, :no_tmdb_id}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

- [ ] **Step 4: Add the queue**

In `config/config.exs:49`:

```elixir
  queues: [acquisition: 3, self_update: 1, images: 2],
```

- [ ] **Step 5: Run tests, verify pass**

Run: `mix test test/media_centaur/pipeline/image_refresh_worker_test.exs test/media_centaur/pipeline/image_refresh_test.exs`
Expected: PASS (all cases, incl. Task 3's inline-enqueue case).

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/pipeline/image_refresh.ex lib/media_centaur/pipeline/image_refresh_worker.ex config/config.exs test/media_centaur/pipeline/image_refresh_test.exs test/media_centaur/pipeline/image_refresh_worker_test.exs
git commit -m "feat: per-entity artwork refresh core + oban worker"
```

---

### Task 5: EntityModal flash mapping + event

**Files:**
- Modify: `lib/media_centaur_web/live/entity_modal.ex`
- Test: `test/media_centaur_web/live/entity_modal_test.exs` (or nearest existing modal/library live test)

- [ ] **Step 1: Write the failing test (pure mapping)**

```elixir
# test/media_centaur_web/live/entity_modal_test.exs (add describe block; create file if absent)
defmodule MediaCentaurWeb.Live.EntityModalTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Live.EntityModal

  describe "refresh_artwork_flash/1" do
    test "ok → info" do
      assert {:info, message} = EntityModal.refresh_artwork_flash({:ok, %Oban.Job{}})
      assert message =~ "Refreshing artwork"
    end

    test "no tmdb id → error pointing at Rematch" do
      assert {:error, message} = EntityModal.refresh_artwork_flash({:error, :no_tmdb_id})
      assert message =~ "Rematch"
    end

    test "other error → generic error" do
      assert {:error, _} = EntityModal.refresh_artwork_flash({:error, :boom})
    end
  end
end
```

- [ ] **Step 2: Run test, verify it fails**

Run: `mix test test/media_centaur_web/live/entity_modal_test.exs`
Expected: FAIL — `refresh_artwork_flash/1` undefined.

- [ ] **Step 3: Implement the pure helper + the event clause**

In `entity_modal.ex`, add a public pure function (outside the `__using__` quote, alongside other module functions):

```elixir
@doc """
Maps a `Pipeline.ImageRefresh.enqueue_refresh/2` result to a
`{flash_level, message}` pair for the detail-panel Refresh-artwork action.
"""
def refresh_artwork_flash({:ok, _job}), do: {:info, "Refreshing artwork from TMDB…"}
def refresh_artwork_flash({:error, :no_tmdb_id}), do: {:error, "No TMDB match — Rematch first."}
def refresh_artwork_flash({:error, _reason}), do: {:error, "Couldn't start artwork refresh."}
```

In the `__using__` quote, after the `"rematch"` clause (≈ line 203), add:

```elixir
      def handle_event("refresh_artwork", %{"id" => entity_id}, socket) do
        type = socket.assigns.selected_entry.entity.type
        result = MediaCentaur.Pipeline.ImageRefresh.enqueue_refresh(entity_id, type)
        {level, message} = MediaCentaurWeb.Live.EntityModal.refresh_artwork_flash(result)
        {:noreply, put_flash(socket, level, message)}
      end
```

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/media_centaur_web/live/entity_modal_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/entity_modal.ex test/media_centaur_web/live/entity_modal_test.exs
git commit -m "feat: wire refresh_artwork event + flash mapping into entity modal"
```

---

### Task 6: Detail-panel button

**Files:**
- Modify: `lib/media_centaur_web/components/detail_panel.ex:1215-1234` (Actions section of `info_view/1`)
- Check: `storybook/detail_panel/detail_panel.story.exs`

- [ ] **Step 1: Add the button after Rematch**

Inside the Actions `<div class="mt-2 flex items-center gap-2">`, after the Rematch `<.button>` (before the `!@tmdb_ready` `<p>`), add:

```heex
          <.button
            :if={@tmdb_ready}
            variant="ghost"
            size="sm"
            phx-click="refresh_artwork"
            phx-value-id={@entity.id}
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-photo-mini" class="size-4" /> Refresh artwork
          </.button>
```

- [ ] **Step 2: Verify storybook still compiles/renders**

The button is gated on the existing `@tmdb_ready` attr (no new attr), so the existing `info`-view variation covers it. Confirm:

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS. If `info_view` lacks a `tmdb_ready: true` variation that renders the Actions block, add/adjust the variation in `detail_panel.story.exs` so the new button renders, then re-run.

- [ ] **Step 3: Commit**

```bash
git add lib/media_centaur_web/components/detail_panel.ex storybook/detail_panel/detail_panel.story.exs
git commit -m "feat: add Refresh artwork button to detail manage view"
```

---

### Task 7: LiveView no-HTTP wiring test (regression net)

**Files:**
- Modify: nearest existing LiveView integration test that opens the modal in the `:info` view (e.g. a `library_live` modal test), or add a focused test.

- [ ] **Step 1: Write a LiveView test for the `:no_tmdb_id` flash**

Open the detail modal for an **unidentified** movie in `?detail_view=info` (or via the toggle event), click the Refresh-artwork button, and assert the flash contains "Rematch". This path performs no TMDB HTTP (pre-check returns before enqueue), so it is deterministic and stub-free.

> During execution: locate the existing modal LiveView test + the params/events used to open the info view (`toggle_detail_view`), and mirror that setup. Assert via `render(view) =~ "Rematch"` after `element(view, "[phx-click=refresh_artwork]") |> render_click()`.

- [ ] **Step 2: Run, verify red→green; Step 3: Commit**

---

## Self-review notes

- **Spec coverage:** mapper extraction (T1), context extraction (T2), ImageRefresh core + replace/gap semantics via import enqueue path (T3), Oban out-of-LiveView execution (T4), button + flash + no-tmdb gate (T5/T6), observability via `Log.info` (T3), LiveView regression net (T7). All spec sections covered.
- **Async/ADR-049:** no web-layer task spawn (MC0019-safe); Oban job outlives the LiveView; tests drive the inline path in the owning (test) process; LiveView test stays on the no-HTTP branch.
- **Type consistency:** `enqueue_refresh/2` and `refresh_entity/2` share the `entity_type` set; worker passes `to_string(type)`/`String.to_existing_atom/1`; `refresh_artwork_flash/1` matches `enqueue_refresh/2`'s return tuples exactly.
- **Final gate:** `mix precommit` then ship a patch release.
