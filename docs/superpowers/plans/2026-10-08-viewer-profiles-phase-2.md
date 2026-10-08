# Viewer Profiles Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every watching row — watch progress, extra progress, track memory, watch history — belongs to one profile, and every read and write of watching state names the profile, so two profiles' progress, resume, Continue Watching, history, track memory and finish prompts do not leak into each other.

**Architecture:** The profile id is a parameter of every function over watching state and is resolved in exactly two places: the web layer (`socket.assigns.profile.id`, from `Live.ProfileAware`) and the playback session (`MpvSession.profile_id`, captured at play and held for the session's life). Below those two layers nothing reads "the active profile". The four tables gain `profile_id` (FK to `profiles`, `ON DELETE CASCADE`) with composite unique keys; the hot-path progress table is keyed `{profile_id, playable_item_id}`; the two read models hold one snapshot per profile; the playback events carry `profile_id` so a page can ignore another profile's broadcasts. `Library`, `WatchHistory` and `Playback` gain no dependency on `Profiles`: a column is not a dependency, the id is opaque, and the cascade is the database's.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto + SQLite (`ecto_sqlite3`, table rebuilds for `NOT NULL`), ETS and `:persistent_term` projections (`MediaCentaur.Cache`), `mix precommit` via `~/scripts/agents/agent-mix`.

**Spec:** `docs/superpowers/specs/2026-10-06-viewer-profiles-design.md` § "Watching per profile (phase 2)". **Records:** ADR-078. **Campaign:** `campaigns/viewer-profiles.md`. **Phase 1 plan:** `docs/superpowers/plans/2026-10-06-viewer-profiles-phase-1.md` (format and working rules to match).

**Working rules for this plan**

- Work on branch `viewer-profiles` in the worktree `/home/shawn/src/media-centaur/media-centaur-app-viewer-profiles` (phase 1 is there, unmerged). The owner merges. Do not push.
- Never run `mix` directly; run `~/scripts/agents/agent-mix` (CLAUDE.md). `agent-mix test <file>` for one file, `agent-mix compile --warnings-as-errors` to let the compiler list the callers of a changed signature, `agent-mix precommit` at the end of every task that changes Elixir.
- Test first: write the failing test, run it, see it fail for the stated reason, implement, run it, commit.
- Every test module states `async:`; DB tests use `MediaCentaur.DataCase`/`MediaCentaurWeb.ConnCase` with `async: false`; pure tests use `MediaCentaur.Case, async: true`.
- Generic names in fixtures (`Sample Movie`, `Sample Show`, `Ana`); no real people, no real titles.
- Commit per task with a conventional message.
- `Exqlite "Database busy"` under machine load, an `Exqlite` client-exited disconnect, and the context-map tests timing out are normal for SQLite under load: re-run the file alone and move on (owner, 2026-10-08).

---

## Unify pass (2026-10-08)

**Core idea.** Watching state is a fact about a *(profile, title)* pair. The profile id is a parameter of every read and write of watching state and is resolved in two places only: the web layer and the playback session.

**Greenfield shape.** Four tables with `profile_id NOT NULL` and composite unique keys. One way to load a title's progress: `ProgressRecords.list_for_container(profile_id, type, id)`. A hot-path table keyed by the pair. Read models keyed by profile, rebuilt whole for the profiles that have rows (read from the rows themselves, so no `Profiles` dependency). Playback captures the profile at play, writes under it, names it in every event, and carries it in the mpv socket's name so a backend restart recovers the session to the same profile.

**Diff against the code — every incoherence and its disposition.**

| Found | Disposition |
|---|---|
| `has_one :watch_progress` on `PlayableItem`, and `has_one … through` on `Movie`, `Episode`, `VideoObject`; preloaded by `Containers.full_preloads`, `Browser`, `HomeFeed`, `Deletion`; read by `EntityShape.extract_progress/2` (Resolver, NextEpisode, Browser). With a profile the cardinality is one-to-many, so `has_one` would return an arbitrary profile's row. | **Fix now (Task 2):** delete the four associations, `extract_progress/2` and every `:watch_progress` preload. Resolver and NextEpisode read progress through `ProgressRecords.list_for_container/2`, the path the detail modal already uses. Browser entries stop carrying progress (their only consumer, `Views.Browse`, discards it). `EntityCascade.destroy_progress/1` goes: the `PlayableItem → WatchProgress` FK cascade already deletes the rows, as its own comment states. |
| `WatchHistory.delete_event!/2`'s `reset_progress: true` option has no caller in `lib/`; only its own tests use it. | **Fix now (Task 6):** remove the option and `reset_watch_progress/1`, with its tests. No compatibility path. |
| `Library.Views.ContinueWatching` is one rank-keyed ETS table built from a profile-less `list_in_progress/1`; `WatchHistory.Views.Summary` is one `:persistent_term` snapshot. | **Fix now (Tasks 3, 6):** Continue Watching becomes a `:set` of `{profile_id, items}`; Summary a `%{profile_id => SummaryData}` under its one key. Both rebuild whole, for the profile ids present in their source table (`ProgressRecords.profile_ids_with_progress/0`, `WatchHistory.profile_ids_with_events/0`). The derived messages are unchanged; a page re-reads for its own profile. `RankedProjection` keeps the three rank-keyed projections. |
| `Library.Progress.Worker`'s ETS key is `playable_item_id`; `ProgressTicked` / `ProgressFlushed` name only the item. | **Fix now (Task 3):** key `{profile_id, playable_item_id}`; the row map and both events carry `profile_id`. |
| `SessionRecovery` rebuilds a session from `media-centaur-<entity_id>.sock` alone; a profile would be lost across a backend restart. | **Fix now (Task 1):** the socket is `media-centaur-<entity_id>.<profile_id>.sock`. A socket in the old shape (an mpv started by the outgoing release and still running across the upgrade) is skipped with a log line rather than recovered under a guessed profile; no `Profiles` dependency in `Playback`. One-release edge. |
| The Status page's `PlaybackActivity` (hours watched, titles, streak, recent five) is install-wide per the spec; the spec's text files it under "the History page" by mistake. The spec also lists `HeroCandidates` among the read models to key, but it never reads watching state. | **Record (Task 7):** spec amendments. `WatchHistory`'s readers take a `scope` of a profile id or `:all`; `PlaybackActivity` reads `:all`; `HeroCandidates` is untouched. |
| `EntityView.watch_progress: []` and `DetailItem … watch_progress: []` are dead fields predating this campaign ("progress is an overlay"). | **Scheduled, not here:** named in the campaign file as a cleanup; not part of the profile sweep. |

**Scope cost.** The `has_one` removal (Task 2) and the socket rename (Task 1) are the two pieces the spec did not list. Both are small and strictly simplifying; both are recorded in the campaign's Decisions for the owner.

---

## Glossary additions

| Term | Meaning |
|---|---|
| **Watching scope** | What a `WatchHistory` reader is asked for: one profile's id, or `:all` for the install-wide view the Status page shows. Type `MediaCentaur.WatchHistory.scope()`. |
| **Profile-keyed read model** | A projection whose snapshot is held per profile and read with the profile id: `Library.Views.ContinueWatching` (ETS `{profile_id, items}`), `WatchHistory.Views.Summary` (`%{profile_id => SummaryData}`). Rebuilt whole. |
| **Legacy socket** | An mpv IPC socket named `media-centaur-<entity_id>.sock`, the shape before phase 2. Recovery skips it. |

---

## File structure

| File | Responsibility |
|---|---|
| `priv/repo/migrations/20261008120000_watch_progress_per_profile.exs` | Rebuild `library_watch_progress` with `profile_id`, assign existing rows to the oldest profile, unique `(profile_id, playable_item_id)`. |
| `priv/repo/migrations/20261008120001_extra_progress_per_profile.exs` | Same for `library_extra_progress`; unique `(profile_id, extra_id)`; the extra FK gains `ON DELETE CASCADE`. |
| `priv/repo/migrations/20261008120002_media_track_overrides_per_profile.exs` | Same for `library_media_track_overrides`; unique `(profile_id, owner_type, owner_id)`. |
| `priv/repo/migrations/20261008120003_watch_history_events_per_profile.exs` | Same for `watch_history_events`; index `(profile_id, completed_at)`. |
| `lib/media_centaur/library/watch_progress.ex`, `extra_progress.ex`, `media_track_override.ex`, `lib/media_centaur/watch_history/event.ex` | `field :profile_id, Ecto.UUID`, cast, required, composite unique constraint. |
| `lib/media_centaur/library/progress_records.ex` | Every WatchProgress / ExtraProgress query takes the profile first; `profile_ids_with_progress/0`. |
| `lib/media_centaur/library/progress.ex`, `progress/worker.ex`, `progress/events.ex` | Hot path keyed `{profile_id, playable_item_id}`. |
| `lib/media_centaur/library/home_feed.ex`, `lib/media_centaur/library.ex` | `list_in_progress(profile_id, opts)`; every WatchProgress subquery filtered by profile; leaf progress by one query, not a preload. |
| `lib/media_centaur/library/views/continue_watching.ex`, `views.ex`, `views/ranked_projection.ex` | Profile-keyed Continue Watching; `Views.continue_watching(profile_id, opts)`. |
| `lib/media_centaur/library/media_track_overrides.ex` | `get/3`, `upsert/4`, `clear/3`, `put_on_entity/2` take the profile first. |
| `lib/media_centaur/library/entity_shape.ex`, `containers.ex`, `browser.ex`, `entity_cascade.ex`, `deletion.ex`, `type_resolver.ex`, `playable_item.ex`, `movie.ex`, `episode.ex`, `video_object.ex` | The `has_one :watch_progress` path removed. |
| `lib/media_centaur/playback.ex`, `playback/resolver.ex`, `next_episode.ex`, `sessions.ex`, `mpv_session.ex`, `session_recovery.ex`, `language_context.ex`, `progress_broadcaster.ex`, `events.ex` | The profile rides play → params → session → writes → events; the socket name carries it. |
| `lib/media_centaur/watch_history.ex`, `watch_history/rewatch.ex`, `recorder.ex`, `views.ex`, `views/summary.ex`, `views/playback_activity.ex` | Scoped readers; the recorder writes the record's profile; Summary per profile; PlaybackActivity `:all`. |
| `lib/media_centaur_web/live/title_detail_host.ex`, `title_detail_host/library_half.ex`, `library_events.ex`, `view_model/{series,collection,leaf}_detail.ex`, `lib/media_centaur/library/modal_entry.ex` | The open detail composes for the socket's profile; broadcasts from another profile are ignored. |
| `lib/media_centaur_web/live/home_live.ex`, `library_live.ex`, `watch_history_live.ex` | Pages read for `socket.assigns.profile.id` in `handle_params`/`handle_info` (never `mount`, per `ProfileAware`). |
| `lib/media_centaur/showcase.ex`, `lib/media_centaur/profile/loader.ex` | Seed under the owner profile. |
| `test/support/factory.ex` | `owner_profile_id/0`; the four watching factories default to it. |
| `docs/superpowers/specs/2026-10-06-viewer-profiles-design.md`, `campaigns/viewer-profiles.md`, `lib/media_centaur/topics.ex` | Amendments, status, the topics table. |

---

### Task 0: Preflight in the worktree

- [ ] **Step 1: Confirm the branch and a clean tree**

```bash
cd /home/shawn/src/media-centaur/media-centaur-app-viewer-profiles
git status --short
git log --oneline -1
```

Expected: no output from `status`; HEAD is `f6ed5667` or later on `viewer-profiles`.

- [ ] **Step 2: Confirm the suite is green before any change**

Run: `~/scripts/agents/agent-mix test 2>&1 | tail -5`
Expected: `0 failures` (a `Database busy` or a context-map timeout under load: re-run that file alone).

---

### Task 1: Playback carries the profile

The profile reaches playback at `Playback.play/2`, lives in the session struct and the socket name, and is named in every `playback:events` struct. Nothing in the data layer changes yet; the web layer passes `socket.assigns.profile.id` and ignores another profile's broadcasts.

**Files:**
- Modify: `lib/media_centaur/playback.ex`, `lib/media_centaur/playback/sessions.ex`, `lib/media_centaur/playback/mpv_session.ex`, `lib/media_centaur/playback/session_recovery.ex`, `lib/media_centaur/playback/events.ex`, `lib/media_centaur/playback/progress_broadcaster.ex`
- Modify: `lib/media_centaur_web/live/title_detail_host.ex`, `lib/media_centaur_web/live/title_detail_host/library_events.ex`, `lib/media_centaur_web/live/library_live.ex`
- Test: `test/media_centaur/playback/mpv_session_test.exs`, `test/media_centaur/playback/session_recovery_test.exs`, `test/media_centaur/playback/sessions_test.exs`, `test/media_centaur_web/live/title_detail_host/finish_test.exs`, `test/media_centaur_web/live/home_live_test.exs`, `test/media_centaur_web/live/library_live_test.exs`, `test/media_centaur_web/live/status_live_test.exs`, `test/media_centaur/library/progress_test.exs` (event constructions)

- [ ] **Step 1: Write the failing tests**

In `test/media_centaur/playback/mpv_session_test.exs`, the `session_ended/1` test (around line 112) becomes:

```elixir
    test "session_ended/1 names the session's entity, profile and completed set" do
      profile_id = Ecto.UUID.generate()

      state =
        struct!(MpvSession, %{
          entity_id: "movie-1",
          profile_id: profile_id,
          completed: MapSet.new([{:movie, "movie-1"}])
        })

      assert %SessionEnded{entity_id: "movie-1", profile_id: ^profile_id, completed: completed} =
               MpvSession.session_ended(state)

      assert MapSet.member?(completed, {:movie, "movie-1"})
    end
```

In `test/media_centaur/playback/session_recovery_test.exs`, the helper and two tests:

```elixir
  defp socket_path(dir, entity_id, profile_id),
    do: Path.join(dir, "media-centaur-#{entity_id}.#{profile_id}.sock")
```

Update every existing call of `socket_path/2` and `touch_dead_socket/2` to pass a `profile_id` (generate one per test with `Ecto.UUID.generate()`), and in the test that recovers a live session assert the params carry it:

```elixir
      assert [%{entity_id: ^entity_id, profile_id: ^profile_id, content_url: ^path}] =
               SessionRecovery.recover_all()
```

Add one test:

```elixir
    test "a legacy socket without a profile segment is skipped and left in place",
         %{socket_dir: socket_dir} do
      entity_id = Ecto.UUID.generate()
      legacy = Path.join(socket_dir, "media-centaur-#{entity_id}.sock")
      File.write!(legacy, "")

      assert SessionRecovery.recover_all() == []
      assert File.exists?(legacy)
    end
```

In `test/media_centaur/playback/sessions_test.exs`, add `profile_id: Ecto.UUID.generate()` to `params`.

In `test/media_centaur_web/live/title_detail_host/finish_test.exs`, `ended/2` gains a profile:

```elixir
  defp ended(entity_id, completed),
    do: %SessionEnded{entity_id: entity_id, profile_id: "p-1", completed: MapSet.new(completed)}
```

In `test/media_centaur_web/live/home_live_test.exs`, the `finish/2` helper (around line 673) takes the profile and a new test proves another profile's finish is ignored:

```elixir
    defp finish(movie, profile_id, completed \\ nil) do
      Events.broadcast(%SessionEnded{
        entity_id: movie.id,
        profile_id: profile_id,
        completed: MapSet.new(completed || [{:movie, movie.id}])
      })
    end

    test "opens the finished movie with the prompt", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, "/")

      finish(movie, owner_profile_id())

      assert_patch(view, "/?entity=#{movie.id}")
      assert render(view) =~ ~s|data-state="open"|
      assert has_element?(view, "#finish-prompt")
      assert render(view) =~ "You finished"
    end

    test "a session another profile finished does not open the prompt here", %{conn: conn, movie: movie} do
      ana = create_profile(%{name: "Ana"})
      {:ok, view, _html} = live_async!(conn, "/")

      finish(movie, ana.id)

      refute has_element?(view, "#finish-prompt")
      refute render(view) =~ ~s|data-state="open"|
    end
```

Every other `finish(movie)` / `finish(movie, [...])` call in that describe passes `owner_profile_id()` as the second argument. `owner_profile_id/0` is added to the factory in this task (Step 3) because `ConnCase` tests mount as the owner profile "Me" by default.

Every `%PlaybackStateChanged{…}`, `%EntityProgressUpdated{…}`, `%ExtraProgressUpdated{…}`, `%TrackOverrideChanged{…}` and `%SessionEnded{…}` constructed in `test/media_centaur_web/live/library_live_test.exs`, `status_live_test.exs`, `home_live_test.exs` gains `profile_id: owner_profile_id()`. `ProgressTicked`/`ProgressFlushed` in `progress_test.exs` are Task 3's.

- [ ] **Step 2: Run them to see them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/playback/mpv_session_test.exs test/media_centaur/playback/session_recovery_test.exs test/media_centaur_web/live/title_detail_host/finish_test.exs`
Expected: compile errors — `profile_id` is not a key of `SessionEnded` / `MpvSession`; `owner_profile_id/0` undefined.

- [ ] **Step 3: The factory's owner profile**

In `test/support/factory.ex`, next to `create_profile/1`:

```elixir
  @doc """
  The owner profile the phase 1 migration created ("Me"): the default
  profile of every watching-row factory, and the profile a `ConnCase`
  test mounts as when it does not pick one with `with_profile/2`.
  """
  def owner_profile_id, do: MediaCentaur.Profiles.list() |> hd() |> Map.fetch!(:id)
```

- [ ] **Step 4: The events**

In `lib/media_centaur/playback/events.ex`, every struct gains `profile_id` as the second field, enforced:

```elixir
  defmodule EntityProgressUpdated do
    @moduledoc "Persisted progress for an entity (movie / episode root) changed, for one profile."
    @enforce_keys [:entity_id, :profile_id, :summary, :resume_target, :changed_record, :last_activity_at]
    defstruct [:entity_id, :profile_id, :summary, :resume_target, :changed_record, :last_activity_at]

    @type t :: %__MODULE__{
            entity_id: String.t(),
            profile_id: String.t(),
            summary: map(),
            resume_target: map() | nil,
            changed_record: map() | nil,
            last_activity_at: DateTime.t()
          }
  end
```

Apply the same to `ExtraProgressUpdated` (`[:entity_id, :profile_id, :extra_id, :progress]`), `PlaybackStateChanged` (`[:entity_id, :profile_id, :state, :now_playing, :started_at]`; fix its type: `started_at: integer()` — it is `System.monotonic_time(:millisecond)`), `SessionEnded` (`[:entity_id, :profile_id, :completed]`) and `TrackOverrideChanged` (`[:profile_id, :owner_type, :owner_id]`). `PlaybackFailed` is unchanged: a failure to start is not watching state. Add to the module doc one sentence: "Every event about watching state names the `profile_id` it was recorded under (ADR-078); a subscriber holding profile-scoped state compares it with its own."

- [ ] **Step 5: `Playback.play/2`, the params, the session, the socket**

`lib/media_centaur/playback.ex`:

```elixir
  @doc """
  Starts playback of `uuid` for `profile_id`, the session's active profile
  (ADR-078). The profile is captured here and held by the session for its
  life: a switch mid-film does not re-home the progress.
  """
  @spec play(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def play(profile_id, uuid) when is_binary(profile_id) and is_binary(uuid) do
    Log.info(:playback, "play requested — #{Format.short_id(uuid)}")

    case Resolver.resolve(uuid) do
      {:ok, play_params} ->
        Sessions.play(Map.put(play_params, :profile_id, profile_id))

      {:error, reason} ->
        Log.info(:playback, "play failed — #{Format.short_id(uuid)}, #{reason}")
        {:error, reason}
    end
  end
```

`lib/media_centaur/playback/sessions.ex`: the `play/1` doc gains "`params.profile_id` is required: the profile the session records under." No code change.

`lib/media_centaur/playback/mpv_session.ex`:
- `defstruct` gains `:profile_id` right after `:entity_id`.
- `init/1`: `profile_id: params.profile_id` in the struct, and the socket path becomes

```elixir
    socket_path = Path.join(socket_dir, socket_name(params.entity_id, params.profile_id))
```

with, in the module (public, used by recovery):

```elixir
  @doc "The IPC socket file name for a session: entity and profile, both UUIDs, dot-separated."
  @spec socket_name(Ecto.UUID.t(), Ecto.UUID.t()) :: String.t()
  def socket_name(entity_id, profile_id), do: "media-centaur-#{entity_id}.#{profile_id}.sock"
```

- `session_ended/1`: `%Events.SessionEnded{entity_id: state.entity_id, profile_id: state.profile_id, completed: state.completed}`.
- `broadcast_state_changed/2`: add `profile_id: session.profile_id`.
- `persist_track_override/2` becomes `persist_track_override(state, attrs)` and reads `state.language_context.owner_type`, `state.language_context.owner_id`; the `TrackOverrideChanged` it broadcasts carries `profile_id: state.profile_id`. (Its `MediaTrackOverrides.upsert/3` call stays as is until Task 5.)
- `reset_for_file/4` leaves `profile_id` untouched (it is not in its reset list; confirm, do not add it).
- Module doc: the socket line becomes "The socket path is `media-centaur-{entity_id}.{profile_id}.sock` in the configured socket dir (`socket_name/2`)".

`lib/media_centaur/playback/progress_broadcaster.ex`: `broadcast/2` becomes `broadcast(profile_id, entity_id, changed)` and `broadcast_extra/2` becomes `broadcast_extra(profile_id, entity_id, extra_id)`; each puts `profile_id` into the struct it broadcasts. The reads inside stay as they are until Tasks 3 and 4. Update the four call sites in `mpv_session.ex` (`finalize/1` ×2, `persist_extra_progress/2`, `persist_entity_progress/2`) to pass `session.profile_id` / `state.profile_id`, and the two in `library_events.ex` (Step 7).

`lib/media_centaur/playback/session_recovery.ex`:

```elixir
  @socket_prefix "media-centaur-"
  @socket_suffix ".sock"
  @connect_timeout_ms 500

  def recover_all do
    socket_dir = MediaCentaur.Settings.Config.get(:mpv_socket_dir)
    pattern = Path.join(socket_dir, "#{@socket_prefix}*#{@socket_suffix}")

    Enum.flat_map(Path.wildcard(pattern), fn socket_path ->
      case session_ids(socket_path) do
        {:ok, entity_id, profile_id} -> recover(socket_path, entity_id, profile_id)
        :legacy -> skip_legacy(socket_path)
      end
    end)
  end

  defp recover(socket_path, entity_id, profile_id) do
    case recover_from_socket(socket_path, entity_id) do
      {:ok, params} ->
        Log.info(:playback, "recovery: found live session for #{params[:entity_name] || entity_id}")
        [Map.put(params, :profile_id, profile_id)]

      :skip ->
        []
    end
  end

  # A socket named by the outgoing release, `media-centaur-<entity>.sock`,
  # carries no profile. It is not recovered under a guessed one: mpv keeps
  # playing, the backend does not track it, and the file goes when mpv
  # exits or on the next boot's dead-socket sweep. One-release edge.
  defp skip_legacy(socket_path) do
    Log.info(:playback, "recovery: skipping legacy socket without a profile — #{Path.basename(socket_path)}")
    []
  end

  # `media-centaur-<entity_id>.<profile_id>.sock` → the two ids; the old
  # one-id shape → `:legacy`. UUIDs carry no dots, so the split is exact.
  defp session_ids(socket_path) do
    socket_path
    |> Path.basename()
    |> String.trim_leading(@socket_prefix)
    |> String.trim_trailing(@socket_suffix)
    |> String.split(".")
    |> case do
      [entity_id, profile_id] -> {:ok, entity_id, profile_id}
      [_entity_id] -> :legacy
    end
  end
```

Delete `extract_entity_id/1`. Update the moduledoc's socket line to the new shape. `recover_from_socket/2`, `query_and_resolve/2` and `build_params/3` are unchanged.

- [ ] **Step 6: The host ignores another profile's broadcasts; the finish prompt is the watcher's**

`lib/media_centaur_web/live/title_detail_host.ex`, in the `react/2` clauses:

```elixir
  # UIDR-052: a finished title opens with the prompt — the modal may be
  # closed. `:stopped` arrived first (same session, same topic), so the
  # playing set no longer guards its delete. Only the profile that
  # watched is asked (ADR-078): another profile's session, or a page on
  # the pick path with no profile yet, leaves this page as it was.
  defp react(
         {:session_ended, %{profile_id: profile_id} = event},
         %{assigns: %{profile: %{id: profile_id}}} = socket
       ) do
    open_id = DetailLogic.subject_id(socket.assigns.title_detail)
    latest_aired = if Finish.episodes?(event), do: latest_aired_episode(event.entity_id)

    case Finish.reaction(event, open_id, FinishPrompt.enabled?(), latest_aired) do
      :ignore -> socket
      {:in_place, id} -> assign(socket, :finished_id, id)
      {:open, id} -> socket |> assign(:finished_id, id) |> push_patch(to: path(socket, entity: id))
    end
  end

  defp react({:session_ended, _another_profile}, socket), do: socket

  defp react(_message, %{assigns: %{title_detail: nil}} = socket), do: socket

  # The open detail holds one profile's progress and track memory; a
  # broadcast about another profile's is not merged into it.
  defp react({tag, %{profile_id: other}}, %{assigns: %{profile: %{id: mine}}} = socket)
       when tag in [:entity_progress_updated, :extra_progress_updated, :track_override_changed] and
              other != mine,
       do: socket
```

followed by the existing three merge clauses unchanged. The `:playback_state_changed` clause stays unfiltered: whether mpv is playing a file is an install-wide fact that guards delete.

`lib/media_centaur_web/live/library_live.ex`, the progress handler:

```elixir
  def handle_info({:entity_progress_updated, %{entity_id: entity_id, profile_id: profile_id}}, socket)
      when profile_id == socket.assigns.profile.id do
    …existing body…
  end

  def handle_info({:entity_progress_updated, _another_profile}, socket), do: {:noreply, socket}
```

(`socket.assigns.profile` exists on every connected `LibraryLive`: the pick path redirects in the first `handle_params`, before any broadcast is handled.)

- [ ] **Step 7: Play from the socket's profile**

`lib/media_centaur_web/live/title_detail_host/library_events.ex`:

```elixir
  def play(socket, id) do
    case Playback.play(socket.assigns.profile.id, id) do
```

and the two broadcaster calls: `ProgressBroadcaster.broadcast(profile_id, entity_id, changed_record)` in `toggle_watch_progress/4` and `ProgressBroadcaster.broadcast_extra(profile_id, entity_id, extra_id)` in `toggle_extra_watched/3` — thread `socket.assigns.profile.id` from the two `handle/3` clauses as a first argument to both private functions (the data reads inside them change in Tasks 3 and 4).

- [ ] **Step 8: Compile, then run the touched tests**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors`
Expected: clean. If it names a `%SessionEnded{}` or `%PlaybackStateChanged{}` construction you missed, add `profile_id` there.

Run: `~/scripts/agents/agent-mix test test/media_centaur/playback test/media_centaur_web/live/title_detail_host test/media_centaur_web/live/home_live_test.exs test/media_centaur_web/live/library_live_test.exs test/media_centaur_web/live/status_live_test.exs`
Expected: PASS.

- [ ] **Step 9: Precommit and commit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: clean. MC0012 is satisfied (every event still goes through `Events.broadcast/1`).

```bash
git add -A
git commit -m "feat(playback): the session captures the profile and names it in every event (ADR-078)"
```

---

### Task 2: One way to load a title's progress

Remove the `has_one :watch_progress` path. After this task the only readers of `library_watch_progress` are `ProgressRecords`, `Progress`, `Progress.Worker` and `HomeFeed`.

**Files:**
- Modify: `lib/media_centaur/library/playable_item.ex`, `movie.ex`, `episode.ex`, `video_object.ex` (drop the association and its comment)
- Modify: `lib/media_centaur/library/containers.ex`, `browser.ex` (preload lists), `entity_shape.ex` (delete `extract_progress/2` and helpers), `type_resolver.ex` (doc example), `entity_cascade.ex`, `deletion.ex`, `home_feed.ex`
- Modify: `lib/media_centaur/playback/resolver.ex`, `next_episode.ex`
- Modify: `lib/media_centaur/library/progress_records.ex` (`progress_by_leaf/2`)
- Test: `test/media_centaur/library/entity_test.exs`, `entity_shape_test.exs`, `browser_test.exs`, `test/media_centaur/playback/resolver_test.exs`, `next_episode_test.exs`, `test/media_centaur/library/deletion_test.exs`

- [ ] **Step 1: Delete the tests of the removed path and write the one new test**

- `test/media_centaur/library/entity_shape_test.exs`: delete the four `describe "extract_progress/2 — …"` blocks.
- `test/media_centaur/library/entity_test.exs`: delete `test "preloads watch_progress"`.
- `test/media_centaur/library/browser_test.exs:19`: `assert [%{entity: fetched}] = results` (Browser entries no longer carry progress).

New, in `test/media_centaur/library/progress_records_test.exs`:

```elixir
  describe "progress_by_leaf/2" do
    test "one query maps each leaf container to its progress row; leaves without one are absent" do
      watched = create_standalone_movie(%{name: "Watched"})
      fresh = create_standalone_movie(%{name: "Fresh"})
      create_watch_progress(%{movie_id: watched.id, position_seconds: 30.0, duration_seconds: 100.0})

      by_id = Library.ProgressRecords.progress_by_leaf(:movie, [watched.id, fresh.id])

      assert %{position_seconds: 30.0} = by_id[watched.id]
      refute Map.has_key?(by_id, fresh.id)
    end
  end
```

- [ ] **Step 2: Run to see the new test fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/library/progress_records_test.exs`
Expected: FAIL — `progress_by_leaf/2` undefined.

- [ ] **Step 3: `ProgressRecords.progress_by_leaf/2`**

In `lib/media_centaur/library/progress_records.ex`, next to `list_for_container/2`:

```elixir
  @doc """
  The progress row of each leaf container (movie, video object) in
  `ids`, keyed by container id, in one query. A leaf without a row is
  absent. The read Continue Watching uses for its single-leaf entries.
  """
  @spec progress_by_leaf(:movie | :video_object, [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => WatchProgress.t()}
  def progress_by_leaf(_container_type, []), do: %{}

  def progress_by_leaf(container_type, ids) when container_type in [:movie, :video_object] do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id and pi.container_type == ^container_type and pi.container_id in ^ids,
      select: {pi.container_id, wp}
    )
    |> Repo.all()
    |> Map.new()
  end
```

- [ ] **Step 4: Remove the associations and preloads**

- `playable_item.ex:62-64`, `movie.ex:99-106`, `episode.ex:68-74`, `video_object.ex:60-67`: delete the `has_one :watch_progress …` line and the comment block above it.
- `containers.ex`: remove `:watch_progress` from the four `@*_full_preloads` lists (episodes: `[:images] ++ @leaf_file_path_preload`; movies likewise; movie and video object lists drop the bare atom).
- `browser.ex`: remove `:watch_progress` from the five preload lists. `build_entry_for/2` and `build_entry_from_normalized/2` collapse to

```elixir
  defp build_entry_for(record, type) do
    entity = record |> EntityShape.to_entity_view(type) |> pre_sort_children()
    %{entity: entity}
  end
```

(keep whatever `build_entry_from_normalized/2` did to `entity` besides progress — read it first; `ProgressSummary` and `progress_records` go). Update the `@doc` of `fetch_all_typed_entries/1`: "Returns a list of `%{entity: entity}`." Remove the now-unused `ProgressSummary` alias.
- `lib/media_centaur/library/views/browse.ex:104`: the comment "`entry` is the rich `%{entity:, progress:, progress_records:}` map" becomes "`entry` is `%{entity:}` from `Browser.fetch_all_typed_entries/0`".
- `entity_shape.ex`: delete `extract_progress/2`, `extract_episode_progress/1`, `extract_movie_progress/1`, `wrap_progress/3`, `attach_container/3` and the `@doc` above them; in the moduledoc, drop the "walks seasons > episodes > watch_progress" lines (126-134).
- `type_resolver.ex:47`: the doc example becomes `TypeResolver.resolve_container(uuid, preload: [tv_series: [:images, seasons: [:episodes]]])`.
- `entity_cascade.ex`: delete `destroy_progress/1` (all four clauses, lines 266-273) and the call in `destroy_supporting_rows!/2`; rewrite the comment above `destroy_leaf!/2` to: "Order: supporting rows first, then PlayableItem rows; the `PlayableItem → WatchProgress` FK (`on_delete: :delete_all`) takes the progress rows of every profile with the items." Remove `WatchProgress` from the alias list only if nothing else in the module uses it (`@tables_in_delete_order` does — keep it).
- `deletion.ex:194,209`: drop `:watch_progress` from the two `load:` lists and the two `destroy_progress(…)` calls; remove `destroy_progress` from the `import … only:` list if it names it.

- [ ] **Step 5: HomeFeed's leaf entries come from one query**

In `lib/media_centaur/library/home_feed.ex`:

```elixir
  defp fetch_in_progress_movies(limit) do
    movies =
      from(m in Movie, …unchanged query…)
      |> Repo.all()
      |> Repo.preload([:images, movie_series: :images])

    progress_by_id = ProgressRecords.progress_by_leaf(:movie, Enum.map(movies, & &1.id))

    movies
    |> Enum.map(&build_in_progress_movie_entry(&1, Map.get(progress_by_id, &1.id)))
    |> Enum.reject(&is_nil/1)
  end

  defp build_in_progress_movie_entry(movie, progress) do
    single_leaf_entry(%{…unchanged entity map…}, progress)
  end
```

and the same shape for `fetch_in_progress_video_objects/1` (`Repo.preload([:images])`, `progress_by_leaf(:video_object, ids)`, `single_leaf_entry(entity, Map.get(progress_by_id, video_object.id))`). Add `ProgressRecords` to the `alias MediaCentaur.Library.{…}` list.

- [ ] **Step 6: Resolver and NextEpisode read progress through ProgressRecords**

`lib/media_centaur/playback/resolver.ex`:

```elixir
  defp resolve_typed_entity(uuid) do
    case TypeResolver.resolve_container(uuid, preload: Library.Containers.full_preloads_by_type()) do
      {:ok, type, record} ->
        {:ok, EntityShape.to_entity_view(record, type), ProgressRecords.list_for_container(type, record.id)}

      :not_found ->
        :not_found
    end
  end
```

In `resolve_episode_playback/1`: `progress_records = ProgressRecords.list_for_container(:tv_series, season.tv_series_id)`. In `resolve_movie_parent/1`: `ProgressRecords.list_for_container(:movie_series, movie.movie_series_id)` and `ProgressRecords.list_for_container(:movie, movie.id)`.

`lib/media_centaur/playback/next_episode.ex`, `resolve/1`: `progress_records = ProgressRecords.list_for_container(:tv_series, season.tv_series_id)`.

- [ ] **Step 7: Compile, run the Library and Playback suites**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors`
Expected: clean (an unused alias of `EntityShape` or `ProgressSummary` is a warning — remove it).

Run: `~/scripts/agents/agent-mix test test/media_centaur/library test/media_centaur/playback test/media_centaur_web/no_db_on_render_test.exs`
Expected: PASS. `no_db_on_render_test` asserts an upper bound on render queries; fewer is fine. `deletion_test` "deletes episode with recorded watch progress without FK violation" passes through the FK cascade.

- [ ] **Step 8: Precommit and commit**

Run: `~/scripts/agents/agent-mix precommit`

```bash
git add -A
git commit -m "refactor(library): progress is read through ProgressRecords only; the has_one path goes"
```

---

### Task 3: Watch progress per profile

The migration, the schema, `ProgressRecords`, the hot path, the Continue Watching feed and projection, and every caller. The largest task; the compiler is the checklist.

**Files:**
- Create: `priv/repo/migrations/20261008120000_watch_progress_per_profile.exs`
- Modify: `lib/media_centaur/library/watch_progress.ex`, `progress_records.ex`, `progress.ex`, `progress/worker.ex`, `progress/events.ex`, `home_feed.ex`, `library.ex`, `views/continue_watching.ex`, `views.ex`, `views/ranked_projection.ex` (moduledoc), `modal_entry.ex`
- Modify: `lib/media_centaur/playback/resolver.ex`, `next_episode.ex`, `mpv_session.ex`, `progress_broadcaster.ex`
- Modify: `lib/media_centaur_web/live/title_detail_host.ex`, `title_detail_host/library_half.ex`, `title_detail_host/library_events.ex`, `view_model/series_detail.ex`, `collection_detail.ex`, `leaf_detail.ex`, `live/library_live.ex`, `live/home_live.ex`
- Modify: `lib/media_centaur/showcase.ex`, `lib/media_centaur/profile/loader.ex`, `lib/media_centaur/profile/suites/continue_watching_suite.ex`, `suite.ex`
- Modify: `test/support/factory.ex`
- Test: `test/media_centaur/library/progress_records_test.exs`, `progress_test.exs`, `views/continue_watching_test.exs`, `test/media_centaur/playback/resolver_test.exs`, `test/media_centaur_web/live/home_live_test.exs`, and every test the compiler names

- [ ] **Step 1: Write the failing isolation tests**

`test/media_centaur/library/progress_records_test.exs`:

```elixir
  describe "two profiles" do
    setup do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      ana = create_profile(%{name: "Ana"})
      %{movie: movie, me: owner_profile_id(), ana: ana.id}
    end

    test "each profile has its own row for the same title", %{movie: movie, me: me, ana: ana} do
      {:ok, mine} = Library.ProgressRecords.find_or_create_for_container(me, :movie, movie.id, %{position_seconds: 10.0})
      {:ok, hers} = Library.ProgressRecords.find_or_create_for_container(ana, :movie, movie.id, %{position_seconds: 90.0})

      assert mine.id != hers.id
      assert mine.playable_item_id == hers.playable_item_id
      assert {:ok, %{position_seconds: 10.0}} = Library.ProgressRecords.fetch_for_container(me, :movie, movie.id)
      assert {:ok, %{position_seconds: 90.0}} = Library.ProgressRecords.fetch_for_container(ana, :movie, movie.id)
      assert [%{position_seconds: 10.0}] = Library.ProgressRecords.list_for_container(me, :movie, movie.id)
      assert %{^movie_id => %{episode_position_seconds: 90.0}} = Library.ProgressRecords.summaries(ana, [movie.id])
    end

    test "a profile without a row reads nothing", %{movie: movie, me: me, ana: ana} do
      {:ok, _} = Library.ProgressRecords.find_or_create_for_container(me, :movie, movie.id, %{position_seconds: 10.0})

      assert {:error, :not_found} = Library.ProgressRecords.fetch_for_container(ana, :movie, movie.id)
      assert Library.ProgressRecords.list_for_container(ana, :movie, movie.id) == []
      assert Library.ProgressRecords.summaries(ana, [movie.id]) == %{}
      assert Library.ProgressRecords.profile_ids_with_progress() == [me]
    end

    test "removing a profile removes its rows and no one else's", %{movie: movie, me: me, ana: ana} do
      {:ok, _} = Library.ProgressRecords.find_or_create_for_container(me, :movie, movie.id, %{})
      {:ok, _} = Library.ProgressRecords.find_or_create_for_container(ana, :movie, movie.id, %{})

      :ok = MediaCentaur.Profiles.remove(MediaCentaur.Profiles.get(ana))

      assert {:ok, _} = Library.ProgressRecords.fetch_for_container(me, :movie, movie.id)
      assert {:error, :not_found} = Library.ProgressRecords.fetch_for_container(ana, :movie, movie.id)
    end
  end
```

(`movie_id` in the pin: write `movie_id = movie.id` first.)

`test/media_centaur/library/progress_test.exs`, in the describe that drives the worker:

```elixir
    test "the hot path keys by profile: two profiles' positions on one item do not mix" do
      pi_id = seed_movie_playable_item()
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id

      :ok = Progress.record(me, pi_id, 100.0, 1000.0)
      :ok = Progress.record(ana, pi_id, 500.0, 1000.0)

      assert %WatchProgress{position_seconds: 100.0} = Progress.get(me, pi_id)
      assert %WatchProgress{position_seconds: 500.0} = Progress.get(ana, pi_id)

      :ok = Progress.complete(ana, pi_id)
      assert %WatchProgress{completed: true} = Progress.get(ana, pi_id)
      assert %WatchProgress{completed: false} = Progress.get(me, pi_id)
    end
```

`test/media_centaur/library/views/continue_watching_test.exs`:

```elixir
  describe "per profile" do
    test "each profile's shelf holds its own titles; the ETS snapshot and the fallback agree" do
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id
      mine = create_standalone_movie(%{name: "Mine"})
      hers = create_standalone_movie(%{name: "Hers"})
      record_present(create_linked_file(%{movie_id: mine.id}))
      record_present(create_linked_file(%{movie_id: hers.id}))
      create_watch_progress(%{profile_id: me, movie_id: mine.id, position_seconds: 30.0, duration_seconds: 100.0})
      create_watch_progress(%{profile_id: ana, movie_id: hers.id, position_seconds: 30.0, duration_seconds: 100.0})

      assert [%{entity_name: "Mine"}] = Views.continue_watching(me)
      assert [%{entity_name: "Hers"}] = Views.continue_watching(ana)

      assert :ok = ContinueWatching.refresh_cache()
      assert [%{entity_name: "Mine"}] = Views.continue_watching(me)
      assert [%{entity_name: "Hers"}] = Views.continue_watching(ana)
      assert Views.continue_watching(Ecto.UUID.generate()) == []
    end
  end
```

`test/media_centaur_web/live/home_live_test.exs`, in the Continue Watching describe:

```elixir
    test "the shelf is the session's profile's", %{conn: conn} do
      ana = create_profile(%{name: "Ana"})
      hers = create_standalone_movie(%{name: "Hers Only"})
      record_present(create_linked_file(%{movie_id: hers.id}))
      create_watch_progress(%{profile_id: ana.id, movie_id: hers.id, position_seconds: 30.0, duration_seconds: 100.0})

      {:ok, _view, html} = live_async!(conn, "/")
      refute html =~ "Hers Only"

      {:ok, _view, html} = conn |> with_profile(ana) |> live_async!("/")
      assert html =~ "Hers Only"
    end
```

`test/media_centaur/playback/resolver_test.exs`, one test:

```elixir
    test "resume reads the profile's own row" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_linked_file(%{movie_id: movie.id})
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id
      create_watch_progress(%{profile_id: ana, movie_id: movie.id, position_seconds: 600.0, duration_seconds: 7200.0})

      assert {:ok, %{start_position: 600.0}} = Resolver.resolve(ana, movie.id)
      assert {:ok, %{start_position: 0.0}} = Resolver.resolve(me, movie.id)
    end
```

- [ ] **Step 2: Run one to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/library/progress_records_test.exs`
Expected: FAIL — `find_or_create_for_container/4` undefined (compile error).

- [ ] **Step 3: The migration**

`priv/repo/migrations/20261008120000_watch_progress_per_profile.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.WatchProgressPerProfile do
  @moduledoc """
  Watch progress belongs to a profile (ADR-078, phase 2). Every existing
  row is the oldest profile's — the owner profile the phase 1 migration
  created — and the unique key becomes `(profile_id, playable_item_id)`.

  SQLite cannot add a NOT NULL column to a filled table, so the table is
  rebuilt; the copy fills `profile_id` in the same statement, which is
  why no UPDATE (and no MC0015 carve-out) is needed. The FK to `profiles`
  cascades: removing a profile removes its rows, no job involved.

  Between `migrate` and the restart the outgoing release can still write
  a row without a profile; `NOT NULL` refuses it, the progress worker
  logs the failed flush and retries on its next tick, and the new release
  is serving by then. Not reversible: rows of several profiles would
  collapse onto one key.
  """
  use Ecto.Migration

  def up do
    create table(:library_watch_progress_next, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position_seconds, :float, default: 0.0
      add :duration_seconds, :float, default: 0.0
      add :completed, :boolean, default: false
      add :last_watched_at, :utc_datetime

      add :playable_item_id,
          references(:library_playable_items, type: :binary_id, on_delete: :delete_all),
          null: false

      add :profile_id, references(:profiles, type: :uuid, on_delete: :delete_all), null: false

      timestamps()
    end

    execute """
    INSERT INTO library_watch_progress_next
      (id, position_seconds, duration_seconds, completed, last_watched_at,
       playable_item_id, profile_id, inserted_at, updated_at)
    SELECT id, position_seconds, duration_seconds, completed, last_watched_at,
           playable_item_id,
           (SELECT id FROM profiles ORDER BY inserted_at, id LIMIT 1),
           inserted_at, updated_at
    FROM library_watch_progress
    """

    drop table(:library_watch_progress)
    rename table(:library_watch_progress_next), to: table(:library_watch_progress)

    create unique_index(:library_watch_progress, [:profile_id, :playable_item_id])

    create index(:library_watch_progress, [:completed, :last_watched_at],
             name: :library_watch_progress_completed_last_watched_at_index
           )
  end

  def down do
    raise Ecto.MigrationError,
          "watch_progress_per_profile is not reversible — rows of several profiles would collapse onto one playable_item_id"
  end
end
```

- [ ] **Step 4: The schema**

`lib/media_centaur/library/watch_progress.ex`:

```elixir
  schema "library_watch_progress" do
    field :position_seconds, :float, default: 0.0
    field :duration_seconds, :float, default: 0.0
    field :completed, :boolean, default: false
    field :last_watched_at, :utc_datetime
    field :profile_id, Ecto.UUID

    belongs_to :playable_item, MediaCentaur.Library.PlayableItem

    timestamps()
  end

  @type t :: %__MODULE__{}

  @impl true
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:profile_id, :playable_item_id, :position_seconds, :duration_seconds, :completed])
    |> validate_required([:profile_id, :playable_item_id])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
    |> unique_constraint([:profile_id, :playable_item_id])
  end

  @impl true
  def update_changeset(record, attrs) do
    record
    |> cast(attrs, [:position_seconds, :duration_seconds, :completed])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
    |> unique_constraint([:profile_id, :playable_item_id])
  end
```

(`update_changeset` no longer casts `playable_item_id`: the key of a row does not move.) Moduledoc: one sentence, "A row is one profile's progress on one playable item (ADR-078); the profile is a plain id, not an association — `Profiles` is another context."

- [ ] **Step 5: `ProgressRecords` takes the profile first**

In `lib/media_centaur/library/progress_records.ex`, the WatchProgress functions become:

```elixir
  @spec fetch_for_container(Ecto.UUID.t(), PlayableItem.container_type(), Ecto.UUID.t()) ::
          {:ok, WatchProgress.t()} | {:error, :not_found}
  def fetch_for_container(profile_id, container_type, container_id) when is_binary(profile_id) do
    query =
      from(wp in WatchProgress,
        join: pi in PlayableItem,
        on: pi.id == wp.playable_item_id,
        where:
          wp.profile_id == ^profile_id and pi.container_type == ^container_type and
            pi.container_id == ^container_id,
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @spec find_or_create_for_container(Ecto.UUID.t(), PlayableItem.container_type(), Ecto.UUID.t(), map()) ::
          {:ok, WatchProgress.t()} | {:error, term()}
  def find_or_create_for_container(profile_id, container_type, container_id, attrs \\ %{})
      when is_binary(profile_id) do
    position = PlayableItems.canonical_position(container_type, container_id)

    with {:ok, playable_item} <- PlayableItems.find_or_create(container_type, container_id, position) do
      attrs = attrs |> Map.new() |> Map.merge(%{profile_id: profile_id, playable_item_id: playable_item.id})
      Writes.upsert_by(WatchProgress, [profile_id: profile_id, playable_item_id: playable_item.id], attrs)
    end
  end

  @doc "The progress worker's flush: writes one in-memory row through to its `(profile_id, playable_item_id)` row."
  @spec upsert_by_profile_item!(map()) :: WatchProgress.t()
  def upsert_by_profile_item!(%{profile_id: profile_id, playable_item_id: playable_item_id} = attrs)
      when is_binary(profile_id) and is_binary(playable_item_id) do
    case Writes.upsert_by(WatchProgress, [profile_id: profile_id, playable_item_id: playable_item_id], attrs) do
      {:ok, record} -> record
      {:error, changeset} -> raise "WatchProgress flush failed: #{inspect(changeset)}"
    end
  end

  @spec find_or_create_by_playable_item(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, WatchProgress.t()} | {:error, term()}
  def find_or_create_by_playable_item(profile_id, playable_item_id)
      when is_binary(profile_id) and is_binary(playable_item_id) do
    case Repo.get_by(WatchProgress, profile_id: profile_id, playable_item_id: playable_item_id) do
      nil ->
        Writes.upsert_by(
          WatchProgress,
          [profile_id: profile_id, playable_item_id: playable_item_id],
          %{profile_id: profile_id, playable_item_id: playable_item_id}
        )

      record ->
        {:ok, record}
    end
  end

  @spec list_for_container(Ecto.UUID.t(), container_type(), Ecto.UUID.t()) :: [struct()]
  def list_for_container(profile_id, :tv_series, id), do: list_for_tv_series(profile_id, id)
  def list_for_container(profile_id, :movie_series, id), do: list_for_movie_series(profile_id, id)
  def list_for_container(profile_id, :movie, id), do: list_for_leaf(profile_id, :movie, id)
  def list_for_container(profile_id, :video_object, id), do: list_for_leaf(profile_id, :video_object, id)

  @spec list_for_tv_series(Ecto.UUID.t(), Ecto.UUID.t()) :: [struct()]
  def list_for_tv_series(profile_id, tv_series_id) when is_binary(profile_id) and is_binary(tv_series_id) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id and pi.container_type == :episode,
      join: e in Episode,
      on: e.id == pi.container_id,
      join: s in Season,
      on: s.id == e.season_id,
      where: wp.profile_id == ^profile_id and s.tv_series_id == ^tv_series_id,
      select: {wp, e.id}
    )
    |> Repo.all()
    |> Enum.map(fn {progress, episode_id} ->
      %{progress | playable_item: %{container_type: :episode, container_id: episode_id}}
    end)
  end

  @spec summaries(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => summary()}
  def summaries(_profile_id, []), do: %{}

  def summaries(profile_id, entity_ids) when is_binary(profile_id) and is_list(entity_ids) do
    %{}
    |> Map.merge(leaf_summaries(profile_id, :movie, entity_ids))
    |> Map.merge(leaf_summaries(profile_id, :video_object, entity_ids))
    |> Map.merge(movie_series_summaries(profile_id, entity_ids))
    |> Map.merge(tv_series_summaries(profile_id, entity_ids))
  end

  @spec progress_by_leaf(Ecto.UUID.t(), :movie | :video_object, [Ecto.UUID.t()]) ::
          %{Ecto.UUID.t() => WatchProgress.t()}
  def progress_by_leaf(_profile_id, _container_type, []), do: %{}

  def progress_by_leaf(profile_id, container_type, ids) when container_type in [:movie, :video_object] do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id and pi.container_type == ^container_type and pi.container_id in ^ids,
      where: wp.profile_id == ^profile_id,
      select: {pi.container_id, wp}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Every profile with at least one progress row — the profiles Continue Watching is built for."
  @spec profile_ids_with_progress() :: [Ecto.UUID.t()]
  def profile_ids_with_progress,
    do: Repo.all(from(wp in WatchProgress, distinct: true, select: wp.profile_id, order_by: wp.profile_id))
```

The private `list_for_movie_series/2`, `list_for_leaf/3`, `leaf_summaries/3`, `tv_series_summaries/2`, `movie_series_summaries/2` each gain `profile_id` as the first argument and `wp.profile_id == ^profile_id` in their `where`. Delete `upsert_by_playable_item!/1`. `list_all/0`, `mark_*`, `destroy*`, the pure helpers and the Extra functions are unchanged here (Task 4 does extras). Moduledoc: "Every read and write names the profile first (ADR-078)."

Update the test at `test/media_centaur/library/progress_records_test.exs` from Task 2 to `progress_by_leaf(owner_profile_id(), :movie, …)`.

- [ ] **Step 6: The hot path is keyed by the pair**

`lib/media_centaur/library/progress/events.ex`: `ProgressTicked` keys/fields `[:profile_id, :playable_item_id, :position_seconds]`; `ProgressFlushed` `[:profile_id, :playable_item_id]`; types gain `profile_id: String.t()`. `ProgressHydrated` unchanged.

`lib/media_centaur/library/progress.ex`:

```elixir
  @type key :: {Ecto.UUID.t(), Ecto.UUID.t()}

  @spec record(Ecto.UUID.t(), Ecto.UUID.t(), float(), float()) :: :ok
  def record(profile_id, playable_item_id, position_seconds, duration_seconds)
      when is_binary(profile_id) and is_binary(playable_item_id) and is_number(position_seconds) and
             is_number(duration_seconds) do
    position = position_seconds / 1
    duration = duration_seconds / 1
    key = {profile_id, playable_item_id}
    write_in_memory(key, position, duration, hot_completed?(key))
    cast({:record, key, position, duration})
  end

  @spec complete(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def complete(profile_id, playable_item_id) when is_binary(profile_id) and is_binary(playable_item_id),
    do: call({:complete, {profile_id, playable_item_id}})

  @spec get(Ecto.UUID.t(), Ecto.UUID.t()) :: WatchProgress.t() | nil
  def get(profile_id, playable_item_id) when is_binary(profile_id) and is_binary(playable_item_id) do
    case lookup_in_memory_row({profile_id, playable_item_id}) do
      nil -> Repo.get_by(WatchProgress, profile_id: profile_id, playable_item_id: playable_item_id)
      row -> row_to_schema(row)
    end
  end

  @spec overlay_in_memory(map()) :: map()
  def overlay_in_memory(%{profile_id: profile_id, playable_item_id: playable_item_id} = record)
      when is_binary(profile_id) and is_binary(playable_item_id) do
    case lookup_in_memory({profile_id, playable_item_id}) do
      nil -> record
      hot -> %{record | position_seconds: hot.position_seconds, duration_seconds: hot.duration_seconds, last_watched_at: hot.last_watched_at}
    end
  end

  def overlay_in_memory(record), do: record
```

The private helpers take `key` where they took `playable_item_id`; the ETS row is `{key, row}` with `row = %{profile_id:, playable_item_id:, position_seconds:, duration_seconds:, completed:, last_watched_at:}`; `row_to_schema/1` sets `profile_id` on the struct. Update the moduledoc's key description.

`lib/media_centaur/library/progress/worker.ex`: every place `playable_item_id` is the ETS key or a dirty-set member becomes `key = {profile_id, playable_item_id}`:
- `__inject_record_for_test__(server \\ __MODULE__, profile_id, playable_item_id, position, duration)` casts `{:record, {profile_id, playable_item_id}, position, duration}`.
- `handle_call({:complete, {profile_id, playable_item_id} = key}, _from, state)`: `ProgressRecords.find_or_create_by_playable_item(profile_id, playable_item_id)`; `lookup_row(state.table, key)`; `upsert_in_memory(state.table, key, …)`; `Topics.publish(Topics.watch_history_events(), {:watch_completed, playable_item_id})` unchanged; `MapSet.delete(state.dirty, key)`.
- `handle_cast({:record, {profile_id, playable_item_id} = key, position, duration}, state)`: `fill_in_memory_if_absent(state.table, key, …)`; `%ProgressTicked{profile_id: profile_id, playable_item_id: playable_item_id, position_seconds: position}`; `MapSet.put(state.dirty, key)`.
- `flush_dirty/1`: rows by key; returns `{:ok, Enum.map(rows, &{&1.profile_id, &1.playable_item_id})}`; `broadcast_flushed({profile_id, playable_item_id})` → `%ProgressFlushed{profile_id: profile_id, playable_item_id: playable_item_id}`.
- `persist_rows/1`: `Enum.each(rows, &Library.ProgressRecords.upsert_by_profile_item!/1)`.
- `hydrate_from_db/1`: key `{record.profile_id, record.playable_item_id}`, row map gains `profile_id: record.profile_id`.
- `lookup_row/2`, `upsert_in_memory/…`, `fill_in_memory_if_absent/…`: parameter renamed to `key`, row map carries `profile_id` (from the key's first element).
- Moduledoc: "Key shape: `{{profile_id, playable_item_id}, row}`."

Update `test/media_centaur/library/progress_test.exs` throughout: `Progress.record(owner_profile_id(), pi_id, …)`, `Progress.get(owner_profile_id(), pi_id)`, `Progress.complete(…)`, `__inject_record_for_test__(worker, owner_profile_id(), pi_id, …)`, `{:progress_ticked, %{profile_id: _, playable_item_id: ^pi_id}}`, `{:progress_flushed, %{playable_item_id: ^pi_id}}`. The three `progress_broadcaster_test.exs` and one `continue_watching_test.exs` worker calls likewise.

- [ ] **Step 7: Continue Watching reads for a profile**

`lib/media_centaur/library/home_feed.ex`:

```elixir
  @spec list_in_progress(Ecto.UUID.t(), keyword()) :: [map()]
  def list_in_progress(profile_id, opts \\ []) when is_binary(profile_id) do
    limit = Keyword.get(opts, :limit, 12)

    (fetch_in_progress_movies(profile_id, limit) ++
       fetch_in_progress_tv_series(profile_id, limit) ++
       fetch_in_progress_video_objects(profile_id, limit))
    |> Enum.map(&overlay_in_memory_progress/1)
    |> Enum.sort_by(fn entry -> entry_last_watched_at(entry) || @epoch_datetime end, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(&shape_in_progress_row/1)
  end
```

Every private WatchProgress query gains `profile_id` as its first argument and `wp.profile_id == ^profile_id` in its `where`: `progress_records_by_tv_series/2`, `last_watched_by_container/2`, `last_watched_by_tv_series/1`, the `exists`/`not exists` subqueries in `fetch_in_progress_movies/2`, `fetch_in_progress_tv_series/2`, `fetch_in_progress_video_objects/2`, and the `ProgressRecords.progress_by_leaf(profile_id, type, ids)` calls from Task 2. `overlay_in_memory_progress/1` is unchanged (the records carry `profile_id`).

`lib/media_centaur/library.ex:131`: `def list_in_progress(profile_id, opts \\ []), do: HomeFeed.list_in_progress(profile_id, opts)`.

`lib/media_centaur/library/views/continue_watching.ex`:

```elixir
  @table :library_view_continue_watching
  @max_items 100
  @ets_opts [:set, :public, :named_table, read_concurrency: true]

  @impl MediaCentaur.Cache
  def refresh_cache do
    ensure_table()

    rows =
      for profile_id <- ProgressRecords.profile_ids_with_progress(),
          do: {profile_id, build(profile_id, @max_items)}

    :ets.delete_all_objects(@table)
    :ets.insert(@table, rows)
    Topics.publish(Topics.library_views(), {:library_view_updated, :continue_watching})
    :ok
  end

  @doc """
  Read one profile's shelf. Falls back to the underlying query when the
  ETS table is absent — test mode (no `Cache.Worker`) and the window
  between boot and first refresh. A profile with no rows reads `[]`.
  """
  @spec read(Ecto.UUID.t(), keyword()) :: [ContinueWatchingItem.t()]
  def read(profile_id, opts \\ []) when is_binary(profile_id) do
    limit = Keyword.get(opts, :limit, 12)

    case :ets.whereis(@table) do
      :undefined ->
        build(profile_id, limit)

      _ref ->
        case :ets.lookup(@table, profile_id) do
          [{^profile_id, items}] -> Enum.take(items, limit)
          [] -> []
        end
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, @ets_opts)
      _ref -> :ok
    end

    :ok
  end

  defp build(profile_id, limit) do
    profile_id
    |> Library.list_in_progress(limit: limit)
    |> Enum.map(&to_view_model/1)
    |> ItemAvailability.resolve(id: :entity_id, artwork: [:backdrop_url, :logo_url])
  end
```

Remove the `RankedProjection` alias; add `alias MediaCentaur.Library.ProgressRecords`. Moduledoc: "Profile-keyed (ADR-078): the `:set` holds `{profile_id, items}` for every profile with a progress row, rebuilt whole on every relevant event — a household is a handful of profiles. The derived message is unchanged; a page re-reads for its own profile." In `ranked_projection.ex`'s moduledoc, drop `ContinueWatching` from the list of users ("`RecentlyAdded`, `HeroCandidates`, `Browse`").

`lib/media_centaur/library/views.ex`:

```elixir
  @doc "Up to `:limit` Continue Watching items for `profile_id`, most recently watched first. Defaults to 12."
  @spec continue_watching(Ecto.UUID.t(), keyword()) :: [ContinueWatchingItem.t()]
  def continue_watching(profile_id, opts \\ []), do: ContinueWatching.read(profile_id, opts)
```

- [ ] **Step 8: Playback writes and reads under the session's profile**

`lib/media_centaur/playback/resolver.ex`: `resolve(profile_id, uuid)`; thread `profile_id` through `resolve_entity/2`, `resolve_typed_entity/2`, `resolve_episode/2`, `resolve_episode_playback/2`, `resolve_movie/2`, `resolve_movie_playback/2`, `resolve_movie_parent/2`, `resolve_extra/2`, `resolve_extra_playback/2`; every `ProgressRecords.list_for_container(type, id)` becomes `(profile_id, type, id)`. `extra_resume_position/1` waits for Task 4 (keep `fetch_for_extra(extra_id)` for now). `Playback.play/2` calls `Resolver.resolve(profile_id, uuid)`.

`lib/media_centaur/playback/next_episode.ex`: `resolve(profile_id, episode_id)`; `ProgressRecords.list_for_container(profile_id, :tv_series, season.tv_series_id)`. `identify/2` unchanged (no progress).

`lib/media_centaur/playback/mpv_session.ex`:
- `queue_next/1`: `NextEpisode.resolve(state.profile_id, state.episode_id)`.
- `persist_entity_progress/2`: capture `profile_id = state.profile_id` before the task; `LibraryProgress.record(profile_id, playable_item_id, saveable, duration)`; `maybe_mark_completed(profile_id, playable_item_id, reason)`; `ProgressBroadcaster.broadcast(profile_id, entity_id, playable_item_id)`.
- `maybe_mark_completed(profile_id, playable_item_id, reason)`: `LibraryProgress.get(profile_id, playable_item_id)` / `LibraryProgress.complete(profile_id, playable_item_id)`.

`lib/media_centaur/playback/progress_broadcaster.ex`: `broadcast(profile_id, entity_id, changed)` → `resolve_entity_with_progress(profile_id, id)` → `load_via_detail(profile_id, type, id)` → `Library.ProgressRecords.list_for_container(profile_id, id)` becomes `list_for_container(profile_id, type, id)`. `broadcast_extra/3` reads stay for Task 4.

- [ ] **Step 9: The web composes for the socket's profile**

`lib/media_centaur/library/modal_entry.ex`: `load_resolved(profile_id, kind, id)` → `build_modal_entry(profile_id, kind, item, id)` with `ProgressRecords.list_for_container(profile_id, container_type, id)` (the `MediaTrackOverrides.put_on_entity/1` call stays until Task 5).

`lib/media_centaur_web/view_model/leaf_detail.ex`: `compose(profile_id, kind, id)` → `ModalEntry.load_resolved(profile_id, kind, id)`.
`series_detail.ex`: `compose(profile_id, entity_id)` → `compose_from_detail(profile_id, detail_item, entity_id)` → `Library.ProgressRecords.list_for_tv_series(profile_id, entity_id)`.
`collection_detail.ex`: `compose(profile_id, entity_id)` → `Library.ProgressRecords.list_for_container(profile_id, :movie_series, entity_id)`.
Update the `@doc`s that name `compose/1` → `compose/2` in `components/detail/collection_rail.ex`, `season_list.ex`, `view_model/episode_row.ex`, `season_view.ex`.

`lib/media_centaur_web/live/title_detail_host/library_half.ex`: `load(profile_id, ref)`, `load_entity(profile_id, id)`, `address(profile_id, id)`, `reload(profile_id, half)`, private `compose(profile_id, kind, id)` dispatching `SeriesDetail.compose(profile_id, id)`, `CollectionDetail.compose(profile_id, id)`, `LeafDetail.compose(profile_id, kind, id)`.

`lib/media_centaur_web/live/title_detail_host.ex`: the six `LibraryHalf.*` call sites (lines 221, 232, 469, 478, 496, 884, 1104) pass `socket.assigns.profile.id`. All run from `handle_params`, `handle_event` or `handle_info` hooks, never from `on_mount`, so the assign is present.

`lib/media_centaur_web/live/title_detail_host/library_events.ex`: `toggle_watch_progress(profile_id, entity_id, container_type, container_id)` → `load_progress(profile_id, …)` → `ProgressRecords.fetch_for_container(profile_id, type, id)`; `apply_progress_transition(nil, profile_id, container_type, container_id)` → `find_or_create_for_container(profile_id, …)`.

`lib/media_centaur_web/live/library_live.ex`: `Library.ProgressRecords.summaries(socket.assigns.profile.id, ids)` at both sites (`load_library/1` runs from `handle_params`' `ensure_loaded/1`).

`lib/media_centaur_web/live/home_live.ex`: `defp load_progress(socket), do: Views.continue_watching(socket.assigns.profile.id, limit: 24)` and `assign_continue_watching/1` calls `load_progress(socket)`.

- [ ] **Step 10: Factories, seeders, benchmark**

`test/support/factory.ex`:

```elixir
  def create_watch_progress(attrs) do
    defaults = %{position_seconds: 0.0, duration_seconds: 0.0}
    merged = Map.merge(defaults, Map.new(attrs))
    profile_id = Map.get_lazy(merged, :profile_id, &owner_profile_id/0)

    {container_type, container_id} = container_ref(merged)
    progress_attrs = Map.drop(merged, [:movie_id, :episode_id, :video_object_id, :profile_id])

    result =
      Library.ProgressRecords.find_or_create_for_container(
        profile_id,
        container_type,
        container_id,
        progress_attrs
      )

    then(result, fn {:ok, record} -> MediaCentaur.Repo.preload(record, :playable_item) end)
  end
```

`build_progress/1`: `defaults` gains `profile_id: Ecto.UUID.generate()` (pure tests; a pure merge keys on `playable_item_id`).

`lib/media_centaur/showcase.ex`: at the top of `seed!/0` (or wherever `movies`/`tv_series` are first in scope), `owner_id = MediaCentaur.Profiles.list() |> hd() |> Map.fetch!(:id)`; `seed_watch_progress!(owner_id, movies, tv_series)` and the two `find_or_create_for_container(owner_id, :movie | :episode, …)` calls. (Track override and history follow in Tasks 5 and 6.) `Showcase` is `top_level?: true, check: [in: false, out: false]`, so no Boundary change.

`lib/media_centaur/profile/loader.ex`: the same owner lookup; `find_or_create_for_container(owner_id, …)` ×2. `lib/media_centaur/profile/suite.ex:42,44` and `suites/continue_watching_suite.ex:54,57`: `Views.continue_watching(owner_id, limit: 30)`, `Library.list_in_progress(owner_id, limit: 30)` with the same lookup (check `Profile`'s Boundary declaration; add `MediaCentaur.Profiles` to its deps if it has one).

- [ ] **Step 11: Compile; follow the compiler through the tests**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors`
Expected: clean once every caller passes the profile.

Run: `~/scripts/agents/agent-mix test 2>&1 | tee /tmp/claude-1000/phase2-task3.log | tail -40`

Every failing test is one of three kinds; fix each the same way:
1. A direct call with the old arity (`ProgressRecords.fetch_for_container(:movie, id)`, `list_for_container(:tv_series, id)`, `summaries(ids)`, `Library.list_in_progress(…)`, `Views.continue_watching(limit: n)`, `Progress.record/get/complete`, `SeriesDetail/CollectionDetail/LeafDetail.compose`, `LibraryHalf.load_entity/reload/address`, `Resolver.resolve/1`, `NextEpisode.resolve/1`): pass `owner_profile_id()` first.
2. A `%WatchProgress{}` or `build_progress` pure fixture: add `profile_id`.
3. An event pattern on `:progress_ticked` / `:progress_flushed`: match the struct with `profile_id`.

Expected: PASS.

- [ ] **Step 12: Precommit and commit**

Run: `~/scripts/agents/agent-mix precommit`

```bash
git add -A
git commit -m "feat(library): watch progress belongs to a profile — migration, hot path, Continue Watching, resume"
```

---

### Task 4: Extra progress per profile

**Files:**
- Create: `priv/repo/migrations/20261008120001_extra_progress_per_profile.exs`
- Modify: `lib/media_centaur/library/extra_progress.ex`, `progress_records.ex`, `lib/media_centaur/playback/resolver.ex`, `mpv_session.ex`, `progress_broadcaster.ex`, `lib/media_centaur_web/live/title_detail_host/library_events.ex`, `test/support/factory.ex`
- Test: `test/media_centaur/library/extra_progress_test.exs`

- [ ] **Step 1: Write the failing test**

In `test/media_centaur/library/extra_progress_test.exs`:

```elixir
  describe "two profiles" do
    test "each profile has its own row for the same extra; a profile without one reads not_found" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})
      extra = create_extra(%{movie_id: movie.id, name: "Behind the Scenes"})
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id

      create_extra_progress(%{profile_id: me, extra_id: extra.id, position_seconds: 45.0, duration_seconds: 300.0})

      assert {:ok, %{position_seconds: 45.0}} = Library.ProgressRecords.fetch_for_extra(me, extra.id)
      assert {:error, :not_found} = Library.ProgressRecords.fetch_for_extra(ana, extra.id)

      create_extra_progress(%{profile_id: ana, extra_id: extra.id, position_seconds: 5.0, duration_seconds: 300.0})
      assert {:ok, %{position_seconds: 5.0}} = Library.ProgressRecords.fetch_for_extra(ana, extra.id)
      assert {:ok, %{position_seconds: 45.0}} = Library.ProgressRecords.fetch_for_extra(me, extra.id)
    end
  end
```

- [ ] **Step 2: Run to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/library/extra_progress_test.exs`
Expected: FAIL — `fetch_for_extra/2` undefined.

- [ ] **Step 3: The migration**

`priv/repo/migrations/20261008120001_extra_progress_per_profile.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.ExtraProgressPerProfile do
  @moduledoc """
  Extra progress belongs to a profile (ADR-078, phase 2): the rebuild of
  `library_extra_progress` with `profile_id`, every existing row the
  oldest profile's, unique on `(profile_id, extra_id)`. The copy fills the
  column, so no UPDATE. The extra FK gains `ON DELETE CASCADE` on the way
  (the original had none; `EntityCascade` deleted these rows first by
  hand). Not reversible.
  """
  use Ecto.Migration

  def up do
    create table(:library_extra_progress_next, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :extra_id, references(:library_extras, type: :uuid, on_delete: :delete_all), null: false
      add :profile_id, references(:profiles, type: :uuid, on_delete: :delete_all), null: false
      add :position_seconds, :float
      add :duration_seconds, :float
      add :completed, :boolean
      add :last_watched_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    execute """
    INSERT INTO library_extra_progress_next
      (id, extra_id, profile_id, position_seconds, duration_seconds, completed, last_watched_at,
       inserted_at, updated_at)
    SELECT id, extra_id, (SELECT id FROM profiles ORDER BY inserted_at, id LIMIT 1),
           position_seconds, duration_seconds, completed, last_watched_at, inserted_at, updated_at
    FROM library_extra_progress
    """

    drop table(:library_extra_progress)
    rename table(:library_extra_progress_next), to: table(:library_extra_progress)
    create unique_index(:library_extra_progress, [:profile_id, :extra_id])
  end

  def down do
    raise Ecto.MigrationError,
          "extra_progress_per_profile is not reversible — rows of several profiles would collapse onto one extra_id"
  end
end
```

- [ ] **Step 4: Schema and context**

`lib/media_centaur/library/extra_progress.ex`: `field :profile_id, Ecto.UUID`; `create_changeset` casts `[:profile_id, :extra_id, :position_seconds, :duration_seconds]`, requires `[:profile_id, :extra_id]`, adds `unique_constraint([:profile_id, :extra_id])`.

`lib/media_centaur/library/progress_records.ex`:

```elixir
  @spec fetch_for_extra(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, ExtraProgress.t()} | {:error, :not_found}
  def fetch_for_extra(profile_id, extra_id) when is_binary(profile_id) and is_binary(extra_id) do
    case Repo.get_by(ExtraProgress, profile_id: profile_id, extra_id: extra_id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc "Upserts one profile's progress on an extra; `attrs` carries `:profile_id` and `:extra_id`."
  @spec find_or_create_for_extra(map()) :: {:ok, ExtraProgress.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_for_extra(attrs) do
    Writes.upsert_by(
      ExtraProgress,
      [profile_id: Writes.attr(attrs, :profile_id), extra_id: Writes.attr(attrs, :extra_id)],
      attrs
    )
  end
```

- [ ] **Step 5: Callers**

- `resolver.ex`: `extra_resume_position(profile_id, extra_id)` → `fetch_for_extra(profile_id, extra_id)`; called from `resolve_extra_playback/2`.
- `mpv_session.ex` `persist_extra_progress/2`: `params` gains `profile_id: state.profile_id`; `maybe_mark_extra_completed/2` unchanged; the broadcaster call already passes the profile (Task 1).
- `progress_broadcaster.ex` `broadcast_extra(profile_id, entity_id, extra_id)`: `fetch_for_extra(profile_id, extra_id)`.
- `library_events.ex` `toggle_extra_watched(profile_id, entity_id, extra_id)`: `fetch_for_extra(profile_id, extra_id)`; the create passes `profile_id: profile_id` in its attrs.
- `test/support/factory.ex`:

```elixir
  def create_extra_progress(attrs) do
    defaults = %{position_seconds: 0.0, duration_seconds: 0.0}

    defaults
    |> Map.merge(Map.new(attrs))
    |> Map.put_new_lazy(:profile_id, &owner_profile_id/0)
    |> Library.ProgressRecords.find_or_create_for_extra!()
  end
```

- Existing `fetch_for_extra(extra.id)` calls in `extra_progress_test.exs` and any other test: `fetch_for_extra(owner_profile_id(), extra.id)`.
- `EntityCascade.@tables_in_delete_order` keeps `ExtraProgress` first (harmless, and `destroy_all!` is whole-library).

- [ ] **Step 6: Compile, test, precommit, commit**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test test/media_centaur/library/extra_progress_test.exs test/media_centaur/playback test/media_centaur_web/live/library_live_test.exs`
Expected: PASS.

Run: `~/scripts/agents/agent-mix precommit`

```bash
git add -A
git commit -m "feat(library): extra progress belongs to a profile"
```

---

### Task 5: Track memory per profile

**Files:**
- Create: `priv/repo/migrations/20261008120002_media_track_overrides_per_profile.exs`
- Modify: `lib/media_centaur/library/media_track_override.ex`, `media_track_overrides.ex`, `modal_entry.ex`, `lib/media_centaur/playback/language_context.ex`, `mpv_session.ex`, `lib/media_centaur_web/live/title_detail_host.ex`, `title_detail_host/library_events.ex`, `view_model/series_detail.ex`, `collection_detail.ex`, `lib/media_centaur/showcase.ex`
- Test: `test/media_centaur/library/media_track_override_test.exs`, `test/media_centaur/playback/language_context_test.exs`, `track_override_round_trip_test.exs`, `test/media_centaur_web/live/library_live_test.exs`, `test/media_centaur/library/entity_cascade_test.exs`

- [ ] **Step 1: Write the failing test**

In `test/media_centaur/library/media_track_override_test.exs`:

```elixir
  describe "two profiles" do
    test "the remembered tracks are the profile's own; clearing one leaves the other" do
      tv_series = create_tv_series()
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id

      {:ok, _} = Library.MediaTrackOverrides.upsert(me, :tv_series, tv_series.id, %{audio_lang: "jpn"})
      {:ok, _} = Library.MediaTrackOverrides.upsert(ana, :tv_series, tv_series.id, %{audio_lang: "fra"})

      assert %MediaTrackOverride{audio_lang: "jpn"} = Library.MediaTrackOverrides.get(me, :tv_series, tv_series.id)
      assert %MediaTrackOverride{audio_lang: "fra"} = Library.MediaTrackOverrides.get(ana, :tv_series, tv_series.id)

      :ok = Library.MediaTrackOverrides.clear(ana, :tv_series, tv_series.id)
      assert Library.MediaTrackOverrides.get(ana, :tv_series, tv_series.id) == nil
      assert %MediaTrackOverride{audio_lang: "jpn"} = Library.MediaTrackOverrides.get(me, :tv_series, tv_series.id)

      entity = Library.MediaTrackOverrides.put_on_entity(ana, %{id: tv_series.id, type: :tv_series})
      assert entity.track_override == nil
    end
  end
```

- [ ] **Step 2: Run to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/library/media_track_override_test.exs`
Expected: FAIL — `upsert/4` undefined.

- [ ] **Step 3: The migration**

`priv/repo/migrations/20261008120002_media_track_overrides_per_profile.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.MediaTrackOverridesPerProfile do
  @moduledoc """
  Track memory — the audio and subtitle choice remembered per title —
  belongs to a profile (ADR-078, phase 2). Rebuild with `profile_id`,
  every existing row the oldest profile's, unique on
  `(profile_id, owner_type, owner_id)`. Not reversible.
  """
  use Ecto.Migration

  def up do
    create table(:library_media_track_overrides_next, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :profile_id, references(:profiles, type: :uuid, on_delete: :delete_all), null: false
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false
      add :audio_lang, :string
      add :subtitle_lang, :string
      add :subtitle_forced, :boolean, null: false, default: false
      add :subtitles_off, :boolean, null: false, default: false

      timestamps()
    end

    execute """
    INSERT INTO library_media_track_overrides_next
      (id, profile_id, owner_type, owner_id, audio_lang, subtitle_lang, subtitle_forced, subtitles_off,
       inserted_at, updated_at)
    SELECT id, (SELECT id FROM profiles ORDER BY inserted_at, id LIMIT 1), owner_type, owner_id,
           audio_lang, subtitle_lang, subtitle_forced, subtitles_off, inserted_at, updated_at
    FROM library_media_track_overrides
    """

    drop table(:library_media_track_overrides)
    rename table(:library_media_track_overrides_next), to: table(:library_media_track_overrides)

    create unique_index(:library_media_track_overrides, [:profile_id, :owner_type, :owner_id],
             name: :library_media_track_overrides_profile_id_owner_type_owner_id_index
           )
  end

  def down do
    raise Ecto.MigrationError,
          "media_track_overrides_per_profile is not reversible — rows of several profiles would collapse onto one owner"
  end
end
```

- [ ] **Step 4: Schema and context**

`lib/media_centaur/library/media_track_override.ex`: `field :profile_id, Ecto.UUID` (and `profile_id: Ecto.UUID.t() | nil` in `@type t`); `changeset/2` casts it, requires `[:profile_id, :owner_type, :owner_id]`, and the constraint becomes

```elixir
    |> unique_constraint([:profile_id, :owner_type, :owner_id],
      name: :library_media_track_overrides_profile_id_owner_type_owner_id_index
    )
```

`lib/media_centaur/library/media_track_overrides.ex`:

```elixir
  @spec get(Ecto.UUID.t(), MediaTrackOverride.owner_type(), Ecto.UUID.t()) :: MediaTrackOverride.t() | nil
  def get(profile_id, owner_type, owner_id)
      when is_binary(profile_id) and is_atom(owner_type) and is_binary(owner_id) do
    Repo.get_by(MediaTrackOverride, profile_id: profile_id, owner_type: owner_type, owner_id: owner_id)
  end

  @spec upsert(Ecto.UUID.t(), MediaTrackOverride.owner_type(), Ecto.UUID.t(), map()) ::
          {:ok, MediaTrackOverride.t()} | {:error, Ecto.Changeset.t()}
  def upsert(profile_id, owner_type, owner_id, attrs)
      when is_binary(profile_id) and is_atom(owner_type) and is_binary(owner_id) and is_map(attrs) do
    attrs = Map.merge(attrs, %{profile_id: profile_id, owner_type: owner_type, owner_id: owner_id})

    if owner_type in MediaTrackOverride.owner_types() do
      case get(profile_id, owner_type, owner_id) do
        nil -> Repo.insert(MediaTrackOverride.changeset(%MediaTrackOverride{}, attrs))
        existing -> Repo.update(MediaTrackOverride.changeset(existing, attrs))
      end
    else
      {:error, MediaTrackOverride.changeset(%MediaTrackOverride{}, attrs)}
    end
  end

  @spec clear(Ecto.UUID.t(), MediaTrackOverride.owner_type(), Ecto.UUID.t()) :: :ok
  def clear(profile_id, owner_type, owner_id)
      when is_binary(profile_id) and is_atom(owner_type) and is_binary(owner_id) do
    case get(profile_id, owner_type, owner_id) do
      nil -> :ok
      override -> {:ok, _} = Repo.delete(override); :ok
    end
  end

  @spec put_on_entity(Ecto.UUID.t(), map()) :: map()
  def put_on_entity(profile_id, %{id: id, type: type} = entity) when is_binary(profile_id) and is_binary(id) do
    if type in MediaTrackOverride.owner_types(),
      do: Map.put(entity, :track_override, get(profile_id, type, id)),
      else: Map.put(entity, :track_override, nil)
  end

  def put_on_entity(_profile_id, entity) when is_map(entity), do: Map.put(entity, :track_override, nil)
```

(Write the `clear/3` `override ->` branch on two lines, as the formatter will.)

- [ ] **Step 5: Callers**

- `lib/media_centaur/playback/language_context.ex` `init/1`: `override = if owner_type, do: Library.MediaTrackOverrides.get(params.profile_id, owner_type, owner_id)`; add `required(:profile_id) => String.t()` to its `@spec`'s param map.
- `lib/media_centaur/playback/mpv_session.ex` `persist_track_override(state, attrs)` (Task 1 shape): `Library.MediaTrackOverrides.upsert(state.profile_id, owner_type, owner_id, attrs)`.
- `lib/media_centaur/library/modal_entry.ex` `build_modal_entry/4`: `MediaTrackOverrides.put_on_entity(profile_id, …)`.
- `view_model/series_detail.ex`, `collection_detail.ex`: `Library.MediaTrackOverrides.put_on_entity(profile_id, …)` in `compose_from_detail/3`.
- `title_detail_host.ex` `react({:track_override_changed, …})`: `Library.MediaTrackOverrides.get(socket.assigns.profile.id, type, id)` (the other-profile clause from Task 1 already ran).
- `library_events.ex` `handle("reset_track_override", …)`: `Library.MediaTrackOverrides.clear(socket.assigns.profile.id, type, id)`.
- `lib/media_centaur/showcase.ex` `maybe_seed_track_override!(owner_id, movie_id, entry)`: `upsert(owner_id, :movie, movie_id, attrs)`; thread `owner_id` through `seed_movie!`.
- Tests: every `MediaTrackOverrides.upsert(:type, id, attrs)` / `get(:type, id)` / `clear(:type, id)` in `media_track_override_test.exs`, `track_override_round_trip_test.exs`, `language_context_test.exs`, `library_live_test.exs`, `entity_cascade_test.exs` gains `owner_profile_id()` first; `language_context_test` passes `profile_id: owner_profile_id()` in its params.

- [ ] **Step 6: Compile, test, precommit, commit**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test test/media_centaur/library/media_track_override_test.exs test/media_centaur/library/entity_cascade_test.exs test/media_centaur/playback test/media_centaur_web/live/library_live_test.exs test/media_centaur_web/components/detail`
Expected: PASS.

Run: `~/scripts/agents/agent-mix precommit`

```bash
git add -A
git commit -m "feat(library): track memory belongs to a profile"
```

---

### Task 6: Watch history per profile

**Files:**
- Create: `priv/repo/migrations/20261008120003_watch_history_events_per_profile.exs`
- Modify: `lib/media_centaur/watch_history/event.ex`, `watch_history.ex`, `watch_history/rewatch.ex`, `recorder.ex`, `views.ex`, `views/summary.ex`, `views/playback_activity.ex`
- Modify: `lib/media_centaur_web/live/watch_history_live.ex`, `lib/media_centaur/showcase.ex`, `test/support/factory.ex`
- Test: `test/media_centaur/watch_history_test.exs`, `watch_history/event_test.exs`, `recorder_test.exs`, `views/summary_test.exs`, `views/playback_activity_test.exs`, `test/media_centaur_web/live/watch_history_live_test.exs`, `test/media_centaur/activities/publisher_test.exs`

- [ ] **Step 1: Write the failing tests**

`test/media_centaur/watch_history_test.exs`:

```elixir
  describe "scope" do
    setup do
      movie = create_movie(%{name: "Sample Movie"})
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id
      create_watch_event(%{profile_id: me, movie_id: movie.id, title: "Sample Movie", duration_seconds: 3600.0})
      create_watch_event(%{profile_id: ana, movie_id: movie.id, title: "Sample Movie", duration_seconds: 1800.0})
      create_watch_event(%{profile_id: ana, movie_id: movie.id, title: "Sample Movie", duration_seconds: 1800.0})
      %{movie: movie, me: me, ana: ana}
    end

    test "a profile reads its own events and aggregates", %{movie: movie, me: me, ana: ana} do
      assert [%{duration_seconds: 3600.0}] = WatchHistory.list_events(me)
      assert length(WatchHistory.list_events(ana)) == 2
      assert WatchHistory.stats(me).total_count == 1
      assert WatchHistory.stats(ana).total_seconds == 3600.0
      assert WatchHistory.rewatch_count_map(me, :movie) == %{movie.id => 1}
      assert WatchHistory.rewatch_count_map(ana, :movie) == %{movie.id => 2}
      assert WatchHistory.recent_events(me, 5) |> length() == 1
      assert Enum.sort(WatchHistory.profile_ids_with_events()) == Enum.sort([me, ana])
    end

    test ":all is the install-wide view", %{movie: movie} do
      assert WatchHistory.stats(:all).total_count == 3
      assert WatchHistory.stats(:all).total_seconds == 7200.0
      assert WatchHistory.rewatch_count_map(:all, :movie) == %{movie.id => 3}
      assert length(WatchHistory.recent_events(:all, 5)) == 3
    end

    test "removing a profile removes its events", %{me: me, ana: ana} do
      :ok = MediaCentaur.Profiles.remove(MediaCentaur.Profiles.get(ana))
      assert WatchHistory.list_events(ana) == []
      assert WatchHistory.stats(:all).total_count == 1
      assert WatchHistory.profile_ids_with_events() == [me]
    end
  end
```

`test/media_centaur/watch_history/recorder_test.exs`, in the movie test, after the existing assertions: `assert event.profile_id == progress.profile_id`.

`test/media_centaur/watch_history/views/summary_test.exs`:

```elixir
    test "the snapshot is per profile; a profile with no events computes an empty summary" do
      movie = create_standalone_movie(%{name: "Replayed"})
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id
      create_watch_event(%{profile_id: me, movie_id: movie.id, entity_type: :movie, title: "Replayed"})
      create_watch_event(%{profile_id: me, movie_id: movie.id, entity_type: :movie, title: "Replayed"})

      assert :ok = Summary.refresh_cache()
      assert Views.summary(me).stats.total_count == 2
      assert Views.summary(me).rewatch_counts[:movie][movie.id] == 2
      assert Views.summary(ana).stats.total_count == 0
      assert Views.summary(ana).rewatch_counts == %{movie: %{}, episode: %{}, video_object: %{}}
    end
```

`test/media_centaur_web/live/watch_history_live_test.exs`:

```elixir
  test "the History page lists the session's profile's completions only", %{conn: conn} do
    movie = create_movie(%{name: "Sample Movie"})
    ana = create_profile(%{name: "Ana"})
    create_watch_event(%{profile_id: owner_profile_id(), movie_id: movie.id, title: "Mine Only"})
    create_watch_event(%{profile_id: ana.id, movie_id: movie.id, title: "Hers Only"})

    {:ok, _view, html} = live(conn, "/history")
    assert html =~ "Mine Only"
    refute html =~ "Hers Only"

    {:ok, _view, html} = conn |> with_profile(ana) |> live("/history")
    assert html =~ "Hers Only"
    refute html =~ "Mine Only"
  end
```

(Use the file's existing mount helper if it has one — `live_async!` or `live` — match its neighbours.)

`test/media_centaur/watch_history/event_test.exs`: delete the `describe "WatchHistory.delete_event!/2 (reset_progress: true)"` block; the default-delete describe's title drops the parenthetical.

- [ ] **Step 2: Run one to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/watch_history_test.exs`
Expected: FAIL — `list_events/1` with a profile id is not a keyword list (`Keyword.get` raises) or compile error on `profile_ids_with_events/0`.

- [ ] **Step 3: The migration**

`priv/repo/migrations/20261008120003_watch_history_events_per_profile.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.WatchHistoryEventsPerProfile do
  @moduledoc """
  A completion is a profile's (ADR-078, phase 2). Rebuild
  `watch_history_events` with `profile_id`, every existing event the
  oldest profile's, indexed on `(profile_id, completed_at)` for the
  History page's newest-first list. The copy fills the column, so no
  UPDATE. The entity FKs stay `nilify_all` (the table is append-only
  history). Not reversible.
  """
  use Ecto.Migration

  def up do
    create table(:watch_history_events_next, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :profile_id, references(:profiles, type: :uuid, on_delete: :delete_all), null: false
      add :entity_type, :text, null: false
      add :title, :text, null: false
      add :duration_seconds, :float, null: false, default: 0.0
      add :completed_at, :utc_datetime_usec, null: false

      add :movie_id, references(:library_movies, type: :uuid, on_delete: :nilify_all)
      add :episode_id, references(:library_episodes, type: :uuid, on_delete: :nilify_all)
      add :video_object_id, references(:library_video_objects, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    execute """
    INSERT INTO watch_history_events_next
      (id, profile_id, entity_type, title, duration_seconds, completed_at,
       movie_id, episode_id, video_object_id, inserted_at, updated_at)
    SELECT id, (SELECT id FROM profiles ORDER BY inserted_at, id LIMIT 1), entity_type, title,
           duration_seconds, completed_at, movie_id, episode_id, video_object_id, inserted_at, updated_at
    FROM watch_history_events
    """

    drop table(:watch_history_events)
    rename table(:watch_history_events_next), to: table(:watch_history_events)

    create index(:watch_history_events, [:profile_id, :completed_at])
    create index(:watch_history_events, [:completed_at])
    create index(:watch_history_events, [:entity_type])
    create index(:watch_history_events, [:movie_id])
    create index(:watch_history_events, [:episode_id])
    create index(:watch_history_events, [:video_object_id])
  end

  def down do
    raise Ecto.MigrationError, "watch_history_events_per_profile is not reversible — the profile of each event would be lost"
  end
end
```

- [ ] **Step 4: Schema, recorder, scoped readers**

`lib/media_centaur/watch_history/event.ex`: `field :profile_id, Ecto.UUID`; cast it; `validate_required([:profile_id, :entity_type, :title, :duration_seconds, :completed_at])`. Moduledoc: "Each event is one profile's completion (ADR-078)."

`lib/media_centaur/watch_history/recorder.ex`: each of the three attrs maps in `build_event_attrs/1` gains `profile_id: record.profile_id` (the `WatchProgress` record carries it). Moduledoc: "The event takes the profile from the progress row that completed."

`lib/media_centaur/watch_history.ex`:

```elixir
  @typedoc "What a reader is asked for: one profile's history, or `:all` for the install-wide view the Status page shows."
  @type scope :: Ecto.UUID.t() | :all

  @doc """
  One profile's completion events, newest first.

  Options: `:entity_type`, `:search`, `:date`, `:limit` (100), `:offset` (0).
  """
  @spec list_events(Ecto.UUID.t(), keyword()) :: [Event.t()]
  def list_events(profile_id, opts \\ []) when is_binary(profile_id) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    Event
    |> scoped(profile_id)
    |> maybe_filter_type(Keyword.get(opts, :entity_type))
    |> maybe_filter_search(Keyword.get(opts, :search))
    |> maybe_filter_date(Keyword.get(opts, :date))
    |> order_by([e], desc: e.completed_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "The N most recent completions in `scope`. Default 5."
  @spec recent_events(scope(), pos_integer()) :: [Event.t()]
  def recent_events(scope, limit \\ 5) do
    Event
    |> scoped(scope)
    |> order_by([e], desc: e.completed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec heatmap_cells_by_type(scope()) :: map()
  def heatmap_cells_by_type(scope) do
    rows =
      Event
      |> scoped(scope)
      |> where([event], event.completed_at >= ^heatmap_cutoff_dt())
      |> group_by([event], [fragment("date(?)", event.completed_at), event.entity_type])
      |> select([event], {fragment("date(?)", event.completed_at), event.entity_type, count(event.id)})
      |> Repo.all()

    …unchanged shaping…
  end

  @spec stats(scope()) :: map()
  def stats(scope) do
    %{
      total_count: Repo.aggregate(scoped(Event, scope), :count),
      total_seconds: Repo.aggregate(scoped(Event, scope), :sum, :duration_seconds) || 0.0,
      streak: compute_streak(scope),
      heatmap: heatmap_map(scope)
    }
  end

  @spec rewatch_count_map(scope(), Rewatch.entity_type()) :: %{Ecto.UUID.t() => pos_integer()}
  def rewatch_count_map(scope, type), do: Rewatch.count_per_entity(scope, type)

  @doc "Every profile with at least one completion — the profiles the summary is built for."
  @spec profile_ids_with_events() :: [Ecto.UUID.t()]
  def profile_ids_with_events,
    do: Repo.all(from(e in Event, distinct: true, select: e.profile_id, order_by: e.profile_id))

  @doc "Removes an event from history and broadcasts `{:watch_event_deleted, event}`. The progress row is untouched."
  @spec delete_event!(Event.t()) :: :ok
  def delete_event!(%Event{} = event) do
    Repo.delete!(event)
    Topics.publish(Topics.watch_history_events(), {:watch_event_deleted, event})
    :ok
  end

  @doc false
  @spec scoped(Ecto.Queryable.t(), scope()) :: Ecto.Query.t()
  def scoped(query, :all), do: query
  def scoped(query, profile_id) when is_binary(profile_id), do: where(query, [e], e.profile_id == ^profile_id)
```

`heatmap_map/1` and `compute_streak/1` start from `Event |> scoped(scope)`. Delete the three `reset_watch_progress/1` clauses, the `_event` clause and the `Library` alias if it is now unused (check: `Library.broadcast_entities_changed` was its only use here).

`lib/media_centaur/watch_history/rewatch.ex`: `count_per_entity(scope, :movie)` etc. → `do_count(scope, field)` starting from `Event |> WatchHistory.scoped(scope)` (import or alias `MediaCentaur.WatchHistory`; `scoped/2` is `@doc false` public for this).

- [ ] **Step 5: The two read models and the facade**

`lib/media_centaur/watch_history/views/summary.ex`:

```elixir
  # %{profile_id => SummaryData.t()} for every profile with an event.
  @cache_key {__MODULE__, :data}

  @impl MediaCentaur.Cache
  def refresh_cache do
    snapshot = Map.new(WatchHistory.profile_ids_with_events(), &{&1, compute(&1)})
    :persistent_term.put(@cache_key, snapshot)
    Topics.publish(Topics.watch_history_views(), {:watch_history_view_updated, :summary})
    :ok
  end

  @doc """
  One profile's snapshot. Falls back to a fresh compute when the term is
  unset (test mode, the boot window) or the profile has no events yet.
  """
  @spec read(Ecto.UUID.t()) :: SummaryData.t()
  def read(profile_id) when is_binary(profile_id) do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset -> compute(profile_id)
      snapshot -> Map.get_lazy(snapshot, profile_id, fn -> compute(profile_id) end)
    end
  end

  defp compute(profile_id) do
    %SummaryData{
      stats: WatchHistory.stats(profile_id),
      heatmap_cells_by_type: WatchHistory.heatmap_cells_by_type(profile_id),
      rewatch_counts: %{
        movie: WatchHistory.rewatch_count_map(profile_id, :movie),
        episode: WatchHistory.rewatch_count_map(profile_id, :episode),
        video_object: WatchHistory.rewatch_count_map(profile_id, :video_object)
      }
    }
  end
```

Moduledoc: "Profile-keyed (ADR-078): one `SummaryData` per profile with an event, rebuilt whole."

`lib/media_centaur/watch_history/views.ex`: `@spec summary(Ecto.UUID.t()) :: SummaryData.t()`, `def summary(profile_id), do: Summary.read(profile_id)`.

`lib/media_centaur/watch_history/views/playback_activity.ex`: `WatchHistory.recent_events(:all, @recent_limit)` and `WatchHistory.stats(:all)`. Moduledoc: add "Install-wide: the Status page sums across profiles (spec, 2026-10-06)", and delete the stale sentence about `empty/0`.

- [ ] **Step 6: The History page**

`lib/media_centaur_web/live/watch_history_live.ex`:
- `load_history/1`: `summary = WatchHistoryViews.summary(socket.assigns.profile.id)` (runs from `handle_params`' `ensure_loaded/1`).
- `filter_snapshot/1`: add `profile_id: socket.assigns.profile.id` to the map it returns; `fetch_page_for/1`: `WatchHistory.list_events(filters.profile_id, entity_type: …)`.
- `handle_info({:watch_event_created, %{profile_id: profile_id}}, socket)`: debounce only `when profile_id == socket.assigns.profile.id`; add `def handle_info({:watch_event_created, _another_profile}, socket), do: {:noreply, socket}`.
- `handle_info({:watch_history_view_updated, :summary}, socket)`: `WatchHistoryViews.summary(socket.assigns.profile.id)`.

- [ ] **Step 7: Seeder and factories**

`lib/media_centaur/showcase.ex`: `seed_watch_history!(owner_id, movies, tv_series)`; `create_movie_event!/4` and `create_episode_event!/4` take `owner_id` and put `profile_id: owner_id` in the attrs.

`test/support/factory.ex`: `build_watch_event/1` defaults gain `profile_id: Ecto.UUID.generate()`; `create_watch_event/1`:

```elixir
  def create_watch_event(attrs \\ %{}) do
    defaults = %{entity_type: :movie, title: "Test Movie", duration_seconds: 7200.0, completed_at: DateTime.utc_now(:second)}

    {:ok, event} =
      defaults
      |> Map.merge(Map.new(attrs))
      |> Map.put_new_lazy(:profile_id, &owner_profile_id/0)
      |> MediaCentaur.WatchHistory.create_event()

    event
  end
```

- [ ] **Step 8: Compile; follow the compiler and the suite**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors`

Run: `~/scripts/agents/agent-mix test test/media_centaur/watch_history test/media_centaur/watch_history_test.exs test/media_centaur/activities test/media_centaur_web/live/watch_history_live_test.exs test/media_centaur_web/live/status_live_test.exs test/media_centaur/profile`
Expected: PASS after the old-arity calls in `watch_history_test.exs` (`stats()` → `stats(owner_profile_id())` or `stats(:all)` as the test means), `summary_test.exs` (`Views.summary()` → `Views.summary(owner_profile_id())`), `playback_activity_test.exs` (events need no change: the factory defaults the profile), `watch_history_summary_suite.ex` / `suite.ex` (`Views.summary(owner_id)`, `stats(owner_id)`, …) are updated.

- [ ] **Step 9: Precommit and commit**

Run: `~/scripts/agents/agent-mix precommit`

```bash
git add -A
git commit -m "feat(watch_history): a completion is a profile's — scoped readers, per-profile summary, History page"
```

---

### Task 7: Records, docs, context map, the whole suite

**Files:**
- Modify: `test/media_centaur/profiles_test.exs`, `lib/media_centaur/profiles.ex` (doc), `lib/media_centaur/topics.ex`, `docs/superpowers/specs/2026-10-06-viewer-profiles-design.md`, `campaigns/viewer-profiles.md`, `docs/context-map/verdicts.json`, `docs/library.md`, `docs/playback.md`

- [ ] **Step 1: The cascade, proven from the Profiles side**

In `test/media_centaur/profiles_test.exs`:

```elixir
  test "remove takes the profile's watching rows with it and leaves the other profile's" do
    movie = create_standalone_movie(%{name: "Sample Movie"})
    [me] = Profiles.list()
    {:ok, ana} = Profiles.add("Ana")

    create_watch_progress(%{profile_id: ana.id, movie_id: movie.id, position_seconds: 10.0})
    create_watch_progress(%{profile_id: me.id, movie_id: movie.id, position_seconds: 20.0})
    create_watch_event(%{profile_id: ana.id, movie_id: movie.id, title: "Sample Movie"})
    {:ok, _} = MediaCentaur.Library.MediaTrackOverrides.upsert(ana.id, :movie, movie.id, %{audio_lang: "fra"})

    assert :ok = Profiles.remove(ana)

    assert {:error, :not_found} = MediaCentaur.Library.ProgressRecords.fetch_for_container(ana.id, :movie, movie.id)
    assert {:ok, %{position_seconds: 20.0}} = MediaCentaur.Library.ProgressRecords.fetch_for_container(me.id, :movie, movie.id)
    assert MediaCentaur.WatchHistory.list_events(ana.id) == []
    assert MediaCentaur.Library.MediaTrackOverrides.get(ana.id, :movie, movie.id) == nil
  end
```

Run: `~/scripts/agents/agent-mix test test/media_centaur/profiles_test.exs`
Expected: PASS (the FKs do it). In `lib/media_centaur/profiles.ex`, `remove/1`'s doc: "Phase 2 cascades the watching rows by foreign key" → "The watching rows go with it by foreign key (`ON DELETE CASCADE` on the four tables)."

- [ ] **Step 2: Docs that state the new contract**

- `lib/media_centaur/topics.ex` table: the `watch_history:events` row lists `{:watch_completed, playable_item_id}` too; the `playback:events` row reads "progress + state-change events, each naming its `profile_id`".
- `docs/library.md` (file tracking / progress section): one paragraph — watching rows are per profile, keyed `(profile_id, …)`, read through `ProgressRecords` with the profile first; the `has_one :watch_progress` path is gone.
- `docs/playback.md`: `Playback.play/2` takes the profile; the socket name carries it; a legacy socket is skipped on recovery.
- Spec `docs/superpowers/specs/2026-10-06-viewer-profiles-design.md`, a dated amendment block under "Watching per profile (phase 2)":

```markdown
**Amendments, 2026-10-08 (phase 2 unify pass).** `HeroCandidates` reads no
watching state and is not keyed by profile. `PlaybackActivity` is the Status
page's widget, install-wide, reading scope `:all`; `WatchHistory`'s readers
take a scope of a profile id or `:all`. The `has_one :watch_progress`
associations and `EntityShape.extract_progress/2` are removed: a title's
progress is read through `ProgressRecords.list_for_container/3` only.
`WatchHistory.delete_event!/2`'s unused `reset_progress` option is removed.
The mpv socket is `media-centaur-<entity_id>.<profile_id>.sock` so a
recovered session keeps its profile; a socket in the old shape is skipped.
`Playback.play/2` takes the profile first. The backfill is the rebuild's
`INSERT … SELECT`, so no `UPDATE` and no MC0015 carve-out.
```

- `campaigns/viewer-profiles.md`: Status → "Phase 2 built and gated on branch `viewer-profiles`, <date>"; Decisions gain a `2026-10-08` entry listing the unify dispositions above (has_one removal, legacy socket skipped, scope type, dead option removed, dead `watch_progress: []` fields noted for a later cleanup); Next steps → phase 3 (docs: FAQ, README, wiki, Settings reference, UIDR-012 amendment, screenshots) and the owner's merge; the hand-off section rewritten for the next session.

- [ ] **Step 3: Context map**

Run: `~/scripts/agents/agent-mix context_map --diff`
Expected: new crossings where the web layer passes `profile.id` into `Library`, `WatchHistory` and `Playback`, and where `Playback` reads `WatchProgress.profile_id`. For each, add a verdict in `docs/context-map/verdicts.json` (`"allowed"`, reason "the profile id is the parameter of every read and write of watching state (ADR-078); the id is opaque to the receiving context"). Then `~/scripts/agents/agent-mix context_map` to regenerate the committed map.

- [ ] **Step 4: Precommit and the whole suite, logged**

Run: `~/scripts/agents/agent-mix precommit 2>&1 | tee /tmp/claude-1000/phase2-precommit.log | tail -30`
Expected: format clean, credo clean, boundaries clean, 0 warnings, all tests pass. A `Database busy` or a context-map timeout under load: re-run that file alone.

- [ ] **Step 5: Final commit and hand-off**

```bash
git add -A
git commit -m "docs: phase 2 amendments, campaign status, context-map verdicts"
git log --oneline main..HEAD | head -40
```

Report the branch, the worktree path and the suite count to the owner. Do not merge; do not push.

---

## Self-review

**Spec coverage.** Four tables with `profile_id` and the new unique keys — Tasks 3–6. Profile-first signatures on `Progress`, `ProgressRecords`, `list_in_progress`, `MediaTrackOverrides`, `WatchHistory` — Tasks 3, 5, 6. Worker key — Task 3. `Playback.play/2`, params, session held for life, resume/next-episode/track policy per profile — Tasks 1, 3, 4, 5. `SessionEnded` and `PlaybackStateChanged` carry `profile_id`; the Recorder writes it; the Publisher ignores it — Tasks 1, 6. Finish prompt only in the watcher's session — Task 1. Continue Watching, Summary keyed by profile; derived messages unchanged — Tasks 3, 6. Status counts install-wide — Task 6. Cascade on removal — Task 7 (and 3, 6). Factories default to a profile — Tasks 1, 3, 4, 6. Showcase seeder under the owner — Tasks 3, 5, 6. Two-profile isolation tests for progress, resume, Continue Watching, history, track memory, finish prompt — Tasks 1, 3, 4, 5, 6. Spec's hero/PlaybackActivity slips — recorded in Task 7.

**Type consistency.** `profile_id` is always the first positional argument; `Playback.play(profile_id, uuid)`, `Resolver.resolve(profile_id, uuid)`, `NextEpisode.resolve(profile_id, episode_id)`, `ProgressBroadcaster.broadcast(profile_id, entity_id, changed)` / `broadcast_extra(profile_id, entity_id, extra_id)`, `Views.continue_watching(profile_id, opts)`, `Views.summary(profile_id)`, `LibraryHalf.load(profile_id, ref)`. `WatchHistory.scope()` is the one place `:all` is accepted. `upsert_by_profile_item!/1` replaces `upsert_by_playable_item!/1` and is the worker's only write.
