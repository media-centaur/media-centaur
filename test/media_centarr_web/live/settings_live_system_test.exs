defmodule MediaCentarrWeb.SettingsLiveSystemTest do
  @moduledoc """
  Integration tests for the Settings > System section — version display and
  the "Check for updates" async flow.
  """

  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.UpdateChecker

  setup do
    # Install a stub GitHub Releases client into the same persistent_term
    # key UpdateChecker uses, so clicking "Check for updates" in the
    # LiveView hits our stub.
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

    on_exit(fn ->
      :persistent_term.erase({UpdateChecker, :client})
    end)

    :ok
  end

  test "system section mounts and renders the current version", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings?section=system")
    assert html =~ MediaCentarr.Version.current_version()
  end

  test "clicking 'Check for updates' triggers the async check and renders result",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?section=system")

    # Before the click: idle status (no latest release info).
    refute render(view) =~ "v99.0.0"

    # Allow the async task to run under Req.Test.
    Req.Test.allow(:github_releases_live, self(), view.pid)

    render_click(view, "check_updates", %{})

    # Wait for the async message to arrive at the LiveView.
    assert_eventually(fn -> render(view) =~ "v99.0.0" end)
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
