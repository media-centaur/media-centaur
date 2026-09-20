defmodule MediaCentaur.TMDB.StoreTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.TMDB.Store.{SeasonRecord, TitleRecord}
  alias MediaCentaur.TmdbStubs

  @etag ~s(W/"v1")

  describe "record_fetched/3" do
    test "stores a title with its payload, etag, fetch time and schedule" do
      payload = TmdbStubs.movie_detail(%{"id" => 550, "release_date" => "2026-07-01"})

      assert {:ok, %TitleRecord{} = record} = Store.record_fetched({550, :movie}, payload, @etag)
      assert record.tmdb_id == 550
      assert record.media_type == :movie
      assert record.etag == @etag
      assert record.payload["title"] == "Sample Movie"
      assert record.changed_at == record.fetched_at
      assert record.settled_at == nil
      assert record.next_check_at == DateTime.add(record.fetched_at, 7, :day)
      assert Store.get({550, :movie}) == record
    end

    test "an identical payload moves the fetch time and nothing else" do
      record = create_title_record(%{tmdb_id: 551, media_type: :movie})
      backdated = backdate(record, :fetched_at, ~U[2026-01-01 00:00:00Z])

      assert {:ok, again} = Store.record_fetched({551, :movie}, record.payload, @etag)
      assert DateTime.after?(again.fetched_at, backdated.fetched_at)
      assert again.changed_at == record.changed_at
      assert again.payload == record.payload
    end

    test "a different payload replaces it and moves changed_at" do
      record = create_title_record(%{tmdb_id: 552, media_type: :movie})
      backdated = backdate(record, :changed_at, ~U[2026-01-01 00:00:00Z])

      new_payload = Map.put(record.payload, "overview", "A revised overview.")
      assert {:ok, again} = Store.record_fetched({552, :movie}, new_payload, ~s(W/"v2"))
      assert again.payload["overview"] == "A revised overview."
      assert again.etag == ~s(W/"v2")
      assert DateTime.after?(again.changed_at, backdated.changed_at)
    end

    test "a nil etag keeps the stored one" do
      create_title_record(%{tmdb_id: 553, media_type: :movie, etag: @etag})
      payload = Store.get({553, :movie}).payload

      assert {:ok, again} = Store.record_fetched({553, :movie}, payload, nil)
      assert again.etag == @etag
    end

    test "the images block is reduced to the logo the app selects" do
      payload =
        TmdbStubs.movie_detail(%{
          "id" => 554,
          "images" => %{
            "logos" => [
              %{"iso_639_1" => "de", "file_path" => "/de.png"},
              %{"iso_639_1" => "en", "file_path" => "/en.png"}
            ],
            "posters" => [%{"file_path" => "/p1.jpg"}, %{"file_path" => "/p2.jpg"}],
            "backdrops" => [%{"file_path" => "/b1.jpg"}]
          }
        })

      assert {:ok, record} = Store.record_fetched({554, :movie}, payload, @etag)

      assert record.payload["images"] == %{
               "logos" => [%{"iso_639_1" => "en", "file_path" => "/en.png"}]
             }

      assert MediaCentaur.TMDB.Mapper.pick_logo_path(record.payload) == "/en.png"
    end

    test "the credits are cut to what the preview re-reads: ten top-billed cast and the directing crew" do
      cast = for order <- 0..14, do: %{"name" => "Actor #{order}", "order" => order}

      movie =
        TmdbStubs.movie_detail(%{
          "id" => 570,
          "credits" => %{
            "cast" => Enum.reverse(cast),
            "crew" => [
              %{"name" => "A. Director", "department" => "Directing", "job" => "Director"},
              %{"name" => "A. Writer", "department" => "Writing", "job" => "Writer"}
            ]
          }
        })

      series =
        TmdbStubs.tv_detail(%{
          "id" => 571,
          "aggregate_credits" => %{"cast" => cast, "crew" => [%{"name" => "A. Producer"}]}
        })

      season =
        TmdbStubs.season_detail(%{
          "season_number" => 1,
          "credits" => %{"cast" => [%{"name" => "A. Actor"}]},
          "episodes" => [
            %{
              "episode_number" => 1,
              "air_date" => "2026-01-01",
              "name" => "Pilot",
              "guest_stars" => [%{"name" => "A. Guest"}],
              "crew" => [%{"name" => "A. Writer"}]
            }
          ]
        })

      {:ok, stored_movie} = Store.record_fetched({570, :movie}, movie, @etag)
      {:ok, stored_series} = Store.record_fetched({571, :tv_series}, series, @etag)
      {:ok, stored_season} = Store.record_season_fetched(571, 1, season, @etag)

      assert Enum.map(stored_movie.payload["credits"]["cast"], & &1["order"]) == Enum.to_list(0..9)
      assert [%{"job" => "Director"}] = stored_movie.payload["credits"]["crew"]
      assert length(stored_series.payload["aggregate_credits"]["cast"]) == 10
      refute Map.has_key?(stored_series.payload["aggregate_credits"], "crew")
      refute Map.has_key?(stored_season.payload, "credits")

      assert [%{"episode_number" => 1, "air_date" => "2026-01-01", "name" => "Pilot"} = episode] =
               stored_season.payload["episodes"]

      refute Map.has_key?(episode, "guest_stars")
      refute Map.has_key?(episode, "crew")
      assert stored_movie.payload["release_date"] == movie["release_date"]
    end

    test "a settled title records when it settled and has no due time" do
      payload = TmdbStubs.movie_detail(%{"id" => 555, "release_date" => "2020-01-01"})

      assert {:ok, record} = Store.record_fetched({555, :movie}, payload, @etag)
      assert record.settled_at == record.fetched_at
      assert record.next_check_at == nil
    end

    test "accepts a numeric string id, as the client's callers pass" do
      payload = TmdbStubs.movie_detail(%{"id" => 556})

      assert {:ok, %TitleRecord{tmdb_id: 556}} =
               Store.record_fetched({"556", :movie}, payload, @etag)
    end

    test "refuses a payload that is not the title's own answer" do
      assert {:error, :payload_mismatch} =
               Store.record_fetched({559, :movie}, %{"results" => []}, @etag)

      assert {:error, :payload_mismatch} =
               Store.record_fetched({559, :movie}, TmdbStubs.movie_detail(%{"id" => 560}), @etag)

      assert {:error, :payload_mismatch} =
               Store.record_season_fetched(
                 559,
                 2,
                 TmdbStubs.season_detail(%{"season_number" => 1}),
                 @etag
               )

      assert Store.get({559, :movie}) == nil
    end

    test "refuses an id that is not a TMDB id" do
      payload = TmdbStubs.movie_detail(%{"id" => 557})

      assert {:error, :invalid_id} = Store.record_fetched({"tt-tried", :movie}, payload, @etag)
      assert {:error, :invalid_id} = Store.record_season_fetched("", 1, payload, @etag)
      assert Store.get({"tt-tried", :movie}) == nil
      assert Store.seasons("") == []
    end

    test "two processes recording the same new title both succeed, and one row results" do
      payload = TmdbStubs.movie_detail(%{"id" => 558})

      results =
        1..2
        |> Task.async_stream(fn _n -> Store.record_fetched({558, :movie}, payload, @etag) end,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert [{:ok, %TitleRecord{}}, {:ok, %TitleRecord{}}] = results
      assert Repo.aggregate(TitleRecord, :count) == 1
    end
  end

  describe "record_season_fetched/4" do
    test "stores the season and reschedules its series from the episode dates" do
      series =
        TmdbStubs.tv_detail(%{
          "id" => 1396,
          "status" => "Returning Series",
          "seasons" => [%{"season_number" => 1, "air_date" => "2020-01-01"}]
        })

      {:ok, before} = Store.record_fetched({1396, :tv_series}, series, @etag)
      assert before.next_event_on == nil

      future = Date.add(Date.utc_today(), 3)

      season =
        TmdbStubs.season_detail(%{
          "season_number" => 1,
          "episodes" => [%{"episode_number" => 1, "air_date" => Date.to_iso8601(future)}]
        })

      assert {:ok, %SeasonRecord{tmdb_id: 1396, season_number: 1, etag: @etag}} =
               Store.record_season_fetched(1396, 1, season, @etag)

      assert length(Store.get_season(1396, 1).payload["episodes"]) == 1
      assert Store.get({1396, :tv_series}).next_event_on == future
    end

    test "a season for a series the store does not hold is stored on its own" do
      season = TmdbStubs.season_detail(%{"season_number" => 2})
      assert {:ok, %SeasonRecord{}} = Store.record_season_fetched(1397, 2, season, nil)
      assert [%SeasonRecord{season_number: 2}] = Store.seasons(1397)
    end
  end

  describe "ensure/2 and ensure_season/3" do
    setup do
      test_pid = self()

      Req.Test.stub(:tmdb, fn conn ->
        send(test_pid, {:tmdb_hit, conn.request_path})

        body =
          cond do
            String.contains?(conn.request_path, "/season/") ->
              TmdbStubs.season_detail(%{"season_number" => 1})

            String.contains?(conn.request_path, "/tv/") ->
              TmdbStubs.tv_detail(%{"id" => 1396})

            true ->
              TmdbStubs.movie_detail(%{"id" => 550})
          end

        conn
        |> Plug.Conn.put_resp_header("etag", ~s(W/"first"))
        |> Req.Test.json(body)
      end)

      :ok
    end

    test "a stored title is returned without a request" do
      record = create_title_record(%{tmdb_id: 550, media_type: :movie})
      assert {:ok, ^record} = Store.ensure({550, :movie})
      refute_receive {:tmdb_hit, _path}
    end

    test "an unknown title is fetched once and stored with TMDB's etag" do
      assert {:ok, %TitleRecord{tmdb_id: 550, etag: ~s(W/"first")}} = Store.ensure({550, :movie})
      assert_receive {:tmdb_hit, "/3/movie/550"}
      assert {:ok, %TitleRecord{}} = Store.ensure({550, :movie})
      refute_receive {:tmdb_hit, _path}
    end

    test "an unknown season is fetched once" do
      assert {:ok, %SeasonRecord{tmdb_id: 1396, season_number: 1}} = Store.ensure_season(1396, 1)
      assert_receive {:tmdb_hit, "/3/tv/1396/season/1"}
      assert {:ok, %SeasonRecord{}} = Store.ensure_season(1396, 1)
      refute_receive {:tmdb_hit, _path}
    end

    test "a TMDB failure is returned, and nothing is stored" do
      Req.Test.stub(:tmdb, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
      assert {:error, _reason} = Store.ensure({999, :movie})
      assert Store.get({999, :movie}) == nil
    end
  end

  describe "check/2" do
    setup do
      MediaCentaur.Topics.subscribe(MediaCentaur.Topics.tmdb_titles())
      :ok
    end

    defp stub_check(test_pid, held_etag, fresh_body) do
      Req.Test.stub(:tmdb, fn conn ->
        validator = Plug.Conn.get_req_header(conn, "if-none-match")
        send(test_pid, {:tmdb_hit, conn.request_path, validator})

        if validator == [held_etag] do
          Plug.Conn.send_resp(conn, 304, "")
        else
          conn
          |> Plug.Conn.put_resp_header("etag", ~s(W/"next"))
          |> Req.Test.json(fresh_body.(conn.request_path))
        end
      end)
    end

    test "an unchanged title moves its fetch time, keeps its rows, publishes nothing" do
      record = create_title_record(%{tmdb_id: 560, media_type: :movie, etag: ~s(W/"held")})
      backdate(record, :fetched_at, ~U[2026-01-01 00:00:00Z])
      stub_check(self(), ~s(W/"held"), fn _path -> %{} end)

      assert {:ok, :unchanged, %TitleRecord{} = after_check} = Store.check({560, :movie})
      assert_receive {:tmdb_hit, "/3/movie/560", [~s(W/"held")]}
      assert DateTime.after?(after_check.fetched_at, ~U[2026-01-01 00:00:00Z])
      assert after_check.changed_at == record.changed_at
      assert after_check.payload == record.payload
      refute_receive {:tmdb_title_changed, _ref}
    end

    test "a 200 carrying an identical payload is unchanged, even within the second it was stored" do
      record = create_title_record(%{tmdb_id: 566, media_type: :movie, etag: ~s(W/"old")})
      stub_check(self(), ~s(W/"other"), fn _path -> record.payload end)

      assert {:ok, :unchanged, %TitleRecord{etag: ~s(W/"next")} = after_check} =
               Store.check({566, :movie})

      assert after_check.changed_at == record.changed_at
      refute_receive {:tmdb_title_changed, _ref}
    end

    test "a changed title replaces the payload and etag and publishes the change" do
      record = create_title_record(%{tmdb_id: 561, media_type: :movie, etag: ~s(W/"old")})
      revised = Map.put(record.payload, "overview", "Revised.")
      stub_check(self(), ~s(W/"held"), fn _path -> revised end)

      assert {:ok, :changed, %TitleRecord{etag: ~s(W/"next")} = after_check} =
               Store.check({561, :movie})

      assert after_check.payload["overview"] == "Revised."
      assert_receive {:tmdb_title_changed, {561, :movie}}
    end

    test "a series check revalidates its open seasons and leaves closed ones alone" do
      series =
        TmdbStubs.tv_detail(%{
          "id" => 562,
          "status" => "Returning Series",
          "seasons" => [
            %{"season_number" => 1, "air_date" => "2020-01-01"},
            %{"season_number" => 2, "air_date" => "2026-01-01"}
          ]
        })

      create_title_record(%{
        tmdb_id: 562,
        media_type: :tv_series,
        payload: series,
        etag: ~s(W/"held")
      })

      closed =
        TmdbStubs.season_detail(%{
          "season_number" => 1,
          "episodes" => [%{"episode_number" => 1, "air_date" => "2020-01-01"}]
        })

      latest =
        TmdbStubs.season_detail(%{
          "season_number" => 2,
          "episodes" => [%{"episode_number" => 1, "air_date" => "2026-01-01"}]
        })

      create_season_record(%{tmdb_id: 562, season_number: 1, payload: closed, etag: ~s(W/"held")})
      create_season_record(%{tmdb_id: 562, season_number: 2, payload: latest, etag: ~s(W/"held")})
      stub_check(self(), ~s(W/"held"), fn _path -> %{} end)

      assert {:ok, :unchanged, _record} = Store.check({562, :tv_series})
      assert_receive {:tmdb_hit, "/3/tv/562", [~s(W/"held")]}
      assert_receive {:tmdb_hit, "/3/tv/562/season/2", [~s(W/"held")]}
      refute_receive {:tmdb_hit, "/3/tv/562/season/1", _validator}
    end

    test "a season that changed publishes the series as changed even when the series did not" do
      series =
        TmdbStubs.tv_detail(%{
          "id" => 563,
          "status" => "Returning Series",
          "seasons" => [%{"season_number" => 1, "air_date" => "2026-01-01"}]
        })

      create_title_record(%{
        tmdb_id: 563,
        media_type: :tv_series,
        payload: series,
        etag: ~s(W/"held")
      })

      create_season_record(%{tmdb_id: 563, season_number: 1, etag: ~s(W/"old")})

      new_season =
        TmdbStubs.season_detail(%{
          "season_number" => 1,
          "episodes" => [%{"episode_number" => 3, "air_date" => "2026-12-01"}]
        })

      stub_check(self(), ~s(W/"held"), fn _path -> new_season end)

      assert {:ok, :changed, %TitleRecord{next_event_on: ~D[2026-12-01]}} =
               Store.check({563, :tv_series})

      assert_receive {:tmdb_title_changed, {563, :tv_series}}
    end

    test "checking a title the store does not hold is first contact" do
      stub_check(self(), ~s(W/"none"), fn _path -> TmdbStubs.movie_detail(%{"id" => 564}) end)
      assert {:ok, :changed, %TitleRecord{tmdb_id: 564}} = Store.check({564, :movie})
      assert_receive {:tmdb_title_changed, {564, :movie}}
    end

    test "a TMDB failure leaves the record as it was" do
      record = create_title_record(%{tmdb_id: 565, media_type: :movie})
      Req.Test.stub(:tmdb, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _reason} = Store.check({565, :movie})
      assert Store.get({565, :movie}) == record
    end
  end

  describe "fetch_full/2 and fetch_full_season/3" do
    setup do
      MediaCentaur.Topics.subscribe(MediaCentaur.Topics.tmdb_titles())
      :ok
    end

    defp full_credits do
      cast =
        for n <- 1..12, do: %{"id" => n, "name" => "Person #{n}", "character" => "C#{n}", "order" => n}

      crew = [
        %{"id" => 90, "name" => "A. Director", "department" => "Directing", "job" => "Director"},
        %{"id" => 91, "name" => "A. Writer", "department" => "Writing", "job" => "Writer"}
      ]

      %{"cast" => cast, "crew" => crew}
    end

    test "an unheld title is fetched, stored trimmed and returned whole" do
      body = TmdbStubs.movie_detail(%{"id" => 570, "credits" => full_credits()})
      stub_check(self(), ~s(W/"none"), fn _path -> body end)

      assert {:ok, payload} = Store.fetch_full({570, :movie})
      assert_receive {:tmdb_hit, "/3/movie/570", []}
      assert length(payload["credits"]["cast"]) == 12
      assert Enum.any?(payload["credits"]["crew"], &(&1["job"] == "Writer"))

      stored = Store.get({570, :movie})
      assert length(stored.payload["credits"]["cast"]) == 10
      assert Enum.map(stored.payload["credits"]["crew"], & &1["job"]) == ["Director"]
      assert stored.etag == ~s(W/"next")
      assert_receive {:tmdb_title_changed, {570, :movie}}
    end

    test "a held title is fetched again without a validator; a changed answer replaces the record and announces it" do
      record = create_title_record(%{tmdb_id: 571, media_type: :movie, etag: ~s(W/"held")})
      revised = Map.put(record.payload, "overview", "Revised.")
      stub_check(self(), ~s(W/"held"), fn _path -> revised end)

      assert {:ok, %{"overview" => "Revised."}} = Store.fetch_full({571, :movie})
      assert_receive {:tmdb_hit, "/3/movie/571", []}
      assert Store.get({571, :movie}).payload["overview"] == "Revised."
      assert_receive {:tmdb_title_changed, {571, :movie}}
    end

    test "an identical answer moves the fetch time and announces nothing" do
      record = create_title_record(%{tmdb_id: 572, media_type: :movie})
      backdate(record, :fetched_at, ~U[2026-01-01 00:00:00Z])
      stub_check(self(), ~s(W/"none"), fn _path -> record.payload end)

      assert {:ok, _payload} = Store.fetch_full({572, :movie})
      assert DateTime.after?(Store.get({572, :movie}).fetched_at, ~U[2026-01-01 00:00:00Z])
      refute_receive {:tmdb_title_changed, _ref}
    end

    test "a season is returned with its credits and guest stars, which the record does not keep; a change announces the series" do
      create_title_record(%{tmdb_id: 573, media_type: :tv_series})

      season =
        TmdbStubs.season_detail(%{
          "season_number" => 2,
          "credits" => %{"cast" => [%{"id" => 7, "name" => "Regular", "order" => 0}]},
          "episodes" => [
            %{
              "episode_number" => 1,
              "name" => "One",
              "air_date" => "2020-01-01",
              "guest_stars" => [%{"id" => 8, "name" => "Guest"}]
            }
          ]
        })

      stub_check(self(), ~s(W/"none"), fn _path -> season end)

      assert {:ok, payload} = Store.fetch_full_season("573", 2)
      assert_receive {:tmdb_hit, "/3/tv/573/season/2", []}
      assert [%{"id" => 7}] = get_in(payload, ["credits", "cast"])
      assert [%{"id" => 8}] = hd(payload["episodes"])["guest_stars"]

      stored = Store.get_season(573, 2)
      refute Map.has_key?(stored.payload, "credits")
      refute Map.has_key?(hd(stored.payload["episodes"]), "guest_stars")
      assert_receive {:tmdb_title_changed, {573, :tv_series}}
    end

    test "a TMDB failure is returned and the record left as it was" do
      record = create_title_record(%{tmdb_id: 574, media_type: :movie})
      TmdbStubs.stub_tmdb_error("/movie/574", 500)

      assert {:error, _reason} = Store.fetch_full({574, :movie})
      assert Store.get({574, :movie}).payload == record.payload
      refute_receive {:tmdb_title_changed, _ref}
    end
  end

  describe "sweep/0" do
    test "a referenced title survives however old; an unreferenced one goes with its seasons after seven days; a fresh one stays" do
      create_tracking_item(%{tmdb_id: 580, media_type: :tv_series})
      backdate(Store.get({580, :tv_series}), :fetched_at, ~U[2026-01-01 00:00:00Z])

      old = create_title_record(%{tmdb_id: 581, media_type: :tv_series})
      backdate(old, :fetched_at, ~U[2026-01-01 00:00:00Z])
      create_season_record(%{tmdb_id: 581, season_number: 1})

      create_title_record(%{tmdb_id: 582, media_type: :movie})

      assert Store.sweep() == 1
      assert %TitleRecord{} = Store.get({580, :tv_series})
      assert Store.get({581, :tv_series}) == nil
      assert Store.seasons(581) == []
      assert %TitleRecord{} = Store.get({582, :movie})
    end

    test "a movie and a series sharing an id are swept apart: the held series keeps its seasons" do
      create_tracking_item(%{tmdb_id: 583, media_type: :tv_series})
      create_season_record(%{tmdb_id: 583, season_number: 1})
      movie = create_title_record(%{tmdb_id: 583, media_type: :movie})
      backdate(movie, :fetched_at, ~U[2026-01-01 00:00:00Z])

      assert Store.sweep() == 1
      assert Store.get({583, :movie}) == nil
      assert %TitleRecord{} = Store.get({583, :tv_series})
      assert [%{season_number: 1}] = Store.seasons(583)
    end

    test "nothing to remove is zero" do
      assert Store.sweep() == 0
    end
  end

  describe "snapshot/1 and snapshots/1" do
    test "a stored title renders as the app's title snapshot" do
      create_title_record(%{tmdb_id: 630, media_type: :movie, name: "Sample Movie"})
      create_title_record(%{tmdb_id: 631, media_type: :tv_series, name: "Sample Show"})

      assert %MediaCentaur.TMDB.Title{tmdb_id: 630, media_type: :movie, name: "Sample Movie"} =
               Store.snapshot({630, :movie})

      assert %{{630, :movie} => %{name: "Sample Movie"}, {631, :tv_series} => %{name: "Sample Show"}} =
               Store.snapshots([{630, :movie}, {631, :tv_series}, {632, :movie}])

      assert Store.snapshot({632, :movie}) == nil
    end
  end

  describe "first contact announces the title" do
    test "ensure/2 publishes {:tmdb_title_changed, ref} when it creates the record, not when it finds it" do
      Store.subscribe()

      Req.Test.stub(:tmdb, fn conn ->
        Req.Test.json(conn, TmdbStubs.movie_detail(%{"id" => 640}))
      end)

      assert {:ok, _record} = Store.ensure({640, :movie})
      assert_receive {:tmdb_title_changed, {640, :movie}}

      assert {:ok, _record} = Store.ensure({640, :movie})
      refute_receive {:tmdb_title_changed, _ref}
    end
  end

  describe "get_many/1 and seasons_for/1" do
    test "get_many/1 returns the stored records by ref, missing refs absent" do
      a = create_title_record(%{tmdb_id: 610, media_type: :movie})
      b = create_title_record(%{tmdb_id: 611, media_type: :tv_series})

      found = Store.get_many([{610, :movie}, {611, :tv_series}, {612, :movie}])
      assert %{{610, :movie} => ^a, {611, :tv_series} => ^b} = found
      assert map_size(found) == 2
    end

    test "seasons_for/1 groups the stored seasons of several series" do
      create_season_record(%{tmdb_id: 620, season_number: 2})
      create_season_record(%{tmdb_id: 620, season_number: 1})
      create_season_record(%{tmdb_id: 621, season_number: 1})

      seasons = Store.seasons_for([620, 621, 622])

      assert %{620 => [%SeasonRecord{season_number: 1}, %SeasonRecord{season_number: 2}]} = seasons
      assert %{621 => [_one]} = seasons
      assert map_size(seasons) == 2
    end
  end

  describe "due/1" do
    test "returns unsettled titles whose check time has passed, oldest first" do
      now = DateTime.utc_now(:second)
      overdue = create_title_record(%{tmdb_id: 601})
      later = create_title_record(%{tmdb_id: 602})

      _settled =
        create_title_record(%{
          tmdb_id: 603,
          payload: TmdbStubs.movie_detail(%{"id" => 603, "release_date" => "2020-01-01"})
        })

      backdate(overdue, :next_check_at, DateTime.add(now, -2, :day))
      backdate(later, :next_check_at, DateTime.add(now, -1, :hour))
      _future = create_title_record(%{tmdb_id: 604})

      assert [%{tmdb_id: 601}, %{tmdb_id: 602}] = Store.due(now)
    end
  end
end
