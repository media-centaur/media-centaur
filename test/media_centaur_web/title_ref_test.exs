defmodule MediaCentaurWeb.TitleRefTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.TitleRef

  test "the URL param round-trips" do
    assert TitleRef.parse("movie-777") == {:ok, {777, :movie}}
    assert TitleRef.parse("tv_series-42") == {:ok, {42, :tv_series}}
    assert TitleRef.parse("book-1") == :error
    assert TitleRef.parse("movie-x") == :error
    assert TitleRef.parse(nil) == :error
    assert TitleRef.param({777, :movie}) == "movie-777"
    assert TitleRef.param({42, :tv_series}) == "tv_series-42"
  end
end
