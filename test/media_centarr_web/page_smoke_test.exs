defmodule MediaCentarrWeb.PageSmokeTest do
  @moduledoc """
  Visits every top-level LiveView route and asserts it mounts and renders
  without crashing. This is the cheapest possible safety net for the kind
  of bug where adding a new assign or template variable trips a
  `KeyError` only on a specific page.

  Each route gets one test. If a page needs additional setup to mount
  (Prowlarr config, DB fixtures, etc.) the setup happens in this file so
  the smoke test stays isolated from the per-page test files.
  """

  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Config

  for {path, label} <- [
        {"/", "library"},
        {"/status", "status"},
        {"/settings", "settings"},
        {"/review", "review"},
        {"/console", "console"},
        {"/history", "watch history"}
      ] do
    test "#{label} (#{path}) renders without crashing", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, unquote(path))
      assert is_binary(html)
    end
  end

  describe "/download" do
    setup do
      original = :persistent_term.get({Config, :config}, %{})

      :persistent_term.put(
        {Config, :config},
        Map.merge(original, %{
          prowlarr_url: "http://prowlarr.test",
          prowlarr_api_key: "test-key"
        })
      )

      on_exit(fn -> :persistent_term.put({Config, :config}, original) end)

      :ok
    end

    test "renders without crashing (Prowlarr configured)", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, "/download")
      assert is_binary(html)
    end
  end
end
