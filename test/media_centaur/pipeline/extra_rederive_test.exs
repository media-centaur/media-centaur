defmodule MediaCentaur.Pipeline.ExtraRederiveTest do
  @moduledoc """
  The re-derive sweep (Phase 1 of the deriver-model campaign): re-parses every
  extra's `content_url` and refreshes `name` where the freshly-derived value
  differs, so a parser-rule fix heals existing records with no network call and
  no hand-written backfill.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Pipeline.ExtraRederive

  # Generic placeholder paths (this file is not the parser_test real-filename
  # exemption). The "Web Previews" case mirrors the origin bug's shape — a folder
  # whose name begins with the WEB source token — without a real show title.
  @blank_extra_path "/media/test/Sample Show - Season 01/Extras/Web Previews/[Web Preview] Sample Show - Episode 16.mkv"
  @blank_extra_name "Web Previews - [Web Preview] Sample Show - Episode 16"

  @plain_extra_path "/media/test/Sample Show - Season 01/Extras/Making Of.mkv"
  @plain_extra_name "Making Of"

  # A path that does NOT parse as an extra — re-derive must leave it untouched.
  @movie_path "/media/test/Movies/Sample Movie (2010) 1080p BluRay x265.mkv"

  setup do
    movie = create_movie(%{name: "Sample Movie"})
    %{movie: movie}
  end

  describe "rederive_all/0" do
    test "fills in a blank name from the file path", %{movie: movie} do
      extra = create_extra(%{movie_id: movie.id, name: nil, content_url: @blank_extra_path})

      assert {:ok, summary} = ExtraRederive.rederive_all()
      assert summary.updated >= 1

      assert reload_name(extra) == @blank_extra_name
    end

    test "refreshes a drifted name to the rule's current output", %{movie: movie} do
      extra = create_extra(%{movie_id: movie.id, name: "Stale Name", content_url: @plain_extra_path})

      assert {:ok, _summary} = ExtraRederive.rederive_all()
      assert reload_name(extra) == @plain_extra_name
    end

    test "leaves an already-correct name untouched (idempotent)", %{movie: movie} do
      extra =
        create_extra(%{movie_id: movie.id, name: @plain_extra_name, content_url: @plain_extra_path})

      assert {:ok, summary} = ExtraRederive.rederive_all()
      assert summary.updated == 0
      assert reload_name(extra) == @plain_extra_name

      # second pass changes nothing
      assert {:ok, second} = ExtraRederive.rederive_all()
      assert second.updated == 0
    end

    test "does not touch an extra whose path no longer parses as an extra", %{movie: movie} do
      extra = create_extra(%{movie_id: movie.id, name: "Keep This Name", content_url: @movie_path})

      assert {:ok, summary} = ExtraRederive.rederive_all()
      assert summary.skipped >= 1
      assert reload_name(extra) == "Keep This Name"
    end

    test "reports scanned / updated / skipped counts", %{movie: movie} do
      create_extra(%{movie_id: movie.id, name: nil, content_url: @blank_extra_path})
      create_extra(%{movie_id: movie.id, name: @plain_extra_name, content_url: @plain_extra_path})
      create_extra(%{movie_id: movie.id, name: "Keep", content_url: @movie_path})

      assert {:ok, summary} = ExtraRederive.rederive_all()
      assert summary.scanned == 3
      assert summary.updated == 1
      assert summary.skipped == 1
    end
  end

  defp reload_name(extra) do
    Repo.get!(MediaCentaur.Library.Extra, extra.id).name
  end
end
