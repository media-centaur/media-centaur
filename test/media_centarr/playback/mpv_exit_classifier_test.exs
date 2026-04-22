defmodule MediaCentarr.Playback.MpvExitClassifierTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Playback.MpvExitClassifier

  describe "classify/1" do
    test "ended when property events arrived" do
      assert MpvExitClassifier.classify(%{
               seen_property_event?: true,
               exit_status: 0,
               output_tail: []
             }) == {:ok, :ended}
    end

    test "ended when property events arrived even with non-zero exit status" do
      assert MpvExitClassifier.classify(%{
               seen_property_event?: true,
               exit_status: 2,
               output_tail: ["late error after playback"]
             }) == {:ok, :ended}
    end

    test "startup_failure when no property events and non-zero exit" do
      assert {:error, :startup_failure, message} =
               MpvExitClassifier.classify(%{
                 seen_property_event?: false,
                 exit_status: 1,
                 output_tail: ["Failed to recognize file format."]
               })

      assert message =~ "Failed to recognize file format"
    end

    test "startup_failure when no property events even with zero exit" do
      assert {:error, :startup_failure, message} =
               MpvExitClassifier.classify(%{
                 seen_property_event?: false,
                 exit_status: 0,
                 output_tail: ["Cannot open display"]
               })

      assert message =~ "Cannot open display"
    end

    test "startup_failure when exit status is unknown (socket closed first, port never reported)" do
      assert {:error, :startup_failure, _message} =
               MpvExitClassifier.classify(%{
                 seen_property_event?: false,
                 exit_status: nil,
                 output_tail: ["Error opening input: No such file or directory"]
               })
    end

    test "picks the most error-looking line when multiple lines are present" do
      assert {:error, :startup_failure, message} =
               MpvExitClassifier.classify(%{
                 seen_property_event?: false,
                 exit_status: 1,
                 output_tail: [
                   "[vo/gpu] Selected GPU context: wayland",
                   "[ffmpeg] libav: warning: deprecated pixel format",
                   "Failed to recognize file format."
                 ]
               })

      assert message =~ "Failed to recognize file format"
      refute message =~ "libav"
    end

    test "strips ANSI colour codes from the summary" do
      assert {:error, :startup_failure, message} =
               MpvExitClassifier.classify(%{
                 seen_property_event?: false,
                 exit_status: 1,
                 output_tail: ["\e[31mError opening input file\e[0m"]
               })

      refute message =~ "\e["
      assert message =~ "Error opening input file"
    end

    test "generic fallback message when output is empty and exit nonzero" do
      assert {:error, :startup_failure, message} =
               MpvExitClassifier.classify(%{
                 seen_property_event?: false,
                 exit_status: 2,
                 output_tail: []
               })

      assert message =~ "exit"
      assert message =~ "2"
    end

    test "generic fallback message when output is empty and exit unknown" do
      assert {:error, :startup_failure, message} =
               MpvExitClassifier.classify(%{
                 seen_property_event?: false,
                 exit_status: nil,
                 output_tail: []
               })

      assert is_binary(message)
      assert message != ""
    end

    test "truncates very long error messages" do
      long_line = String.duplicate("x", 500)

      assert {:error, :startup_failure, message} =
               MpvExitClassifier.classify(%{
                 seen_property_event?: false,
                 exit_status: 1,
                 output_tail: [long_line]
               })

      assert String.length(message) <= 200
    end

    test "ignores blank lines when choosing the summary" do
      assert {:error, :startup_failure, message} =
               MpvExitClassifier.classify(%{
                 seen_property_event?: false,
                 exit_status: 1,
                 output_tail: ["Failed to open file", "", "   "]
               })

      assert message =~ "Failed to open file"
    end
  end

  describe "append_output/2" do
    test "splits data on newlines and appends to tail" do
      tail = MpvExitClassifier.append_output([], "first line\nsecond line\n")
      assert tail == ["first line", "second line"]
    end

    test "drops empty trailing entry from a trailing newline" do
      tail = MpvExitClassifier.append_output([], "only line\n")
      assert tail == ["only line"]
    end

    test "keeps only the last 50 lines" do
      initial = Enum.map(1..49, &"line #{&1}")
      new_data = "line 50\nline 51\nline 52\n"
      tail = MpvExitClassifier.append_output(initial, new_data)

      assert length(tail) == 50
      assert List.first(tail) == "line 3"
      assert List.last(tail) == "line 52"
    end

    test "handles incomplete trailing lines by keeping them" do
      tail = MpvExitClassifier.append_output([], "complete\npartial")
      assert tail == ["complete", "partial"]
    end
  end
end
