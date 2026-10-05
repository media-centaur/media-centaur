defmodule MediaCentaur.Playback.CompletionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.Completion

  # mpv's `chapter-list` IPC payload is a list of string-keyed maps:
  # `%{"title" => "...", "time" => 123.4}`. `content_end_seconds/2`
  # returns the start of the credits chapter that marks the real end of
  # content, so completion can fire there instead of grinding through the
  # tail to the 90% / eof fallback.

  describe "content_end_seconds/2" do
    test "returns the start of a titled End Credits chapter in the back stretch" do
      chapters = [
        %{"title" => "Opening", "time" => 0.0},
        %{"title" => "Part 1", "time" => 90.0},
        %{"title" => "End Credits", "time" => 1660.0}
      ]

      assert Completion.content_end_seconds(chapters, 1851.0) == 1660.0
    end

    test "matches an Outro title as well as Credits" do
      chapters = [%{"title" => "Show", "time" => 0.0}, %{"title" => "Outro", "time" => 1700.0}]
      assert Completion.content_end_seconds(chapters, 1851.0) == 1700.0
    end

    test "ignores an opening-credits chapter before the back-stretch floor" do
      # "Opening Credits" matches the credits keyword but sits at the start,
      # so it must never be read as the content end. Guards the classic
      # false positive.
      chapters = [
        %{"title" => "Opening Credits", "time" => 0.0},
        %{"title" => "Part 1", "time" => 120.0}
      ]

      assert Completion.content_end_seconds(chapters, 1851.0) == nil
    end

    test "returns nil when no chapter is titled as credits/outro" do
      chapters = [
        %{"title" => "Chapter 1", "time" => 0.0},
        %{"title" => "Chapter 2", "time" => 1700.0}
      ]

      assert Completion.content_end_seconds(chapters, 1851.0) == nil
    end

    test "does not treat a plain 'Ending' title as credits" do
      # "Ending" is often the story's climax chapter, not the credits.
      chapters = [%{"title" => "Ending", "time" => 1700.0}]
      assert Completion.content_end_seconds(chapters, 1851.0) == nil
    end

    test "picks the earliest qualifying credits chapter when several match" do
      chapters = [
        %{"title" => "Credits", "time" => 1660.0},
        %{"title" => "End Credits Song", "time" => 1750.0}
      ]

      assert Completion.content_end_seconds(chapters, 1851.0) == 1660.0
    end

    test "tolerates atom-keyed chapter maps" do
      chapters = [%{title: "End Credits", time: 1660.0}]
      assert Completion.content_end_seconds(chapters, 1851.0) == 1660.0
    end

    test "ignores chapters with a missing or nil title" do
      chapters = [%{"time" => 1700.0}, %{"title" => nil, "time" => 1720.0}]
      assert Completion.content_end_seconds(chapters, 1851.0) == nil
    end

    test "returns nil for an empty chapter list" do
      assert Completion.content_end_seconds([], 1851.0) == nil
    end

    test "returns nil when duration is unknown (zero or negative)" do
      chapters = [%{"title" => "End Credits", "time" => 1660.0}]
      assert Completion.content_end_seconds(chapters, 0.0) == nil
      assert Completion.content_end_seconds(chapters, -1.0) == nil
    end

    test "returns nil for non-list / non-numeric inputs" do
      assert Completion.content_end_seconds(nil, 1851.0) == nil

      assert Completion.content_end_seconds([%{"title" => "End Credits", "time" => 1660.0}], nil) ==
               nil
    end
  end

  describe "reason/3" do
    @chapters [%{"title" => "Feature", "time" => 0.0}, %{"title" => "End Credits", "time" => 1660.0}]

    test "names the credits chapter once the position reaches it" do
      assert Completion.reason(1660.0, 1851.0, @chapters) =~ "reached credits chapter"
    end

    test "is nil before the credits chapter, even past the chapter floor" do
      assert Completion.reason(1600.0, 1851.0, @chapters) == nil
    end

    test "falls back to 90% of the duration without a credits chapter" do
      assert Completion.reason(1666.0, 1851.0, []) =~ "reached 90.0% of 30:51"
      assert Completion.reason(1665.0, 1851.0, []) == nil
    end

    test "is nil without a usable position or duration" do
      assert Completion.reason(nil, 1851.0, []) == nil
      assert Completion.reason(1700.0, nil, []) == nil
      assert Completion.reason(1700.0, 0.0, []) == nil
    end
  end
end
