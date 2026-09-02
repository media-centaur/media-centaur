defmodule MediaCentaur.Nostr.FilterTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.Filter

  test "builds only the keys given, in NIP-01 wire form" do
    filter =
      Filter.new(
        authors: ["ab", "cd"],
        kinds: [32_160],
        since: 1_700_000_000,
        limit: 50,
        tags: %{"d" => ["tmdb:movie:603"]}
      )

    assert Filter.to_map(filter) == %{
             "authors" => ["ab", "cd"],
             "kinds" => [32_160],
             "since" => 1_700_000_000,
             "limit" => 50,
             "#d" => ["tmdb:movie:603"]
           }
  end

  test "an empty filter is an empty map" do
    assert Filter.to_map(Filter.new([])) == %{}
  end

  test "ids and until are supported; unknown options raise" do
    assert Filter.to_map(Filter.new(ids: ["ef"], until: 5)) == %{"ids" => ["ef"], "until" => 5}
    assert_raise KeyError, fn -> Filter.new(kind: 1) end
  end
end
