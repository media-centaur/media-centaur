defmodule MediaCentaur.TimeSeries.WindowTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TimeSeries.{Resolution, Window}

  test "six windows in order" do
    assert Window.all() == [:"5m", :"1h", :"5h", :"1d", :"1w", :"1mo"]
  end

  test "bar width, bar count and source resolution per window" do
    assert {10, 30, :"10s"} == shape(:"5m")
    assert {60, 60, :"1m"} == shape(:"1h")
    assert {300, 60, :"1m"} == shape(:"5h")
    assert {1_200, 72, :"10m"} == shape(:"1d")
    assert {7_200, 84, :"1h"} == shape(:"1w")
    assert {43_200, 60, :"1h"} == shape(:"1mo")
  end

  test "every bar is a whole multiple of its source resolution" do
    for window <- Window.all() do
      width = Resolution.width(Window.resolution(window))
      assert rem(Window.bar_seconds(window), width) == 0
    end
  end

  test "span never exceeds the source resolution's retention" do
    for window <- Window.all() do
      retention = Resolution.retention(Window.resolution(window))
      assert Window.span_seconds(window) <= retention
    end
  end

  test "parse accepts the six labels and rejects the rest" do
    assert Window.parse("5h") == {:ok, :"5h"}
    assert Window.parse("1mo") == {:ok, :"1mo"}
    assert Window.parse("2h") == :error
    assert Window.parse(nil) == :error
  end

  test "wide bars align to the local day" do
    refute Window.local_aligned?(:"5h")
    assert Window.local_aligned?(:"1d")
    assert Window.local_aligned?(:"1mo")
  end

  defp shape(window), do: {Window.bar_seconds(window), Window.bars(window), Window.resolution(window)}
end
