defmodule MediaCentaur.Review.RememberedMatchTest do
  @moduledoc """
  A person's answer in Review is kept for the files named the same way
  (campaign `review-bulk-match`): a show whose releases carry a tag TMDB
  does not know is answered once, not once per episode or per week.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Review

  @title %{
    tmdb_id: 4242,
    tmdb_type: "tv",
    title: "Sample Show",
    year: "1995",
    poster_path: "/sample.jpg"
  }

  defp waiting_episode(path, overrides \\ %{}) do
    create_pending_file(
      Map.merge(
        %{
          file_path: path,
          parsed_title: "Sample Show Signed",
          parsed_type: "tv",
          parsed_season: 1,
          parsed_episode: 1,
          tmdb_id: nil,
          tmdb_type: nil,
          confidence: nil,
          match_title: nil
        },
        overrides
      )
    )
  end

  describe "match/2 remembers the answer" do
    test "for the name the matched files were read as" do
      file = waiting_episode("/media/test/a.mkv")

      {:ok, 1} = Review.match([file.id], @title)

      remembered = Review.remembered_match("Sample Show Signed", :tv, nil)
      assert {remembered.tmdb_id, remembered.tmdb_type} == {4242, "tv"}
      assert {remembered.match_title, remembered.match_year} == {"Sample Show", "1995"}
    end

    test "once per name, however many files carried it" do
      first = waiting_episode("/media/test/a.mkv")
      second = waiting_episode("/media/test/b.mkv", %{parsed_episode: 2})
      other = waiting_episode("/media/test/c.mkv", %{parsed_title: "Sample Show Sign Language"})

      {:ok, 3} = Review.match([first.id, second.id, other.id], @title)

      assert ["Sample Show Sign Language", "Sample Show Signed"] =
               Enum.map(Review.list_remembered_matches(), & &1.parsed_title)
    end

    test "a later answer for the same name replaces the earlier one" do
      first = waiting_episode("/media/test/a.mkv")
      {:ok, 1} = Review.match([first.id], @title)

      second = waiting_episode("/media/test/b.mkv")
      {:ok, 1} = Review.match([second.id], %{@title | tmdb_id: 9999})

      assert [%{tmdb_id: 9999}] = Review.list_remembered_matches()
    end

    test "accepting a best guess is an answer too" do
      file =
        waiting_episode("/media/test/a.mkv", %{
          tmdb_id: 4242,
          tmdb_type: "tv",
          match_title: "Sample Show"
        })

      {:ok, 1} = Review.approve([file.id])

      assert %{tmdb_id: 4242} = Review.remembered_match("Sample Show Signed", :tv, nil)
    end

    test "an extra is remembered under the type it is searched as" do
      file =
        waiting_episode("/media/test/Sample Show Signed/Extras/Making Of.mkv", %{
          parsed_type: "extra",
          parsed_season: nil,
          parsed_episode: nil
        })

      {:ok, 1} = Review.match([file.id], %{@title | tmdb_type: "movie"})

      assert %{tmdb_id: 4242} = Review.remembered_match("Sample Show Signed", :movie, nil)
    end
  end

  describe "remembered_match/3" do
    setup do
      file = waiting_episode("/media/test/a.mkv", %{parsed_title: "Sample's Show Signed"})
      {:ok, 1} = Review.match([file.id], @title)
      :ok
    end

    test "compares names in folded form — punctuation, case and accents do not matter" do
      assert %{tmdb_id: 4242} = Review.remembered_match("samples.show.SIGNED", :tv, nil)
      assert %{tmdb_id: 4242} = Review.remembered_match("Sámple's Show Signed", :tv, nil)
    end

    # Owner decision 2026-11-05: a name with a year is often a remake, a
    # different title from the one without.
    test "the year is part of the name" do
      assert Review.remembered_match("Sample's Show Signed", :tv, 2020) == nil
    end

    test "the type is part of the name" do
      assert Review.remembered_match("Sample's Show Signed", :movie, nil) == nil
    end
  end

  describe "forget_remembered_match/1" do
    test "removes the answer" do
      file = waiting_episode("/media/test/a.mkv")
      {:ok, 1} = Review.match([file.id], @title)
      [remembered] = Review.list_remembered_matches()

      assert :ok = Review.forget_remembered_match(remembered.id)

      assert Review.remembered_match("Sample Show Signed", :tv, nil) == nil
    end
  end

  # A rematch says the title was wrong. Left in place, the remembered answer
  # would import the released files to the same wrong title on the next
  # rescan, undoing the rematch. Discovery looks a file up by the name the
  # current parser reads, so that is the name a rematch forgets.
  describe "a rematch" do
    test "forgets the answers for the names its files carry" do
      file =
        waiting_episode("/media/test/Sample.Show.Unaired.S01E01.mkv", %{
          parsed_title: "Sample Show Unaired"
        })

      {:ok, 1} = Review.match([file.id], @title)
      unrelated = waiting_episode("/media/test/Other.Show.S01E01.mkv", %{parsed_title: "Other Show"})
      {:ok, 1} = Review.match([unrelated.id], %{@title | tmdb_id: 7})

      {:ok, 1} =
        Review.add_files_for_review([
          %{file_path: "/media/test/Sample.Show.Unaired.S01E01.mkv", media_dir: "/media/test"}
        ])

      assert Review.remembered_match("Sample Show Unaired", :tv, nil) == nil
      assert %{tmdb_id: 7} = Review.remembered_match("Other Show", :tv, nil)
    end
  end
end
