defmodule MediaCentaur.TMDB.ReleaseStagesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.TMDB.ReleaseStages
  alias MediaCentaur.TmdbStubs

  @today ~D[2026-11-01]

  defp movie(tmdb_id, typed, primary \\ nil) do
    dates = for {type, date} <- typed, do: %{"type" => type, "release_date" => "#{date}T00:00:00.000Z"}

    payload =
      TmdbStubs.movie_detail(%{
        "id" => tmdb_id,
        "release_date" => primary,
        "release_dates" => %{"results" => [%{"iso_3166_1" => "US", "release_dates" => dates}]}
      })

    create_title_record(%{tmdb_id: tmdb_id, media_type: :movie, payload: payload})
    {tmdb_id, :movie}
  end

  defp series(tmdb_id, first_air_date) do
    payload =
      TmdbStubs.tv_detail(%{"id" => tmdb_id, "first_air_date" => first_air_date, "seasons" => []})

    create_title_record(%{tmdb_id: tmdb_id, media_type: :tv_series, payload: payload})
    {tmdb_id, :tv_series}
  end

  test "a movie's stage and the date it rests on" do
    home = movie(1, [{3, "2026-09-01"}, {4, "2026-10-20"}])
    theatrical = movie(2, [{3, "2026-10-10"}])
    coming = movie(3, [{3, "2026-12-25"}, {4, "2027-02-01"}])
    unknown = movie(4, [])

    assert %{
             ^home => %{stage: :home, date: ~D[2026-10-20]},
             ^theatrical => %{stage: :theatrical, date: ~D[2026-10-10]},
             ^coming => %{stage: :unreleased, date: ~D[2026-12-25]},
             ^unknown => %{stage: :unknown, date: nil}
           } = ReleaseStages.for_refs([home, theatrical, coming, unknown], @today)
  end

  test "a movie with only a primary date ahead is coming up on that date" do
    coming = movie(5, [], "2027-03-03")

    assert %{^coming => %{stage: :unreleased, date: ~D[2027-03-03]}} =
             ReleaseStages.for_refs([coming], @today)
  end

  test "a series is home once its first episode aired, coming up before, unknown without a date" do
    aired = series(10, "2026-10-01")
    ahead = series(11, "2027-01-15")
    undated = series(12, nil)

    assert %{
             ^aired => %{stage: :home, date: ~D[2026-10-01]},
             ^ahead => %{stage: :unreleased, date: ~D[2027-01-15]},
             ^undated => %{stage: :unknown, date: nil}
           } = ReleaseStages.for_refs([aired, ahead, undated], @today)
  end

  test "a ref the store lacks is absent" do
    assert ReleaseStages.for_refs([{999, :movie}], @today) == %{}
  end
end
