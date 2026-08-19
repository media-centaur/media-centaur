defmodule MediaCentaurWeb.IncomingNavTest do
  @moduledoc """
  Pins the DDR-015 sidebar contract: ONE unconditional "Incoming" entry
  replaces the old conditional "Downloads" + unconditional "Upcoming"
  pair. Without acquisition capabilities the page degrades to an honest
  forecast instead of disappearing, so the nav entry must render in BOTH
  capability states — and must not flicker away when a
  `:capabilities_changed` broadcast re-renders the layout.

  (This file previously asserted the inverse — that the Downloads entry
  hid until `:acquisition_ready` flipped. That gating retired with the
  merge; the reactive `:capabilities_changed` re-render path it exercised
  is still driven here.)
  """

  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Topics

  @cache_key {Capabilities, :ready_flags}
  @ready_true %{
    tmdb: true,
    prowlarr: true,
    torrent_client: true,
    usenet_client: false,
    download_client: true,
    acquisition: true
  }
  @ready_false %{
    tmdb: false,
    prowlarr: false,
    torrent_client: false,
    usenet_client: false,
    download_client: false,
    acquisition: false
  }

  @incoming_nav_entry ~s(#sidebar a[href="/incoming"])

  setup do
    config_backup = :persistent_term.get({Config, :config})
    cache_backup = :persistent_term.get(@cache_key, :__unset)

    on_exit(fn ->
      :persistent_term.put({Config, :config}, config_backup)

      case cache_backup do
        :__unset -> :persistent_term.erase(@cache_key)
        flags -> :persistent_term.put(@cache_key, flags)
      end
    end)

    :ok
  end

  test "Incoming nav entry renders without any acquisition capability", %{conn: conn} do
    :persistent_term.put(@cache_key, @ready_false)

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, @incoming_nav_entry)
  end

  test "Incoming nav entry renders with acquisition fully ready", %{conn: conn} do
    :persistent_term.put(@cache_key, @ready_true)

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, @incoming_nav_entry)
  end

  test "Incoming nav entry survives a :capabilities_changed re-render", %{conn: conn} do
    :persistent_term.put(@cache_key, @ready_false)

    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, @incoming_nav_entry)

    :persistent_term.put(@cache_key, @ready_true)
    Phoenix.PubSub.broadcast(MediaCentaur.PubSub, Topics.capabilities_updates(), :capabilities_changed)

    # Drive the broadcast through the LV before asserting — the entry must
    # still be there after the capability-driven re-render, not just before.
    assert render(view) =~ "Incoming"
    assert has_element?(view, @incoming_nav_entry)
  end
end
