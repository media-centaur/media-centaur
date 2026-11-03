defmodule MediaCentaur.TMDB.SeriesStatusTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.TMDB.SeriesStatus
  alias MediaCentaur.TmdbStubs

  defp series(tmdb_id, status) do
    payload = TmdbStubs.tv_detail(%{"id" => tmdb_id, "status" => status, "seasons" => []})
    create_title_record(%{tmdb_id: tmdb_id, media_type: :tv_series, payload: payload})
    {tmdb_id, :tv_series}
  end

  describe "for_refs/1" do
    test "reads TMDB's status word for every stored series; unknown words, movies and absent refs" do
      returning = series(1, "Returning Series")
      ended = series(2, "Ended")
      odd = series(3, "Pilot")
      movie = create_title_record(%{tmdb_id: 4, media_type: :movie})

      assert SeriesStatus.for_refs([returning, ended, odd, {movie.tmdb_id, :movie}, {5, :tv_series}]) ==
               %{returning => :returning, ended => :ended, odd => :unknown}
    end

    test "read/1 is one payload's status, nil status unknown" do
      assert SeriesStatus.read(%{"status" => "Canceled"}) == :canceled
      assert SeriesStatus.read(%{}) == :unknown
    end
  end
end
