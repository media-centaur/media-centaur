defmodule MediaCentaurWeb.ReviewHelpersTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.ReviewHelpers

  # --- confidence display ---

  describe "reason_label/1" do
    test "returns labels for each reason" do
      assert ReviewHelpers.reason_label(:no_results) == "No TMDB results"
      assert ReviewHelpers.reason_label(:low_confidence) == "Low confidence"
      assert ReviewHelpers.reason_label(:tied) == "Tied match"
    end
  end

  describe "reason_text_class/1" do
    test "returns text classes for each reason" do
      assert ReviewHelpers.reason_text_class(:no_results) == "text-error"
      assert ReviewHelpers.reason_text_class(:low_confidence) == "text-warning"
      assert ReviewHelpers.reason_text_class(:tied) == "text-info"
    end
  end

  # --- format_type/1 ---

  describe "format_type/1" do
    test "formats known string types" do
      assert ReviewHelpers.format_type("movie") == "Movie"
      assert ReviewHelpers.format_type("tv") == "TV"
      assert ReviewHelpers.format_type("extra") == "Extra"
      assert ReviewHelpers.format_type("unknown") == "Unknown"
    end

    test "returns Unknown for nil" do
      assert ReviewHelpers.format_type(nil) == "Unknown"
    end

    test "capitalizes atom types" do
      assert ReviewHelpers.format_type(:documentary) == "Documentary"
    end
  end

  # The bulk list (campaign `review-bulk-match`): one flat list of review
  # items, a filter, ticks and an action bar. Nothing groups files
  # automatically; the dividers only mark where the parsed title changes.

  defp item(overrides) do
    build_pending_file(
      Map.merge(
        %{
          status: :pending,
          parsed_title: "Sample Show",
          parsed_year: nil,
          parsed_type: "tv",
          error_message: nil
        },
        overrides
      )
    )
  end

  describe "status_of/1" do
    test "a pending item waits, an approved one imports, a dismissed one is dismissed" do
      assert ReviewHelpers.status_of(item(%{status: :pending})) == :waiting
      assert ReviewHelpers.status_of(item(%{status: :pending, error_message: "failed"})) == :waiting
      assert ReviewHelpers.status_of(item(%{status: :approved})) == :importing
      assert ReviewHelpers.status_of(item(%{status: :dismissed})) == :dismissed
    end
  end

  describe "count_by_status/1" do
    test "counts each status, zero for the absent ones" do
      files = [item(%{}), item(%{}), item(%{status: :approved})]

      assert ReviewHelpers.count_by_status(files) == %{waiting: 2, importing: 1, dismissed: 0}
    end
  end

  describe "visible/3" do
    test "keeps the items of the chosen status" do
      waiting = item(%{})
      dismissed = item(%{status: :dismissed})

      assert ReviewHelpers.visible([waiting, dismissed], :waiting, "") == [waiting]
      assert ReviewHelpers.visible([waiting, dismissed], :dismissed, "") == [dismissed]
    end

    test "the filter matches the parsed title or the file name, ignoring case and separators" do
      by_title = item(%{parsed_title: "Sample Show Signed", file_path: "/media/a/x.mkv"})
      by_file = item(%{parsed_title: "Other", file_path: "/media/b/Sample.Show.2005.S01E07.mkv"})
      neither = item(%{parsed_title: "Movie A", file_path: "/media/c/Movie.A.mkv"})

      assert ReviewHelpers.visible([by_title, by_file, neither], :waiting, "sample show") == [
               by_title,
               by_file
             ]
    end
  end

  describe "rows/1" do
    test "puts a divider where the parsed title or year changes, carrying the ids below it" do
      first = item(%{parsed_title: "Sample Show Signed"})
      second = item(%{parsed_title: "sample show signed"})
      remake = item(%{parsed_title: "Sample Show Signed", parsed_year: 2005})

      assert [
               {:divider, %{label: "Sample Show Signed", ids: ids}},
               {:item, ^first},
               {:item, ^second},
               {:divider, %{label: "Sample Show Signed (2005)", ids: [remake_id]}},
               {:item, ^remake}
             ] = ReviewHelpers.rows([first, second, remake])

      assert ids == [first.id, second.id]
      assert remake_id == remake.id
    end
  end

  describe "toggle/2 and tick_state/2" do
    test "ticks the ids when any is unticked, unticks them when all are ticked" do
      ticked = ReviewHelpers.toggle(MapSet.new(["a"]), ["a", "b"])
      assert ticked == MapSet.new(["a", "b"])
      assert ReviewHelpers.toggle(ticked, ["a", "b"]) == MapSet.new()
    end

    test "reports a block as checked, partly checked or unchecked" do
      selected = MapSet.new(["a"])

      assert ReviewHelpers.tick_state(selected, ["a"]) == :checked
      assert ReviewHelpers.tick_state(selected, ["a", "b"]) == :indeterminate
      assert ReviewHelpers.tick_state(selected, ["b"]) == :unchecked
      assert ReviewHelpers.tick_state(selected, []) == :unchecked
    end
  end

  describe "search_prefill/2" do
    test "is the first ticked item's parsed title, searched as its type" do
      movie = item(%{parsed_title: "Movie A", parsed_type: "movie"})
      show = item(%{parsed_title: "Sample Show Signed", parsed_type: "tv"})

      assert ReviewHelpers.search_prefill([movie, show], MapSet.new([show.id])) ==
               {"Sample Show Signed", :tv}

      assert ReviewHelpers.search_prefill([movie, show], MapSet.new([movie.id, show.id])) ==
               {"Movie A", :movie}
    end

    test "an extra with a season is searched as a series, one without as a film" do
      with_season = item(%{parsed_type: "extra", parsed_season: 1})
      without = item(%{parsed_type: "extra", parsed_season: nil})

      assert {_, :tv} = ReviewHelpers.search_prefill([with_season], MapSet.new([with_season.id]))
      assert {_, :movie} = ReviewHelpers.search_prefill([without], MapSet.new([without.id]))
    end

    test "is nil with nothing ticked" do
      assert ReviewHelpers.search_prefill([item(%{})], MapSet.new()) == nil
    end
  end

  describe "accept_guesses?/1" do
    test "only when every ticked item has a best guess" do
      assert ReviewHelpers.accept_guesses?([item(%{tmdb_id: 1}), item(%{tmdb_id: 2})])
      refute ReviewHelpers.accept_guesses?([item(%{tmdb_id: 1}), item(%{tmdb_id: nil})])
      refute ReviewHelpers.accept_guesses?([])
    end
  end

  describe "delete_partitions/1" do
    # Each release folder is judged on its own by `DeleteTargets`: a
    # selection spanning six release folders deletes six folders, never a
    # common ancestor.
    test "splits paths by the folder that holds them" do
      paths = ["/m/A/a.mkv", "/m/B/b.mkv", "/m/A/c.mkv"]

      assert ReviewHelpers.delete_partitions(paths) == [["/m/A/a.mkv", "/m/A/c.mkv"], ["/m/B/b.mkv"]]
    end
  end

  describe "episode_label/1" do
    test "is SxxEyy when both are parsed, else empty" do
      assert ReviewHelpers.episode_label(item(%{parsed_season: 1, parsed_episode: 7})) == "S01E07"
      assert ReviewHelpers.episode_label(item(%{parsed_season: nil, parsed_episode: nil})) == ""
    end
  end

  describe "delete_label/1" do
    # The armed Delete names what goes, so confirming is never a guess.
    test "names the files, and the folders that go with them" do
      assert ReviewHelpers.delete_label([{:files, ["/m/a.mkv"]}]) == "Press again to delete 1 file"

      assert ReviewHelpers.delete_label([
               {:folder, "/m/A", ["/m/A/a.mkv", "/m/A/b.mkv"]},
               {:files, ["/m/c.mkv"]}
             ]) ==
               "Press again to delete 3 files and 1 folder"

      assert ReviewHelpers.delete_label([
               {:folder, "/m/A", ["/m/A/a.mkv"]},
               {:folder, "/m/B", ["/m/B/b.mkv"]}
             ]) ==
               "Press again to delete 2 files and 2 folders"
    end
  end
end
