defmodule MediaCentaur.TMDB.CheckJobTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.{CheckJob, Store}
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.mark_ready!()
    test_pid = self()

    Req.Test.stub(:tmdb, fn conn ->
      validator = Plug.Conn.get_req_header(conn, "if-none-match")
      send(test_pid, {:tmdb_hit, conn.request_path, validator})

      if validator == [~s(W/"held")] do
        Plug.Conn.send_resp(conn, 304, "")
      else
        body =
          if String.contains?(conn.request_path, "/tv/"),
            do:
              TmdbStubs.tv_detail(%{
                "id" => 800,
                "status" => "Returning Series",
                "seasons" => []
              }),
            else: TmdbStubs.movie_detail(%{"id" => 801, "release_date" => "2026-12-25"})

        conn |> Plug.Conn.put_resp_header("etag", ~s(W/"held")) |> Req.Test.json(body)
      end
    end)

    :ok
  end

  defp perform do
    Oban.Testing.perform_job(CheckJob, %{}, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite)
  end

  test "a referenced title the store lacks is first-contacted" do
    create_tracking_item(%{tmdb_id: 801, media_type: :movie, stored: false})

    assert :ok = perform()
    assert_receive {:tmdb_hit, "/3/movie/801", []}
    assert %Store.TitleRecord{etag: ~s(W/"held")} = Store.get({801, :movie})
  end

  test "a due referenced title is checked with its etag; an undue one is not" do
    create_tracking_item(%{tmdb_id: 800, media_type: :tv_series, etag: ~s(W/"held")})
    create_tracking_item(%{tmdb_id: 802, media_type: :movie})
    backdate(Store.get({800, :tv_series}), :next_check_at, ~U[2026-01-01 00:00:00Z])

    assert :ok = perform()
    assert_receive {:tmdb_hit, "/3/tv/800", [~s(W/"held")]}
    refute_receive {:tmdb_hit, "/3/movie/802", _validator}

    assert DateTime.after?(Store.get({800, :tv_series}).fetched_at, ~U[2026-01-01 00:00:00Z])
  end

  test "a due title nothing references is left alone" do
    record = create_title_record(%{tmdb_id: 803, media_type: :movie})
    backdate(record, :next_check_at, ~U[2026-01-01 00:00:00Z])

    assert :ok = perform()
    refute_receive {:tmdb_hit, _path, _validator}
  end

  test "held while TMDB is down: no request, nothing lost" do
    create_tracking_item(%{tmdb_id: 801, media_type: :movie, stored: false})
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

    assert :ok = perform()
    refute_receive {:tmdb_hit, _path, _validator}
    assert Store.get({801, :movie}) == nil
  end
end
