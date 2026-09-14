defmodule MediaCentaur.TMDB.ReleaseWindowTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TMDB.ReleaseWindow

  @today ~D[2026-09-14]

  defp payload(us_dates, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 246_813,
        "title" => "Sample Movie",
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "US",
              "release_dates" =>
                Enum.map(us_dates, fn {type, date} ->
                  %{"type" => type, "release_date" => "#{date}T00:00:00.000Z"}
                end)
            }
          ]
        }
      },
      overrides
    )
  end

  describe "stages" do
    test "a home release that has passed is :home" do
      window = ReleaseWindow.from_payload(payload([{3, "2026-06-05"}, {4, "2026-08-01"}]), @today)

      assert window.stage == :home
      assert window.theatrical == ~D[2026-06-05]
      assert window.digital == ~D[2026-08-01]
      assert window.physical == nil
    end

    test "a disc release that has passed is :home too" do
      window = ReleaseWindow.from_payload(payload([{3, "2026-06-05"}, {5, "2026-09-01"}]), @today)

      assert window.stage == :home
      assert window.physical == ~D[2026-09-01]
    end

    test "every date ahead is :unreleased" do
      window = ReleaseWindow.from_payload(payload([{3, "2026-10-03"}, {4, "2026-12-12"}]), @today)

      assert window.stage == :unreleased
    end

    test "opened in theaters with a home date ahead is :theatrical, however long ago it opened" do
      window = ReleaseWindow.from_payload(payload([{3, "2025-01-10"}, {4, "2026-10-14"}]), @today)

      assert window.stage == :theatrical
    end

    test "opened in theaters recently with no home date is :theatrical" do
      window = ReleaseWindow.from_payload(payload([{3, "2026-08-21"}]), @today)

      assert window.stage == :theatrical
      assert window.digital == nil
      assert window.physical == nil
    end

    test "opened in theaters long ago with no home date is :unknown — TMDB's silence means nothing" do
      window = ReleaseWindow.from_payload(payload([{3, "1994-05-01"}]), @today)

      assert window.stage == :unknown
    end

    test "the theatrical run bound is inclusive at 180 days" do
      on_the_bound = Date.add(@today, -180)
      past_the_bound = Date.add(@today, -181)

      assert ReleaseWindow.from_payload(payload([{3, on_the_bound}]), @today).stage == :theatrical
      assert ReleaseWindow.from_payload(payload([{3, past_the_bound}]), @today).stage == :unknown
    end

    test "out today counts as out" do
      assert ReleaseWindow.from_payload(payload([{4, @today}]), @today).stage == :home
      assert ReleaseWindow.from_payload(payload([{3, @today}]), @today).stage == :theatrical
    end
  end

  describe "dates" do
    test "the earliest date of each type wins when TMDB lists several" do
      window =
        ReleaseWindow.from_payload(
          payload([{3, "2026-08-28"}, {3, "2026-08-21"}, {4, "2026-11-01"}, {4, "2026-10-14"}]),
          @today
        )

      assert window.theatrical == ~D[2026-08-21]
      assert window.digital == ~D[2026-10-14]
    end

    test "premieres and limited releases are not read" do
      window = ReleaseWindow.from_payload(payload([{1, "2026-03-01"}, {2, "2026-04-01"}]), @today)

      assert window.stage == :unknown
      assert window.theatrical == nil
    end

    test "only the US dates are read" do
      window =
        ReleaseWindow.from_payload(
          %{
            "id" => 1,
            "release_dates" => %{
              "results" => [
                %{
                  "iso_3166_1" => "FR",
                  "release_dates" => [%{"type" => 4, "release_date" => "2026-01-01T00:00:00.000Z"}]
                }
              ]
            }
          },
          @today
        )

      assert window.digital == nil
      assert window.stage == :unknown
    end

    test "the primary release date is carried" do
      window =
        ReleaseWindow.from_payload(
          payload([{3, "2026-08-21"}], %{"release_date" => "2026-08-21"}),
          @today
        )

      assert window.primary == ~D[2026-08-21]
    end
  end

  describe "primary date only" do
    test "a primary date ahead is :unreleased" do
      window = ReleaseWindow.from_payload(%{"id" => 1, "release_date" => "2027-03-05"}, @today)

      assert window.stage == :unreleased
      assert window.primary == ~D[2027-03-05]
      assert window.theatrical == nil
    end

    test "a passed primary date — a festival premiere, say — does not hide an opening ahead" do
      window =
        ReleaseWindow.from_payload(
          payload([{3, "2026-10-03"}], %{"release_date" => "2026-02-14"}),
          @today
        )

      assert window.stage == :unreleased
      assert window.primary == ~D[2026-02-14]
    end

    test "a primary date that has passed says nothing about the window" do
      window = ReleaseWindow.from_payload(%{"id" => 1, "release_date" => "2016-03-18"}, @today)

      assert window.stage == :unknown
    end

    test "no dates at all is :unknown" do
      window = ReleaseWindow.from_payload(%{"id" => 1, "title" => "Sample Movie"}, @today)

      assert window.stage == :unknown
      assert window.primary == nil
    end

    test "a blank or malformed primary date is no date" do
      assert ReleaseWindow.from_payload(%{"release_date" => ""}, @today).stage == :unknown
      assert ReleaseWindow.from_payload(%{"release_date" => "soon"}, @today).stage == :unknown
    end
  end
end
