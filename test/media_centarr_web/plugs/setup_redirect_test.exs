defmodule MediaCentarrWeb.Plugs.SetupRedirectTest do
  @moduledoc """
  Tests the first-run gate plug that redirects `/`, `/library`, `/home`
  to `/setup` while `setup_wizard_dismissed = false`.
  """

  use MediaCentarrWeb.ConnCase, async: false

  alias MediaCentarr.Config
  alias MediaCentarrWeb.Plugs.SetupRedirect

  setup do
    original = :persistent_term.get({Config, :config})

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original)
    end)

    :ok
  end

  defp set_dismissed(value) do
    config = :persistent_term.get({Config, :config})
    :persistent_term.put({Config, :config}, Map.put(config, :setup_wizard_dismissed, value))
  end

  describe "call/2 — wizard not dismissed" do
    setup do
      set_dismissed(false)
      :ok
    end

    test "redirects '/' to '/setup'", %{conn: conn} do
      conn = SetupRedirect.call(%{conn | request_path: "/"}, [])

      assert conn.halted
      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/setup"]
    end

    test "redirects '/library' to '/setup'", %{conn: conn} do
      conn = SetupRedirect.call(%{conn | request_path: "/library"}, [])
      assert conn.halted
      assert Plug.Conn.get_resp_header(conn, "location") == ["/setup"]
    end

    test "does NOT redirect '/setup' itself (would loop)", %{conn: conn} do
      conn = SetupRedirect.call(%{conn | request_path: "/setup"}, [])
      refute conn.halted
    end

    test "does NOT redirect '/settings'", %{conn: conn} do
      conn = SetupRedirect.call(%{conn | request_path: "/settings"}, [])
      refute conn.halted
    end

    test "does NOT redirect '/console' or other non-redirectable paths", %{conn: conn} do
      conn = SetupRedirect.call(%{conn | request_path: "/console"}, [])
      refute conn.halted
    end

    test "does NOT redirect storybook paths", %{conn: conn} do
      conn = SetupRedirect.call(%{conn | request_path: "/storybook/setup/binary_step"}, [])
      refute conn.halted
    end
  end

  describe "call/2 — wizard dismissed" do
    setup do
      set_dismissed(true)
      :ok
    end

    test "does NOT redirect '/' when dismissed", %{conn: conn} do
      conn = SetupRedirect.call(%{conn | request_path: "/"}, [])
      refute conn.halted
    end

    test "does NOT redirect '/library' when dismissed", %{conn: conn} do
      conn = SetupRedirect.call(%{conn | request_path: "/library"}, [])
      refute conn.halted
    end
  end

  describe "call/2 — key absent from persistent_term" do
    test "redirects (treats absent key as 'not dismissed')", %{conn: conn} do
      # Simulates a dev iex whose :persistent_term predates this key.
      stripped = Map.delete(:persistent_term.get({Config, :config}), :setup_wizard_dismissed)

      :persistent_term.put({Config, :config}, stripped)

      conn = SetupRedirect.call(%{conn | request_path: "/"}, [])

      assert conn.halted
      assert Plug.Conn.get_resp_header(conn, "location") == ["/setup"]
    end
  end
end
