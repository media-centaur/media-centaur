defmodule MediaCentaurWeb.Live.PlanHostTest do
  @moduledoc """
  The plan modal is a tenant of the page that opened it (`Live.PlanHost`,
  `campaigns/adaptive-layout.md` M9): on Library — a page that is not
  Downloads — the picker opens from `?plan=…`, Cancel closes it onto the
  page, a manual plan patches to the page's own board address, and a
  started download ends by the page's own rule, closing and staying.
  Downloads' own walk of the same stages lives in `downloads_live_test`.
  """
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import Phoenix.LiveViewTest

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.TmdbStubs

  setup {TmdbStubs, :setup_artwork_cache}

  defp stub_series do
    TmdbStubs.setup_tmdb_client()

    TmdbStubs.stub_routes([
      {"/tv/246810/season/1",
       TmdbStubs.season_detail(%{
         "season_number" => 1,
         "episodes" => [
           %{"episode_number" => 1, "name" => "Pilot", "air_date" => "2020-01-01"},
           %{"episode_number" => 2, "name" => "Second", "air_date" => "2020-01-08"}
         ]
       })},
      {"/tv/246810",
       TmdbStubs.tv_detail(%{
         "id" => 246_810,
         "name" => "Sample Show",
         "seasons" => [%{"season_number" => 1, "episode_count" => 2}]
       })}
    ])
  end

  defp plan_query("/library?" <> query), do: URI.decode_query(query)

  describe "the plan modal on Library" do
    test "the picker opens from the page's own address and Cancel closes onto the page", %{conn: conn} do
      stub_series()

      {:ok, view, _html} = live_async!(conn, ~p"/library?plan=new&tmdb_id=246810&tmdb_type=tv")

      html = render_async(view, 2_000)
      assert html =~ "Sample Show"
      assert has_element?(view, "#plan-modal[data-nav-overlay='plan']")
      assert html =~ "Download 2 episodes"

      view |> element("#plan-modal button[phx-click='close_plan']") |> render_click()

      assert_patch(view, "/library")
      refute has_element?(view, "#plan-modal[data-nav-overlay='plan']")
    end

    test "a manual plan patches to the page's own board address", %{conn: conn} do
      stub_series()

      {:ok, view, _html} =
        live_async!(conn, ~p"/library?plan=new&tmdb_id=246810&tmdb_type=tv&mode=manually_select_release")

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      path = assert_patch(view)
      assert [plan] = Plans.list_drafts()
      assert plan_query(path) == %{"plan" => plan.id}
      assert render_async(view, 2_000) =~ "Sample Show"
      assert has_element?(view, "#plan-modal[data-nav-overlay='plan']")
    end

    test "a download that starts ends by the page's own rule: the modal closes, the page stays", %{
      conn: conn
    } do
      stub_series()

      {:ok, view, _html} =
        live_async!(
          conn,
          ~p"/library?plan=new&tmdb_id=246810&tmdb_type=tv&mode=auto_select_best_release"
        )

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      assert_patch(view, "/library")
      assert_push_event(view, "nav-remember", %{path: "/downloads", url: "/downloads"})
      refute has_element?(view, "#plan-modal[data-nav-overlay='plan']")
      assert render(view) =~ "Finding a release for Sample Show"
      await_supervised_tasks()

      assert [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
    end
  end
end
