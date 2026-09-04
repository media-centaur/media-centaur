defmodule MediaCentaurWeb.LibraryScanAsyncTest do
  @moduledoc """
  The "Scan" control on both pages that carry it. The scan runs off the
  socket process so the page keeps rendering, and its result has to come
  back to the view that started it — an owned `start_async` (ADR-049,
  MC0019), not a task hung off the global supervisor.
  """
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Settings → Library" do
    test "scan reports its result as a flash and clears the scanning flag", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/settings?section=library")
      _ = render_async(view)

      render_click(view, "scan")

      assert render_async(view) =~ "Scan complete"
      refute view |> element("[phx-click='cancel_scan']") |> has_element?()
    end
  end

  describe "Library page" do
    test "scan clears the scanning flag when the async work returns", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/library")
      _ = render_async(view)

      render_click(view, "scan")
      _ = render_async(view)

      refute render(view) =~ "Scanning"
    end
  end
end
