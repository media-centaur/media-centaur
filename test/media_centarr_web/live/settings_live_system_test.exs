defmodule MediaCentarrWeb.SettingsLiveSystemTest do
  @moduledoc """
  Integration tests for the system content on Settings > Overview — version
  display, the auto-check-on-landing flow, the 5-minute cache, and the
  manual "Check for updates" button.
  """

  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.UpdateChecker

  setup do
    # Install a stub GitHub Releases client into the same persistent_term
    # key UpdateChecker uses, so checks issued by the LiveView hit our stub.
    Req.Test.stub(:github_releases_live, fn conn ->
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

    client = Req.new(plug: {Req.Test, :github_releases_live}, retry: false)
    :persistent_term.put({UpdateChecker, :client}, client)

    # The cache is global (persistent_term) — reset it so each test starts
    # from a known empty state and can't be polluted by prior runs.
    UpdateChecker.clear_cache()

    on_exit(fn ->
      :persistent_term.erase({UpdateChecker, :client})
      UpdateChecker.clear_cache()
    end)

    :ok
  end

  test "overview section mounts and renders the current version", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings?section=overview")
    assert html =~ MediaCentarr.Version.current_version()
  end

  test "landing on overview auto-triggers an update check when cache is empty",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?section=overview")

    # Allow the async task to run under Req.Test.
    Req.Test.allow(:github_releases_live, self(), view.pid)

    assert_eventually(fn -> render(view) =~ "v99.0.0" end)
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

    {:ok, view, _html} = live(conn, ~p"/settings?section=overview")

    # Give any would-be auto-check a window to run; none should.
    Process.sleep(100)

    html = render(view)
    assert html =~ "v55.0.0"
    refute html =~ "v99.0.0"
  end

  test "landing on overview with a cached error reuses the error result", %{conn: conn} do
    :ok = UpdateChecker.cache_result({:error, :not_found})

    {:ok, view, _html} = live(conn, ~p"/settings?section=overview")
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

    {:ok, view, _html} = live(conn, ~p"/settings?section=overview")
    Process.sleep(100)
    assert render(view) =~ "v55.0.0"

    Req.Test.allow(:github_releases_live, self(), view.pid)
    render_click(view, "check_updates", %{})

    assert_eventually(fn -> render(view) =~ "v99.0.0" end)
  end

  test "check results are written back to the cache", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?section=overview")
    Req.Test.allow(:github_releases_live, self(), view.pid)

    assert_eventually(fn -> render(view) =~ "v99.0.0" end)

    assert {:fresh, {:ok, %{version: "99.0.0"}}} = UpdateChecker.cached_latest_release()
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
