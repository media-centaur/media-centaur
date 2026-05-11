defmodule MediaCentarr.Acquisition.PursuitsStatusForTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.ViewModels.PursuitStatus
  alias MediaCentarr.Downloads.QueueItem
  alias MediaCentarr.Downloads.QueueState

  @queue_cache_key {MediaCentarr.Downloads.QueueMonitor, :state}

  setup do
    on_exit(fn -> :persistent_term.put(@queue_cache_key, %QueueState{items: []}) end)
    :persistent_term.put(@queue_cache_key, %QueueState{items: []})
    :ok
  end

  defp put_queue(items), do: :persistent_term.put(@queue_cache_key, %QueueState{items: items})

  test "returns :not_found for unknown pursuit_id" do
    assert {:error, :not_found} = Pursuits.status_for(Ecto.UUID.generate())
  end

  test "active manual pursuit with grabbed grab and no queue match -> Waiting" do
    pursuit = create_pursuit(%{state: "active", origin: "manual", title: "Sample Movie"})
    _grab = create_grab(%{pursuit_id: pursuit.id, status: "grabbed", title: pursuit.title})

    {:ok, %PursuitStatus{} = status} = Pursuits.status_for(pursuit.id)

    assert status.current_action.verb == "Waiting"
    assert :re_search in status.available_actions
    assert status.download == nil
  end

  test "active grab matched in queue -> Downloading with DownloadProgress" do
    pursuit = create_pursuit(%{state: "active", title: "Public Domain Reel"})

    _grab =
      create_grab(%{
        pursuit_id: pursuit.id,
        status: "grabbed",
        title: pursuit.title,
        release_title: "Public.Domain.Reel.1080p.WEB-DL.mkv"
      })

    put_queue([
      %QueueItem{
        id: "abc",
        title: "Public.Domain.Reel.1080p.WEB-DL.mkv",
        state: :downloading,
        progress: 0.42,
        download_client: "qBittorrent"
      }
    ])

    {:ok, %PursuitStatus{} = status} = Pursuits.status_for(pursuit.id)

    assert status.current_action.verb == "Downloading"
    assert status.download != nil
    assert status.download.state == :downloading
    assert_in_delta status.download.progress_pct, 42.0, 0.01
    assert status.download.client == "qBittorrent"
  end

  test "staleness :very_stale for events older than 24h" do
    pursuit = create_pursuit(%{state: "active", title: "Movie A"})
    _grab = create_grab(%{pursuit_id: pursuit.id, status: "grabbed", title: pursuit.title})

    older_than_24h = DateTime.add(DateTime.utc_now(:second), -48 * 3600, :second)
    create_pursuit_event(pursuit, "pursuit_started", %{occurred_at: older_than_24h})

    {:ok, status} = Pursuits.status_for(pursuit.id)
    assert status.staleness == :very_stale
  end

  test "staleness :fresh when latest event is within the last hour" do
    pursuit = create_pursuit(%{state: "active", title: "Movie B"})
    _grab = create_grab(%{pursuit_id: pursuit.id, status: "grabbed", title: pursuit.title})
    create_pursuit_event(pursuit, "pursuit_started")

    {:ok, status} = Pursuits.status_for(pursuit.id)
    assert status.staleness == :fresh
  end
end
