defmodule MediaCentaur.Playback.CompletionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.Completion

  # mpv's `chapter-list` IPC payload is a list of string-keyed maps:
  # `%{"title" => "...", "time" => 123.4}`. The content end is the start
  # of a credits chapter when the file has one, otherwise the duration
  # less the assumed credits length for the playable's kind.

  # A 30:51 episode without a credits chapter ends its content 3 minutes
  # before the end of the file.
  @episode_estimate 1851.0 - 180

  describe "content_end_seconds/3 with a credits chapter" do
    test "returns the start of a titled End Credits chapter in the back stretch" do
      chapters = [
        %{"title" => "Opening", "time" => 0.0},
        %{"title" => "Part 1", "time" => 90.0},
        %{"title" => "End Credits", "time" => 1660.0}
      ]

      assert Completion.content_end_seconds(chapters, 1851.0, :episode) == 1660.0
    end

    test "matches an Outro title as well as Credits" do
      chapters = [%{"title" => "Show", "time" => 0.0}, %{"title" => "Outro", "time" => 1700.0}]
      assert Completion.content_end_seconds(chapters, 1851.0, :episode) == 1700.0
    end

    test "picks the earliest qualifying credits chapter when several match" do
      chapters = [
        %{"title" => "Credits", "time" => 1660.0},
        %{"title" => "End Credits Song", "time" => 1750.0}
      ]

      assert Completion.content_end_seconds(chapters, 1851.0, :episode) == 1660.0
    end

    test "tolerates atom-keyed chapter maps" do
      chapters = [%{title: "End Credits", time: 1660.0}]
      assert Completion.content_end_seconds(chapters, 1851.0, :episode) == 1660.0
    end

    test "takes a credits chapter over the estimate even when the chapter is later" do
      chapters = [%{"title" => "End Credits", "time" => 1800.0}]
      assert Completion.content_end_seconds(chapters, 1851.0, :episode) == 1800.0
    end
  end

  describe "content_end_seconds/3 without a credits chapter" do
    test "ignores an opening-credits chapter before the back-stretch floor" do
      # "Opening Credits" matches the credits keyword but sits at the start,
      # so it must never be read as the content end. Guards the classic
      # false positive.
      chapters = [
        %{"title" => "Opening Credits", "time" => 0.0},
        %{"title" => "Part 1", "time" => 120.0}
      ]

      assert Completion.content_end_seconds(chapters, 1851.0, :episode) == @episode_estimate
    end

    test "estimates when no chapter is titled as credits/outro" do
      chapters = [
        %{"title" => "Chapter 1", "time" => 0.0},
        %{"title" => "Chapter 2", "time" => 1700.0}
      ]

      assert Completion.content_end_seconds(chapters, 1851.0, :episode) == @episode_estimate
    end

    test "does not treat a plain 'Ending' title as credits" do
      # "Ending" is often the story's climax chapter, not the credits.
      chapters = [%{"title" => "Ending", "time" => 1700.0}]
      assert Completion.content_end_seconds(chapters, 1851.0, :episode) == @episode_estimate
    end

    test "ignores chapters with a missing or nil title" do
      chapters = [%{"time" => 1700.0}, %{"title" => nil, "time" => 1720.0}]
      assert Completion.content_end_seconds(chapters, 1851.0, :episode) == @episode_estimate
    end

    test "estimates for an empty or missing chapter list" do
      assert Completion.content_end_seconds([], 1851.0, :episode) == @episode_estimate
      assert Completion.content_end_seconds(nil, 1851.0, :episode) == @episode_estimate
    end

    test "assumes credits run 10% of a short file" do
      assert Completion.content_end_seconds([], 1200.0, :episode) == 1080.0
      assert Completion.content_end_seconds([], 3600.0, :movie) == 3240.0
    end

    test "assumes a movie's credits run at most 8 minutes" do
      assert Completion.content_end_seconds([], 9382.0, :movie) == 9382.0 - 480
    end

    test "assumes any other playable's credits run at most 3 minutes" do
      for kind <- [:episode, :extra, :video_object, nil] do
        assert Completion.content_end_seconds([], 3600.0, kind) == 3600.0 - 180
      end
    end

    test "returns nil when duration is unknown" do
      chapters = [%{"title" => "End Credits", "time" => 1660.0}]
      assert Completion.content_end_seconds(chapters, 0.0, :episode) == nil
      assert Completion.content_end_seconds(chapters, -1.0, :episode) == nil
      assert Completion.content_end_seconds(chapters, nil, :episode) == nil
    end
  end

  describe "reason/4" do
    @chapters [%{"title" => "Feature", "time" => 0.0}, %{"title" => "End Credits", "time" => 1660.0}]

    test "names the credits chapter once the position reaches it" do
      assert Completion.reason(1660.0, 1851.0, @chapters, :episode) =~ "reached credits chapter"
    end

    test "is nil before the credits chapter, even past the chapter floor" do
      assert Completion.reason(1600.0, 1851.0, @chapters, :episode) == nil
    end

    test "names the estimated credits start without a credits chapter" do
      assert Completion.reason(1671.0, 1851.0, [], :episode) =~
               "reached estimated credits start at 27:51"

      assert Completion.reason(1670.0, 1851.0, [], :episode) == nil
    end

    test "leaves a long movie incomplete 14 minutes from the end" do
      assert Completion.reason(8562.0, 9382.0, [], :movie) == nil
      assert Completion.reason(8902.0, 9382.0, [], :movie) =~ "reached estimated credits start"
    end

    test "is nil without a usable position or duration" do
      assert Completion.reason(nil, 1851.0, [], :episode) == nil
      assert Completion.reason(1700.0, nil, [], :episode) == nil
      assert Completion.reason(1700.0, 0.0, [], :episode) == nil
    end
  end
end
