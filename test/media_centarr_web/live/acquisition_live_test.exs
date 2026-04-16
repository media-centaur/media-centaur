defmodule MediaCentarrWeb.AcquisitionLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Acquisition.Prowlarr

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    config = :persistent_term.get({MediaCentarr.Config, :config})

    :persistent_term.put(
      {MediaCentarr.Config, :config},
      Map.merge(config, %{prowlarr_url: "http://prowlarr.test", prowlarr_api_key: "test-key"})
    )

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentarr.Config, :config}, config)
    end)

    :ok
  end

  describe "mount" do
    test "redirects to library when Prowlarr is not configured", %{conn: conn} do
      config = :persistent_term.get({MediaCentarr.Config, :config})

      :persistent_term.put(
        {MediaCentarr.Config, :config},
        Map.merge(config, %{prowlarr_url: nil, prowlarr_api_key: nil})
      )

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/download")
    end

    test "renders the download page when Prowlarr is configured", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/download")

      assert html =~ "Download"
      assert html =~ "data-page-behavior=\"download\""
      assert html =~ "data-nav-default-zone=\"download\""
    end
  end

  describe "query_change" do
    test "updates expansion preview for valid syntax", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      html =
        view
        |> form("form[phx-change='query_change']", query: "The Pitt S02E{00-09}")
        |> render_change()

      assert html =~ "10 queries in parallel"
    end

    test "shows error for invalid brace syntax", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      html =
        view
        |> form("form[phx-change='query_change']", query: "foo {a-}")
        |> render_change()

      assert html =~ "Invalid brace syntax"
    end
  end

  describe "submit_search and grab_selected" do
    test "renders results, lets user select, and submits a grab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      # Allow the LiveView (and tasks it spawns via $callers) to use the stub.
      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [
              %{
                "title" => "Movie.A.2024.2160p.BluRay",
                "guid" => "guid-a",
                "indexerId" => 1,
                "seeders" => 50,
                "indexer" => "indexer-a"
              }
            ])

          "/api/v1/release" ->
            Req.Test.json(conn, %{"approved" => true})

          "/api/v1/queue" ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> form("form[phx-change='query_change']", query: "Movie A")
      |> render_submit()

      html = wait_until(view, &(&1 =~ "Movie.A.2024.2160p.BluRay"))
      # Default selection should be applied — Grab button shows count of 1
      assert html =~ "Grab 1 selected"

      # Submit the grab
      view
      |> element("button[phx-click='grab_selected']")
      |> render_click()

      html = wait_until(view, &(&1 =~ "1 grab(s) submitted"))
      assert html =~ "1 grab(s) submitted"
    end
  end

  # Polls render(view) until `predicate.(html)` returns true or the timeout
  # elapses. Used to wait for async Task.Supervisor work to deliver
  # {:search_result, _, _} / grab completion messages back to the LiveView.
  defp wait_until(view, predicate, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(view, predicate, deadline)
  end

  defp do_wait_until(view, predicate, deadline) do
    html = render(view)

    cond do
      predicate.(html) ->
        html

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("wait_until timed out")

      true ->
        Process.sleep(10)
        do_wait_until(view, predicate, deadline)
    end
  end
end
