defmodule MediaCentarr.Topics do
  @moduledoc """
  PubSub topic constants. Centralises all topic strings so typos
  become compile-time failures instead of silent subscription misses.

  ## Taxonomy (ADR-041)

  Topics fall into one of three roles. Pick the right one when adding
  a new topic — the role determines who broadcasts and who subscribes.

  ### 1. Source topics (canonical events)

  Carry canonical events about the truth. Only the source-of-truth
  context broadcasts on these. Other contexts and Cache.Workers
  subscribe.

  | Topic | Owner | Carries |
  |-------|-------|---------|
  | `library:updates` | `Library` | `{:entities_changed, %EntitiesChanged{}}` |
  | `library:commands` | `Library` | external write commands |
  | `library:file_events` | `Library` | per-file lifecycle |
  | `library:watch_completed` | `Library` | end-of-watch markers |
  | `library:availability` | `Library.Availability` | `{:availability_changed, dir, state}` |
  | `playback:events` | `Playback` | progress + state-change events |
  | `watch_history:events` | `WatchHistory` | `{:watch_event_created, _}`, `{:watch_event_deleted, _}` |
  | `release_tracking:updates` | `ReleaseTracking` | `{:releases_updated, _}`, `{:item_removed, _, _}`, `{:release_ready, _, _}` |
  | `acquisition:updates` | `Acquisition` | grab lifecycle |
  | `acquisition:queue` | `Downloads` | download-client queue snapshots (topic name kept — rename deferred per ADR-043) |
  | `acquisition:search` | `Acquisition` | per-search results |
  | `settings:updates` | `Settings` | per-key changes |
  | `config:updates` | `Config` | TOML reload |
  | `capabilities:updates` | `Capabilities` | service-readiness flips |
  | `controls:updates` | `Controls` | global control changes |
  | `watcher:state` | `Watcher` | dir-watch state transitions |
  | `review:intake`, `review:updates` | `Review` | review-queue events |
  | `pipeline:input`, `:matched`, `:images`, `:publish` | `Pipeline` | per-stage progress |
  | `console:logs` | `Console` | log stream for the in-app drawer |
  | `service:journal` | `Service` | systemd-journal mirror |
  | `self_update:status`, `:progress` | `SelfUpdate` | release self-update lifecycle |
  | `error_reports:updates` | `ErrorReports` | error-report intake |

  ### 2. Derived view topics (`*:views`)

  Emitted by `Cache.Worker`-driven projections after each ETS
  rebuild. **LiveViews subscribe here, never to source topics for
  cache-driven data.** Payload shape: `{:*_view_updated, view_id}`.

  | Topic | Emitted by | Payloads |
  |-------|-----------|----------|
  | `library:views` | `Library.Views.*` projections | `{:library_view_updated, :continue_watching \| :hero_candidates \| :recently_added}` |
  | `release_tracking:views` | `ReleaseTracking.Views.*` projections | `{:release_tracking_view_updated, :coming_up}` |
  | `watch_history:views` | `WatchHistory.Views.*` projections | `{:watch_history_view_updated, :summary}` |

  Adding a new projection that needs its own derived topic: prefer
  one topic per source-context (e.g. `watch_history:views` for any
  WatchHistory.Views.*) over a single firehose. Per-context topics
  let LiveViews subscribe only to the contexts they actually consume.

  ### 3. Internal coordination

  Not for cross-context use; documented here so the boundary stays
  visible. Currently empty — most cross-process coordination flows
  through one of the above.

  ## Discipline

  * Topic strings live here, not inline in modules. Typos surface as
    compile errors when `Topics.foo()` is misspelt; inline strings
    silently fail to deliver.
  * Source events name the *fact* (`:entity_progress_updated`),
    derived events name the *view* (`:library_view_updated`). The
    discriminator is the second tuple element.
  * If you find yourself subscribing to a source topic from a
    LiveView for cache-driven data, stop — either the projection is
    missing, or it should be broadcasting on a derived topic. See
    `MediaCentarr.Cache` moduledoc for the projection pattern.
  """
  use Boundary, top_level?: true, check: [in: false, out: false]

  def library_updates, do: "library:updates"
  def library_commands, do: "library:commands"
  def library_file_events, do: "library:file_events"
  def library_watch_completed, do: "library:watch_completed"
  def library_availability, do: "library:availability"
  def pipeline_input, do: "pipeline:input"
  def pipeline_matched, do: "pipeline:matched"
  def pipeline_images, do: "pipeline:images"
  def pipeline_publish, do: "pipeline:publish"
  def playback_events, do: "playback:events"
  def dir_state, do: "watcher:state"
  def review_intake, do: "review:intake"
  def review_updates, do: "review:updates"
  def settings_updates, do: "settings:updates"
  def config_updates, do: "config:updates"
  def release_tracking_updates, do: "release_tracking:updates"
  def watch_history_events, do: "watch_history:events"
  def console_logs, do: "console:logs"
  def service_journal, do: "service:journal"
  def acquisition_updates, do: "acquisition:updates"
  def acquisition_queue, do: "acquisition:queue"
  def acquisition_search, do: "acquisition:search"
  def capabilities_updates, do: "capabilities:updates"
  def self_update_status, do: "self_update:status"
  def self_update_progress, do: "self_update:progress"
  def controls_updates, do: "controls:updates"
  def error_reports, do: "error_reports:updates"
  def library_views, do: "library:views"
  def release_tracking_views, do: "release_tracking:views"
  def watch_history_views, do: "watch_history:views"
end
