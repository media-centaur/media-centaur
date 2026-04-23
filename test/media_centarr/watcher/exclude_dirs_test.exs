defmodule MediaCentarr.Watcher.ExcludeDirsTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Watcher.ExcludeDirs
  alias MediaCentarr.Watcher.ExcludeDirs.Prepared

  describe "prepare/1" do
    test "returns a Prepared struct" do
      assert %Prepared{} = ExcludeDirs.prepare([])
    end

    test "precomputes the dir-with-trailing-slash form once" do
      prepared = ExcludeDirs.prepare(["/videos/Captures", "/videos/staging"])

      assert prepared.entries == [
               {"/videos/Captures", "/videos/Captures/"},
               {"/videos/staging", "/videos/staging/"}
             ]
    end

    test "handles an empty list" do
      assert ExcludeDirs.prepare([]).entries == []
    end
  end

  describe "excluded?/2" do
    test "returns false when the prepared list is empty" do
      refute ExcludeDirs.excluded?("/videos/movie.mkv", ExcludeDirs.prepare([]))
    end

    test "returns true when path equals an exclude dir exactly" do
      # Regression: the production crash case. An inotify event for the
      # exclude directory itself ("/videos/Captures") was delivered as a
      # plain path; the previous implementation raised FunctionClauseError
      # because `excluded?` received a list of raw strings instead of the
      # prepared shape.
      prepared = ExcludeDirs.prepare(["/videos/Captures"])
      assert ExcludeDirs.excluded?("/videos/Captures", prepared)
    end

    test "returns true when path is nested inside an exclude dir" do
      prepared = ExcludeDirs.prepare(["/videos/Captures"])
      assert ExcludeDirs.excluded?("/videos/Captures/clip.mkv", prepared)
    end

    test "returns true when path is deeply nested inside an exclude dir" do
      prepared = ExcludeDirs.prepare(["/videos/Captures"])
      assert ExcludeDirs.excluded?("/videos/Captures/2026/clip.mkv", prepared)
    end

    test "returns false when path shares a prefix but is not actually nested" do
      prepared = ExcludeDirs.prepare(["/videos/Cap"])
      refute ExcludeDirs.excluded?("/videos/Captures-extras/clip.mkv", prepared)
    end

    test "returns false when path is unrelated to exclude dirs" do
      prepared = ExcludeDirs.prepare(["/videos/Captures", "/videos/staging"])
      refute ExcludeDirs.excluded?("/videos/Movies/Inception.mkv", prepared)
    end

    test "returns true when any one of multiple exclude dirs matches" do
      prepared = ExcludeDirs.prepare(["/videos/Captures", "/videos/staging"])
      assert ExcludeDirs.excluded?("/videos/staging/incoming.mkv", prepared)
    end

    test "raises FunctionClauseError if passed a raw list (not Prepared)" do
      # Type safety: the struct pattern in the function head catches misuse
      # at the boundary, with a clear stack trace pointing at the caller —
      # not buried inside an anonymous fn. `apply/3` defeats the static
      # type checker so the dynamic guarantee can still be asserted.
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(ExcludeDirs, :excluded?, ["/videos/movie.mkv", ["/videos/Captures"]])
      end
    end
  end
end
