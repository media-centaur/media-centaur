defmodule MediaCentaur.Playback.IntroChapterTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.IntroChapter

  describe "intro?/1 — the chapter titles Skip Intro answers to" do
    test "matches the desktop package's titles, case-insensitively" do
      for title <- [
            "Intro",
            "intro",
            "Intro Song",
            "Opening",
            "Opening Credits",
            "OP",
            "OP 2",
            "OP2",
            "Prologue"
          ] do
        assert IntroChapter.intro?(title), title
      end
    end

    test "leaves every other title alone" do
      for title <- ["Introduction", "Open Water", "Operation Finale", "Prologues", "Chapter 1", "", nil] do
        refute IntroChapter.intro?(title), inspect(title)
      end
    end

    test "the words are the four the Lua package knows" do
      assert IntroChapter.words() == ["intro", "opening", "op", "prologue"]
    end
  end

  describe "skip_target/2 — where SELECT seeks to" do
    @chapters [
      %{"title" => "Intro", "time" => 0.0},
      %{"title" => "Story", "time" => 92.5},
      %{"title" => "Credits", "time" => 2500.0}
    ]

    test "the start of the chapter after an intro chapter" do
      assert IntroChapter.skip_target(@chapters, 0) == 92.5
    end

    test "nothing while the current chapter is not an intro" do
      assert IntroChapter.skip_target(@chapters, 1) == nil
    end

    test "nothing when the intro is the last chapter, or there is no current chapter" do
      assert IntroChapter.skip_target([%{"title" => "Intro", "time" => 0.0}], 0) == nil
      assert IntroChapter.skip_target(@chapters, nil) == nil
      assert IntroChapter.skip_target([], 0) == nil
    end
  end
end
