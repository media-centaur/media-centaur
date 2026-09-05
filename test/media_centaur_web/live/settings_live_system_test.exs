defmodule MediaCentaurWeb.SettingsLiveSystemTest do
  @moduledoc """
  Integration tests for the system content on Settings > Overview — version
  display, the no-auto-check-on-landing behaviour (the scheduled CheckerJob
  owns polling), the 5-minute cache, and the manual "Check for updates" button.

  Update network activity only happens on the prod release channel
  (`SelfUpdate.enabled?()`); dev/test rebuild from source and never poll or
  self-update. These tests therefore run with the environment set to `:prod`
  to exercise the real check flow.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.SelfUpdate.UpdateChecker

  setup do
    # UpdateChecker's client is routed to the :github Req.Test stub, so
    # checks issued by the LiveView hit our stub.
    Req.Test.stub(:github, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        JSON.encode!(%{
          "tag_name" => "v99.0.0",
          "name" => "v99.0.0",
          "published_at" => "2099-01-01T00:00:00Z",
          "html_url" => "https://example.test/releases/v99.0.0"
        })
      )
    end)

    Req.Test.set_req_test_from_context(%{async: false})

    # The cache is global (persistent_term) — reset it so each test starts
    # from a known empty state and can't be polluted by prior runs.
    UpdateChecker.clear_cache()

    # Checks (scheduled, landing, and manual) only run on the prod release
    # channel; flip the environment so the check flow under test actually
    # executes. Restored on exit.
    Application.put_env(:media_centaur, :environment, :prod)

    on_exit(fn -> Application.put_env(:media_centaur, :environment, :test) end)

    :ok
  end

  test "overview section mounts and renders the current version", %{conn: conn} do
    {:ok, _view, html} = live_async!(conn, ~p"/settings?section=system")
    assert html =~ MediaCentaur.Version.current_version()
  end

  test "overview links to the guide", %{conn: conn} do
    {:ok, _view, html} = live_async!(conn, ~p"/settings?section=system")
    assert html =~ ~p"/guide"
    assert html =~ "Open the guide"
  end

  test "landing on overview does not trigger an update check (the scheduled job owns polling)",
       %{conn: conn} do
    # Arriving on the page must never kick a network poll — the background
    # CheckerJob is the single scheduled poller. With an empty cache the card
    # renders the idle/current state, never the freshly-fetched v99.0.0.
    {:ok, view, _html} = live_async!(conn, ~p"/settings?section=system")

    # Permit the stub so that *if* a stray check fired, it would resolve to
    # v99.0.0 and fail the assertion below — otherwise this proves nothing.
    Req.Test.allow(:github, self(), view.pid)

    # Give any would-be auto-check a window to run; none should.
    Process.sleep(100)

    refute render(view) =~ "v99.0.0"
  end

  test "landing on overview uses the cached result and does not fetch", %{conn: conn} do
    # Pre-populate cache with a distinct version so we can tell whether a
    # fresh fetch happened.
    cached = %{
      version: "55.0.0",
      tag: "v55.0.0",
      published_at: ~U[2050-01-01 00:00:00Z],
      html_url: "https://example.test/releases/v55.0.0"
    }

    :ok = UpdateChecker.cache_result({:ok, cached})

    {:ok, view, _html} = live_async!(conn, ~p"/settings?section=system")

    # Give any would-be auto-check a window to run; none should.
    Process.sleep(100)

    html = render(view)
    assert html =~ "v55.0.0"
    refute html =~ "v99.0.0"
  end

  test "landing on overview with a cached error reuses the error result", %{conn: conn} do
    :ok = UpdateChecker.cache_result({:error, :not_found})

    {:ok, view, _html} = live_async!(conn, ~p"/settings?section=system")
    Process.sleep(100)

    # The live stub returns v99.0.0 — confirm no fetch happened by asserting
    # the live version is NOT rendered.
    refute render(view) =~ "v99.0.0"
  end

  test "manual 'Check for updates' fetches fresh even when cache is populated",
       %{conn: conn} do
    cached = %{
      version: "55.0.0",
      tag: "v55.0.0",
      published_at: ~U[2050-01-01 00:00:00Z],
      html_url: "https://example.test/releases/v55.0.0"
    }

    :ok = UpdateChecker.cache_result({:ok, cached})

    {:ok, view, _html} = live_async!(conn, ~p"/settings?section=system")
    Process.sleep(100)
    assert render(view) =~ "v55.0.0"

    Req.Test.allow(:github, self(), view.pid)
    render_click(view, "check_updates", %{})

    assert_eventually(fn -> render(view) =~ "v99.0.0" end)
  end

  test "a manual check writes results back to the cache", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings?section=system")
    Req.Test.allow(:github, self(), view.pid)
    render_click(view, "check_updates", %{})

    assert_eventually(fn -> render(view) =~ "v99.0.0" end)

    assert {:fresh, {:ok, %{version: "99.0.0"}}} = UpdateChecker.cached_latest_release()
  end

  test "a failed check resolves the card to an error instead of hanging on 'Checking…'",
       %{conn: conn} do
    # The card's checking state must resolve through the owned async task, not
    # rely on a completion broadcast reaching this view (the prod hang fixed in
    # v0.80.x — a worker→view PubSub gap left it stuck on "Checking…").
    Req.Test.stub(:github, fn conn ->
      Plug.Conn.send_resp(conn, 404, "not found")
    end)

    {:ok, view, _html} = live_async!(conn, ~p"/settings?section=system")
    Req.Test.allow(:github, self(), view.pid)
    render_click(view, "check_updates", %{})

    assert_eventually(fn ->
      html = render(view)
      html =~ "Update check error" and not (html =~ "Checking GitHub releases")
    end)
  end

  defp assert_eventually(check, remaining \\ 20) do
    if check.() do
      :ok
    else
      if remaining > 0 do
        Process.sleep(50)
        assert_eventually(check, remaining - 1)
      else
        flunk("condition not met after waiting")
      end
    end
  end
end
