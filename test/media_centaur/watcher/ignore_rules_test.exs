defmodule MediaCentaur.Watcher.IgnoreRulesTest do
  @moduledoc """
  Unit tests for the single admission predicate. Carries forward every
  case the retired `Watcher.ExcludeDirsTest` held (path-rule matching,
  the prefix-not-nested boundary, the raw-list type guard) and adds the
  name-rule and video-extension halves that used to live in
  `Watcher.WalkTest` — one module now owns the whole question.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Watcher.IgnoreRules

  describe "new/2" do
    test "precomputes the path-rule trailing-slash form once" do
      rules = IgnoreRules.new(["/videos/Captures", "/videos/staging"], [])

      assert rules.path_rules == [
               {"/videos/Captures", "/videos/Captures/"},
               {"/videos/staging", "/videos/staging/"}
             ]
    end

    test "downcases name rules" do
      rules = IgnoreRules.new([], ["TRASH", "Sample"])

      assert "trash" in rules.name_rules
      assert "sample" in rules.name_rules
    end

    test "always includes the reserved name rules, even from empty lists" do
      assert IgnoreRules.reserved_name_rules() == [".staging"]
      assert IgnoreRules.new([], []).name_rules == [".staging"]
    end

    test "de-duplicates both rule kinds" do
      rules = IgnoreRules.new(["/videos/a", "/videos/a"], ["Sample", "sample", ".staging"])

      assert length(rules.path_rules) == 1
      assert rules.name_rules == ["sample", ".staging"]
    end
  end

  describe "ignored?/2 — path rules" do
    test "false when there are no configured rules" do
      refute IgnoreRules.ignored?("/videos/movie.mkv", IgnoreRules.new([], []))
    end

    test "true when the path equals a path rule exactly" do
      # Regression: an inotify event for the excluded directory itself
      # arrives as a plain path, not as a child of one.
      rules = IgnoreRules.new(["/videos/Captures"], [])
      assert IgnoreRules.ignored?("/videos/Captures", rules)
    end

    test "true when nested inside a path rule" do
      rules = IgnoreRules.new(["/videos/Captures"], [])
      assert IgnoreRules.ignored?("/videos/Captures/clip.mkv", rules)
    end

    test "true when deeply nested inside a path rule" do
      rules = IgnoreRules.new(["/videos/Captures"], [])
      assert IgnoreRules.ignored?("/videos/Captures/2026/clip.mkv", rules)
    end

    test "false when the path shares a prefix but is not actually nested" do
      rules = IgnoreRules.new(["/videos/Cap"], [])
      refute IgnoreRules.ignored?("/videos/Captures-extras/clip.mkv", rules)
    end

    test "false when the path is unrelated to every rule" do
      rules = IgnoreRules.new(["/videos/Captures", "/videos/staging"], [])
      refute IgnoreRules.ignored?("/videos/Movies/Sample.Movie.mkv", rules)
    end

    test "true when any one of multiple path rules matches" do
      rules = IgnoreRules.new(["/videos/Captures", "/videos/staging"], [])
      assert IgnoreRules.ignored?("/videos/staging/incoming.mkv", rules)
    end
  end

  describe "ignored?/2 — name rules" do
    test "true when any parent component matches, case-insensitively" do
      rules = IgnoreRules.new([], ["trash"])

      assert IgnoreRules.ignored?("/media/TRASH/b.mkv", rules)
      refute IgnoreRules.ignored?("/media/good/a.mkv", rules)
    end

    test "the file's own name never matches a name rule" do
      refute IgnoreRules.ignored?("/media/trash", IgnoreRules.new([], ["trash"]))
    end

    test ".staging parents match with no configured name rules" do
      rules = IgnoreRules.new([], [])

      assert IgnoreRules.ignored?("/media/.staging/Sample.Show/episode.mkv", rules)
      refute IgnoreRules.ignored?("/media/show/episode.mkv", rules)
    end
  end

  describe "ignored_dir?/2" do
    test "true when the directory's own basename is a name rule" do
      # The difference from ignored?/2: a directory named Sample is
      # ignored, a file named Sample is not.
      rules = IgnoreRules.new([], ["sample"])

      assert IgnoreRules.ignored_dir?("/media/Sample", rules)
      refute IgnoreRules.ignored?("/media/Sample", rules)
    end

    test "true when the directory is a path rule or sits under one" do
      rules = IgnoreRules.new(["/media/Captures"], [])

      assert IgnoreRules.ignored_dir?("/media/Captures", rules)
      assert IgnoreRules.ignored_dir?("/media/Captures/2026", rules)
      refute IgnoreRules.ignored_dir?("/media/Movies", rules)
    end

    test "cannot disagree with ignored?/2 about files underneath it" do
      rules = IgnoreRules.new([], ["sample"])

      assert IgnoreRules.ignored_dir?("/media/Sample", rules)
      assert IgnoreRules.ignored?("/media/Sample/padding.mkv", rules)
    end
  end

  describe "library_content?/2" do
    test "true for a recognised video file no rule ignores" do
      assert IgnoreRules.library_content?("/media/movie.mkv", IgnoreRules.new([], []))
    end

    test "false for a file extension the watcher does not recognise" do
      rules = IgnoreRules.new([], [])

      refute IgnoreRules.library_content?("/media/poster.jpg", rules)
      refute IgnoreRules.library_content?("/media/movie.nfo", rules)
    end

    test "false for a recognised video under a path rule" do
      rules = IgnoreRules.new(["/media/Captures"], [])
      refute IgnoreRules.library_content?("/media/Captures/clip.mkv", rules)
    end

    test "false for a recognised video under a name rule" do
      rules = IgnoreRules.new([], ["sample"])
      refute IgnoreRules.library_content?("/media/Sample/padding.mkv", rules)
    end
  end

  describe "load/1 — the shipped defaults" do
    # Behavioural, not a check on the literal: what matters is that a
    # stock install does not admit either spelling of the encode-sample
    # folder. `Samples/` used to be admitted and parsed, which produced a
    # Review Queue entry with no possible TMDB match.
    test "neither spelling of the sample folder is library content" do
      rules = IgnoreRules.load("/media")

      refute IgnoreRules.library_content?("/media/Film/Sample/clip.mkv", rules)
      refute IgnoreRules.library_content?("/media/Film/Samples/clip.mkv", rules)
      assert IgnoreRules.ignored_dir?("/media/Film/Sample", rules)
      assert IgnoreRules.ignored_dir?("/media/Film/Samples", rules)
    end

    test "a real title beside them is still library content" do
      rules = IgnoreRules.load("/media")

      assert IgnoreRules.library_content?("/media/Film/Sample.Movie.2010.mkv", rules)
    end
  end

  describe "type safety" do
    test "every predicate raises if handed a raw list instead of the struct" do
      # The struct pattern in each function head catches misuse at the
      # boundary with a stack trace pointing at the caller, rather than
      # failing inside an anonymous fn. `apply/3` defeats the static
      # type checker so the dynamic guarantee can still be asserted.
      for fun <- [:ignored?, :ignored_dir?, :library_content?] do
        assert_raise FunctionClauseError, fn ->
          # credo:disable-for-next-line Credo.Check.Refactor.Apply
          apply(IgnoreRules, fun, ["/videos/movie.mkv", ["/videos/Captures"]])
        end
      end
    end
  end
end
