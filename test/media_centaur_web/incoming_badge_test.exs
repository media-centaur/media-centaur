defmodule MediaCentaurWeb.IncomingBadgeTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Acquisition.Plans

  @incoming_pill ~s{aside a[data-tip="Incoming"] [data-component="follow-up-pill"]}

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    :ok
  end

  test "no pill when nothing awaits review", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/history")
    refute has_element?(view, @incoming_pill)
  end

  test "a ready draft shows the count; discarding it clears the pill", %{conn: conn} do
    {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})

    {:ok, view, _html} = live(conn, ~p"/history")
    assert has_element?(view, @incoming_pill, "1")

    {:ok, plan} = Plans.fetch(plan.id)
    {:ok, _discarded} = Plans.discard(plan)
    # No Worker runs under ExUnit; deliver the derived broadcast by hand.
    :ok = MediaCentaurWeb.ShellBadges.refresh_cache()

    refute has_element?(view, @incoming_pill)
  end
end
