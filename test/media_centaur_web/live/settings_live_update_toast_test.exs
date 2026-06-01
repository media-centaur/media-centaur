defmodule MediaCentaurWeb.SettingsLiveUpdateToastTest do
  @moduledoc """
  During a self-update reboot the WebSocket drops, and by then the server is
  already dead — so it can't relabel the disconnect toast. Instead the
  LiveView pushes a lifecycle flag to the client *before* the reboot, so the
  client can swap the scary red "Not connected to server" toast for a calm
  "Applying update" one.

  These tests pin the server side of that contract: the LiveView pushes
  `mc:update:applying` while an update is in flight and `mc:update:aborted`
  when it fails/stalls/cancels (so the red toast returns for genuine
  disconnects). The toast styling itself is wired in `layouts.ex` /
  `app.css` / `app.js`.
  """
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Topics

  defp broadcast_progress(message) do
    Phoenix.PubSub.broadcast(MediaCentaur.PubSub, Topics.self_update_progress(), message)
  end

  test "the first apply phase pushes mc:update:applying", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings")

    broadcast_progress({:progress, :preparing, nil})

    assert_push_event(view, "mc:update:applying", %{})
  end

  test "an intermediate apply phase keeps the flag set", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings")

    broadcast_progress({:progress, :extracting, 60})

    assert_push_event(view, "mc:update:applying", %{})
  end

  test "the reboot-imminent :done phase pushes mc:update:applying", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings")

    broadcast_progress({:progress, :done, 100})

    assert_push_event(view, "mc:update:applying", %{})
  end

  test "a failed apply pushes mc:update:aborted so the red toast returns", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings")

    broadcast_progress({:apply_failed, :checksum_mismatch})

    assert_push_event(view, "mc:update:aborted", %{})
  end

  test "a stalled handoff pushes mc:update:aborted", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings")

    # :done marks the phase and arms the 6s stuck timer. Fire the timer
    # message directly rather than waiting it out.
    broadcast_progress({:progress, :done, 100})
    send(view.pid, :apply_done_stuck)

    assert_push_event(view, "mc:update:aborted", %{})
  end

  test "a cancelled apply pushes mc:update:aborted", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings")

    broadcast_progress({:apply_cancelled})

    assert_push_event(view, "mc:update:aborted", %{})
  end
end
