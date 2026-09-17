defmodule MediaCentaur.Acquisition.Plans.FitTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.Plans.Fit

  describe "span_total/2 — the episode count a scope lands on disk" do
    test "an episode is one; an episode span is its breadth, no span sizes needed" do
      assert Fit.span_total({:episode, 1, 3}, %{}) == 1
      assert Fit.span_total({:episodes, 1, 4, 9}, %{}) == 6
    end

    test "a season reads its aired count; an unknown season is nil" do
      assert Fit.span_total({:season, 2}, %{"2" => 18}) == 18
      assert Fit.span_total({:season, 3}, %{"2" => 18}) == nil
    end

    test "a season range sums only when every season is known" do
      assert Fit.span_total({:seasons, 1, 2}, %{"1" => 24, "2" => 18}) == 42
      assert Fit.span_total({:seasons, 1, 3}, %{"1" => 24, "2" => 18}) == nil
    end

    test "the series sums every known season; nothing known is nil" do
      assert Fit.span_total(:series, %{"1" => 24, "2" => 18}) == 42
      assert Fit.span_total(:series, %{}) == nil
    end

    test "an unknown scope is nil" do
      assert Fit.span_total(:unknown, %{"1" => 24}) == nil
    end
  end

  describe "fits?/3 — wanted-in-span over span-total against the threshold" do
    test "inclusive at the boundary" do
      assert Fit.fits?(3, 4, 0.75)
      refute Fit.fits?(2, 4, 0.75)
    end

    test "an unknown total, an empty span, or no threshold is not judged" do
      assert Fit.fits?(1, nil, 0.75)
      assert Fit.fits?(1, 0, 0.75)
      assert Fit.fits?(1, 22, nil)
    end
  end
end
