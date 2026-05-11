defmodule MediaCentarr.Acquisition.Pursuits do
  @moduledoc """
  Read-side queries over the pursuit aggregate.

  Write-side operations live in `Acquisition.Pursuits.Commands.*`. This
  module is intentionally read-only — it never mutates state, never
  broadcasts, never enqueues jobs. Callers that want to change the
  world go through a command. ViewModel assemblers also live here
  because shaping rows for the UI is a read concern.
  """

  import Ecto.Query

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit, State}
  alias MediaCentarr.Acquisition.{QueueMatcher, Target}

  alias MediaCentarr.Acquisition.ViewModels.{
    PursuitHeader,
    PursuitRow,
    PursuitStatus,
    Recipe,
    Timeline,
    TimelineEntry
  }

  alias MediaCentarr.Downloads.QueueItem
  alias MediaCentarr.Downloads.QueueMonitor
  alias MediaCentarr.Repo

  @recent_events_limit 3

  @spec get(Ecto.UUID.t()) :: {:ok, Pursuit.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Pursuit, id) do
      nil -> {:error, :not_found}
      %Pursuit{} = pursuit -> {:ok, pursuit}
    end
  end

  @doc "Lists every in-flight pursuit (`active` or `needs_decision`), newest-updated first."
  @spec list_active() :: [Pursuit.t()]
  def list_active do
    Pursuit
    |> where([p], p.state in ^State.in_flight())
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc "Lists active pursuits as `PursuitRow` view-models with the last few events attached."
  @spec list_active_rows() :: [PursuitRow.t()]
  def list_active_rows do
    pursuits = list_active()

    pursuit_ids = Enum.map(pursuits, & &1.id)
    events_by_pursuit = recent_events_by_pursuit(pursuit_ids, @recent_events_limit)

    current_targets =
      pursuits
      |> Enum.map(& &1.current_target_id)
      |> Enum.reject(&is_nil/1)
      |> fetch_targets_by_id()

    Enum.map(pursuits, fn pursuit ->
      events = Map.get(events_by_pursuit, pursuit.id, [])
      target = Map.get(current_targets, pursuit.current_target_id)
      build_row(pursuit, events, target)
    end)
  end

  @doc "Returns a `PursuitHeader` view-model for the detail page."
  @spec header_for(Ecto.UUID.t()) :: {:ok, PursuitHeader.t()} | {:error, :not_found}
  def header_for(id) do
    case get(id) do
      {:ok, pursuit} -> {:ok, build_header(pursuit)}
      {:error, :not_found} = error -> error
    end
  end

  @doc """
  Returns the full `PursuitStatus` view-model for the detail page —
  identity + current activity + available manual triggers + staleness.
  """
  @spec status_for(Ecto.UUID.t()) :: {:ok, PursuitStatus.t()} | {:error, :not_found}
  def status_for(id) do
    case get(id) do
      {:error, :not_found} = error ->
        error

      {:ok, pursuit} ->
        target = current_target(pursuit)
        queue_item = find_queue_match(target)
        {current_action, next_step, actions} = PursuitStatus.derive(pursuit, target, queue_item)
        last_activity_at = latest_event_at(id)

        status = %PursuitStatus{
          pursuit_id: pursuit.id,
          title: pursuit.title,
          state: String.to_existing_atom(pursuit.state),
          origin: String.to_existing_atom(pursuit.origin),
          recipe: build_recipe(pursuit),
          criteria_summary: summarize_criteria(pursuit.criteria),
          current_action: current_action,
          next_step: next_step,
          download: QueueMatcher.to_download(queue_item),
          staleness: staleness_for(last_activity_at),
          last_activity_at: last_activity_at,
          available_actions: actions
        }

        {:ok, status}
    end
  end

  @doc "Returns a `Timeline` view-model containing every event for a pursuit."
  @spec timeline_for(Ecto.UUID.t()) :: Timeline.t()
  def timeline_for(pursuit_id) do
    entries =
      pursuit_id
      |> events_for()
      |> Enum.map(&entry_for_event/1)

    %Timeline{pursuit_id: pursuit_id, entries: entries}
  end

  @doc """
  Returns events for a pursuit, newest first. Empty list for unknown
  pursuit_id — events with nilified `pursuit_id` are not surfaced here.
  """
  @spec events_for(Ecto.UUID.t()) :: [Event.t()]
  def events_for(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  @doc """
  Returns active pursuits whose TMDB recipe matches the given map.

  Accepts `%{tmdb_id, tmdb_type}` and optional `:season_number` /
  `:episode_number`. TV pursuits without a season pin (e.g.,
  season-pack pursuits) match any episode for that series; movie
  pursuits match by `tmdb_id` alone.

  Only matches pursuits with `recipe_type = "tmdb"` — query-recipe
  pursuits have no TMDB metadata to match against. Used by
  `Pursuits.InboundListener` to dispatch identity verification when a
  file lands for a tracked target.
  """
  @spec find_active_for_target(map()) :: [Pursuit.t()]
  def find_active_for_target(%{tmdb_id: tmdb_id, tmdb_type: "movie"}) when is_binary(tmdb_id) do
    Pursuit
    |> where([p], p.state == "active" and p.recipe_type == "tmdb")
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "movie")
    |> Repo.all()
  end

  def find_active_for_target(%{tmdb_id: tmdb_id, tmdb_type: "tv"} = target) when is_binary(tmdb_id) do
    season = Map.get(target, :season_number)
    episode = Map.get(target, :episode_number)

    Pursuit
    |> where([p], p.state == "active" and p.recipe_type == "tmdb")
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "tv")
    |> match_season(season)
    |> match_episode(episode)
    |> Repo.all()
  end

  def find_active_for_target(_), do: []

  defp match_season(query, nil), do: query

  defp match_season(query, season) do
    where(query, [p], is_nil(p.season_number) or p.season_number == ^season)
  end

  defp match_episode(query, nil), do: query

  defp match_episode(query, episode) do
    where(query, [p], is_nil(p.episode_number) or p.episode_number == ^episode)
  end

  @doc """
  Returns the pursuit's current target (the row pointed at by
  `pursuit.current_target_id`), if any.
  """
  @spec current_target(Pursuit.t()) :: Target.t() | nil
  def current_target(%Pursuit{current_target_id: nil}), do: nil
  def current_target(%Pursuit{current_target_id: id}), do: Repo.get(Target, id)

  @doc """
  Returns the most recently inserted target linked to a pursuit
  (regardless of which is the pursuit's `current_target_id` — useful
  for history queries that want "the latest attempt").
  """
  @spec latest_target(Ecto.UUID.t()) :: {:ok, Target.t()} | {:error, :not_found}
  def latest_target(pursuit_id) do
    target =
      Target
      |> where([t], t.pursuit_id == ^pursuit_id)
      |> order_by([t], desc: t.inserted_at)
      |> limit(1)
      |> Repo.one()

    case target do
      nil -> {:error, :not_found}
      %Target{} = target -> {:ok, target}
    end
  end

  @doc "Returns all targets for a pursuit, newest-inserted first."
  @spec targets_for(Ecto.UUID.t()) :: [Target.t()]
  def targets_for(pursuit_id) do
    Target
    |> where([t], t.pursuit_id == ^pursuit_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  # --- ViewModel assembly ----------------------------------------------------

  defp fetch_targets_by_id([]), do: %{}

  defp fetch_targets_by_id(ids) do
    Target
    |> where([t], t.id in ^ids)
    |> Repo.all()
    |> Map.new(fn target -> {target.id, target} end)
  end

  defp recent_events_by_pursuit([], _limit), do: %{}

  # One LIMIT-bounded query per pursuit. The previous implementation
  # loaded EVERY event for the listed pursuits, grouped in-memory, then
  # discarded all but the head — a long-running pursuit with thousands
  # of events would pull all of them every render. Per-pursuit
  # subqueries keep the worst-case payload bounded by `limit` rows
  # times the number of active pursuits.
  defp recent_events_by_pursuit(pursuit_ids, limit) do
    Map.new(pursuit_ids, fn pursuit_id ->
      events =
        Event
        |> where([e], e.pursuit_id == ^pursuit_id)
        |> order_by([e], desc: e.occurred_at)
        |> limit(^limit)
        |> Repo.all()

      {pursuit_id, events}
    end)
  end

  defp build_row(%Pursuit{} = pursuit, events, target) do
    {release_title, target_status} =
      case target do
        %Target{release_title: rt, status: status} -> {rt, status_to_atom(status)}
        nil -> {nil, nil}
      end

    %PursuitRow{
      id: pursuit.id,
      title: pursuit.title,
      state: String.to_existing_atom(pursuit.state),
      origin: String.to_existing_atom(pursuit.origin),
      attempt_count: pursuit.attempt_count,
      recent_events: Enum.map(events, &entry_for_event/1),
      detail_path: "/download/#{pursuit.id}",
      release_title: release_title,
      target_status: target_status,
      inserted_at: pursuit.inserted_at,
      updated_at: pursuit.updated_at
    }
  end

  defp status_to_atom(nil), do: nil
  defp status_to_atom(status) when is_binary(status), do: String.to_existing_atom(status)

  defp build_header(%Pursuit{} = pursuit) do
    %PursuitHeader{
      id: pursuit.id,
      title: pursuit.title,
      state: String.to_existing_atom(pursuit.state),
      recipe: build_recipe(pursuit),
      criteria_summary: summarize_criteria(pursuit.criteria)
    }
  end

  defp entry_for_event(%Event{} = event) do
    %TimelineEntry{
      kind: event.kind,
      occurred_at: event.occurred_at,
      summary: summary_for(event.kind, event.payload),
      severity: severity_for(event.kind),
      detail: detail_for(event.kind, event.payload)
    }
  end

  defp summary_for("pursuit_started", %{"origin" => "auto"}), do: "Pursuit started (auto)"
  defp summary_for("pursuit_started", %{"origin" => "manual"}), do: "Pursuit started (manual)"
  defp summary_for("pursuit_started", _), do: "Pursuit started"
  defp summary_for("search_started", _), do: "Searching Prowlarr"

  defp summary_for("release_picked", %{"release_title" => t}) when is_binary(t),
    do: "Release picked — #{t}"

  defp summary_for("release_picked", _), do: "Release picked"
  defp summary_for("release_no_match", _), do: "No acceptable release found"
  defp summary_for("download_started", _), do: "Download started"

  defp summary_for("health_changed", payload) when is_map(payload) do
    state_part = transition_phrase(payload["from_state"], payload["to_state"])
    health_part = transition_phrase(payload["from_health"], payload["to_health"])

    case {state_part, health_part} do
      {nil, nil} -> "Health changed"
      {state, nil} -> "State #{state}"
      {nil, health} -> "Health #{health}"
      {state, health} -> "State #{state}, health #{health}"
    end
  end

  defp summary_for("health_changed", _), do: "Health changed"
  defp summary_for("stall_confirmed", _), do: "Stall confirmed"
  defp summary_for("zero_seeders_confirmed", _), do: "Zero seeders confirmed"
  defp summary_for("auto_cancelled", %{"reason" => r}), do: "Auto-cancelled (#{r})"
  defp summary_for("auto_cancelled", _), do: "Auto-cancelled"
  defp summary_for("fallback_initiated", _), do: "Fallback initiated"
  defp summary_for("user_decision_requested", _), do: "User decision requested"
  defp summary_for("user_decision_recorded", %{"choice" => c}), do: "User picked — #{c}"
  defp summary_for("user_decision_recorded", _), do: "User decision recorded"
  defp summary_for("identity_mismatch", _), do: "Identity mismatch — file routed to Review"
  defp summary_for("identity_verified", _), do: "Identity verified"
  defp summary_for("pursuit_satisfied", _), do: "Pursuit satisfied"
  defp summary_for("pursuit_exhausted", %{"reason" => r}), do: "Pursuit exhausted (#{r})"
  defp summary_for("pursuit_exhausted", _), do: "Pursuit exhausted"
  defp summary_for("pursuit_cancelled", _), do: "Pursuit cancelled"
  defp summary_for("target_changed", _), do: "Target changed"
  defp summary_for(kind, _), do: kind

  defp transition_phrase(same, same), do: nil
  defp transition_phrase(nil, to) when is_binary(to), do: to
  defp transition_phrase(from, to) when is_binary(from) and is_binary(to), do: "#{from} → #{to}"
  defp transition_phrase(_, _), do: nil

  defp severity_for(kind) when kind in ~w(stall_confirmed zero_seeders_confirmed), do: :warning
  defp severity_for(kind) when kind in ~w(identity_mismatch pursuit_exhausted), do: :error

  defp severity_for(kind) when kind in ~w(release_picked identity_verified pursuit_satisfied),
    do: :success

  defp severity_for(_), do: :info

  defp detail_for("release_picked", %{"indexer" => indexer, "quality" => q}), do: "#{indexer} • #{q}"

  defp detail_for("release_picked", %{"quality" => q}), do: q
  defp detail_for(_, _), do: nil

  defp summarize_criteria(nil), do: nil
  defp summarize_criteria(map) when map_size(map) == 0, do: nil

  defp summarize_criteria(map) when is_map(map) do
    map
    |> Enum.sort()
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{v}" end)
  end

  # --- status_for helpers ----------------------------------------------------

  defp build_recipe(%Pursuit{recipe_type: "tmdb"} = p) do
    %Recipe{
      recipe_type: :tmdb,
      tmdb_type: p.tmdb_type,
      tmdb_id: p.tmdb_id,
      season_number: p.season_number,
      episode_number: p.episode_number,
      year: p.year
    }
  end

  defp build_recipe(%Pursuit{recipe_type: "prowlarr_query"} = p) do
    %Recipe{
      recipe_type: :prowlarr_query,
      manual_query: p.manual_query
    }
  end

  defp find_queue_match(nil), do: nil
  defp find_queue_match(%Target{release_title: nil}), do: nil

  defp find_queue_match(%Target{release_title: title}) do
    normalized = QueueMatcher.normalize_title(title)

    Enum.find(QueueMonitor.snapshot(), fn %QueueItem{} = item ->
      QueueMatcher.normalize_title(item.title) == normalized
    end)
  end

  defp latest_event_at(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id)
    |> order_by([e], desc: e.occurred_at)
    |> limit(1)
    |> select([e], e.occurred_at)
    |> Repo.one()
  end

  defp staleness_for(nil), do: :very_stale

  defp staleness_for(%DateTime{} = ts) do
    diff_seconds = DateTime.diff(DateTime.utc_now(:second), ts)

    cond do
      diff_seconds < 3600 -> :fresh
      diff_seconds < 86_400 -> :stale
      true -> :very_stale
    end
  end
end
