defmodule MediaCentaur.Acquisition.TitleStatesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.{Plans, TitleStates}

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

  test "empty input, empty output" do
    assert TitleStates.for_refs([]) == %{}
  end

  test "a ready draft is needs_review, an in-flight pursuit is downloading, nothing is absent" do
    {:ok, _plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})
    create_pursuit(%{tmdb_id: "778", tmdb_type: "movie", title: "Sample Movie B"})

    assert TitleStates.for_refs([{777, :movie}, {778, :movie}, {779, :movie}, {42, :tv_series}]) == %{
             {777, :movie} => :needs_review,
             {778, :movie} => :downloading
           }
  end

  test "a pursuit outranks a draft for the same title" do
    {:ok, _plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})
    create_pursuit(%{tmdb_id: "777", tmdb_type: "movie", title: "Sample Movie"})

    assert TitleStates.for_refs([{777, :movie}]) == %{{777, :movie} => :downloading}
  end

  test "a planning draft is planning" do
    {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})
    # Inline Oban solved it to ready already; re-read before forcing it back.
    {:ok, plan} = Plans.fetch(plan.id)
    force_attrs(plan, status: "planning")

    assert TitleStates.for_refs([{777, :movie}]) == %{{777, :movie} => :planning}
  end
end
