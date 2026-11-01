defmodule MediaCentaur.NewReleasesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.NewReleases
  alias MediaCentaur.NewReleases.Member
  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.TmdbStubs

  describe "replace/1 and the reads" do
    test "the membership is the entries in order, with their digital dates" do
      :ok =
        NewReleases.replace([
          %{tmdb_id: 301, digital_date: ~D[2026-10-30]},
          %{tmdb_id: 302, digital_date: ~D[2026-10-24]}
        ])

      assert [
               %Member{tmdb_id: 301, position: 0, digital_date: ~D[2026-10-30]},
               %Member{tmdb_id: 302, position: 1, digital_date: ~D[2026-10-24]}
             ] = NewReleases.members()

      assert NewReleases.refs() == [{301, :movie}, {302, :movie}]
    end

    test "a second replace is the whole shelf, not an addition" do
      :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])
      :ok = NewReleases.replace([%{tmdb_id: 303, digital_date: ~D[2026-10-31]}])

      assert NewReleases.refs() == [{303, :movie}]
    end

    test "a duplicate id keeps its first position" do
      :ok =
        NewReleases.replace([
          %{tmdb_id: 301, digital_date: ~D[2026-10-30]},
          %{tmdb_id: 302, digital_date: ~D[2026-10-24]},
          %{tmdb_id: 301, digital_date: ~D[2026-10-30]}
        ])

      assert NewReleases.refs() == [{301, :movie}, {302, :movie}]
    end

    test "an empty list empties the shelf" do
      :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])
      :ok = NewReleases.replace([])

      assert NewReleases.members() == []
    end

    test "every replace is announced on the shelf's topic" do
      :ok = NewReleases.subscribe()
      :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])

      assert_receive {:new_releases_changed}
    end
  end

  describe "refresh/1" do
    setup context do
      TmdbStubs.mark_ready!()
      TmdbStubs.setup_artwork_cache(context)
      test_pid = self()

      Req.Test.stub(:tmdb, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        send(test_pid, {:tmdb_hit, conn.request_path, conn.query_params})

        cond do
          conn.request_path == "/3/discover/movie" and conn.query_params["page"] == "1" ->
            Req.Test.json(conn, %{
              "total_pages" => 2,
              "results" => [
                %{"id" => 901, "release_date" => "2026-10-30", "title" => "Movie A"},
                %{"id" => 902, "release_date" => "2026-10-28", "title" => "Movie B"},
                %{"id" => 903, "release_date" => nil, "title" => "Undated"}
              ]
            })

          conn.request_path == "/3/discover/movie" ->
            Req.Test.json(conn, %{
              "total_pages" => 2,
              "results" => [%{"id" => 904, "release_date" => "2026-10-20", "title" => "Movie C"}]
            })

          true ->
            "/3/movie/" <> id = conn.request_path
            Req.Test.json(conn, TmdbStubs.movie_detail(%{"id" => String.to_integer(id)}))
        end
      end)

      :ok
    end

    test "the membership is the discover rows in order, dated by the row, and each member is stored" do
      assert {:ok, 3} = NewReleases.refresh(~D[2026-11-01])

      assert [
               %Member{tmdb_id: 901, digital_date: ~D[2026-10-30]},
               %Member{tmdb_id: 902, digital_date: ~D[2026-10-28]},
               %Member{tmdb_id: 904, digital_date: ~D[2026-10-20]}
             ] = NewReleases.members()

      assert_receive {:tmdb_hit, "/3/discover/movie", %{"page" => "1", "region" => "US"} = params}
      assert params["release_date.gte"] == "2026-10-18"
      assert params["release_date.lte"] == "2026-11-01"
      assert params["vote_count.gte"] == "20"
      assert_receive {:tmdb_hit, "/3/discover/movie", %{"page" => "2"}}

      for id <- [901, 902, 904] do
        assert_receive {:tmdb_hit, "/3/movie/" <> _, _params}
        assert %Store.TitleRecord{} = Store.get({id, :movie})
      end

      refute_receive {:tmdb_hit, "/3/movie/903", _params}
    end

    test "a failed discover request leaves the membership as it was" do
      :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])
      Req.Test.stub(:tmdb, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      assert {:error, {:http_error, 500, _body}} = NewReleases.refresh(~D[2026-11-01])
      assert NewReleases.refs() == [{301, :movie}]
    end
  end
end
