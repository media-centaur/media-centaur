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
