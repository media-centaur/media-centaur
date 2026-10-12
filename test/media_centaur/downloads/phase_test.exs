defmodule MediaCentaur.Downloads.PhaseTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Downloads.{Phase, QueueItem}

  defp usenet(state, overrides \\ %{}) do
    struct!(
      %QueueItem{id: "nzo", title: "Sample.Show", state: state, protocol: :usenet, status: nil},
      overrides
    )
  end

  defp torrent(state, overrides \\ %{}) do
    struct!(
      %QueueItem{id: "hash", title: "Sample.Show", state: state, protocol: :torrent, status: nil},
      overrides
    )
  end

  describe "of/1 — usenet ladder" do
    test "fetching the NZB is the first step, with no figure" do
      phase = Phase.of(usenet(:fetching_nzb, %{progress: 19.0}))

      assert phase.ladder == [:fetch, :download, :verify, :unpack, :move, :done]
      assert phase.current == :fetch
      assert phase.condition == nil
      assert phase.figure == nil
    end

    test "downloading carries the client's percentage as a 0..1 figure" do
      phase = Phase.of(usenet(:downloading, %{progress: 42.0}))

      assert phase.current == :download
      assert phase.figure == 0.42
    end

    test "post-processing steps read their figure from the stage line" do
      assert %{current: :verify, figure: figure} =
               Phase.of(usenet(:verifying, %{stage_line: "Verifying: 14/56"}))

      assert_in_delta figure, 0.25, 0.001

      assert %{current: :unpack, figure: 0.45} =
               Phase.of(usenet(:extracting, %{stage_line: "Unpacking: 45%"}))

      assert %{current: :move, figure: nil} = Phase.of(usenet(:moving, %{stage_line: nil}))
    end

    test "repair appears on the ladder only while it is happening" do
      phase = Phase.of(usenet(:repairing, %{stage_line: "Repairing: 12%"}))

      assert phase.ladder == [:fetch, :download, :verify, :repair, :unpack, :move, :done]
      assert phase.current == :repair
      assert phase.figure == 0.12
    end

    test "completed is done with a full figure" do
      assert %{current: :done, figure: 1.0} = Phase.of(usenet(:completed, %{progress: 100.0}))
    end

    test "queued and paused are conditions on the download step" do
      assert %{current: :download, condition: :queued} = Phase.of(usenet(:queued))

      assert %{current: :download, condition: :paused, figure: 0.5} =
               Phase.of(usenet(:paused, %{progress: 50.0}))
    end

    test "a failed job has no position and the failed condition" do
      assert %{current: nil, condition: :failed, figure: nil} = Phase.of(usenet(:error))
    end
  end

  describe "of/1 — torrent ladder" do
    test "metadata fetch is the first step, read from the raw status" do
      phase = Phase.of(torrent(:downloading, %{status: "metaDL", progress: 0.0}))

      assert phase.ladder == [:metadata, :download, :done]
      assert phase.current == :metadata
      assert phase.figure == nil
    end

    test "downloading, stalled, queued, paused, done" do
      assert %{current: :download, condition: nil, figure: 0.5} =
               Phase.of(torrent(:downloading, %{status: "downloading", progress: 50.0}))

      assert %{current: :download, condition: :stalled} = Phase.of(torrent(:stalled))
      assert %{current: :download, condition: :queued} = Phase.of(torrent(:queued))
      assert %{current: :download, condition: :paused} = Phase.of(torrent(:paused))
      assert %{current: :done, figure: 1.0} = Phase.of(torrent(:completed, %{progress: 100.0}))
    end

    test "an unknown client state has no position and no condition" do
      assert %{current: nil, condition: nil} = Phase.of(torrent(:other))
    end
  end

  describe "stage line parsing" do
    test "pins the edge cases of the figure parser" do
      figure = fn line -> Phase.of(usenet(:extracting, %{stage_line: line})).figure end

      assert figure.("Verifying: 0/0") == nil
      assert figure.("Verifying: 60/56") == 1.0
      assert figure.("Unpacking: 150%") == 1.0
      assert_in_delta figure.("Repairing: 45.5%"), 0.455, 0.0001
      assert figure.("Running script: notify") == nil
      assert figure.("Verifying: 14/56 blocks") == nil

      assert Phase.of(usenet(:downloading, %{progress: 150.0})).figure == 1.0
    end

    # Observed live 2026-10-12 on a bare-MKV release: SABnzbd's Moving stage
    # names the file it is moving, never a figure, for the whole two-minute
    # move — the indeterminate bar's case, not a parse failure.
    test "the Moving stage names a file, which is no figure" do
      phase = Phase.of(usenet(:moving, %{stage_line: "Moving: a1b2c3d4e5f6.mkv"}))

      assert phase.current == :move
      assert phase.figure == nil
      assert Phase.working?(phase)
    end
  end

  describe "word/1 and text_class/1" do
    test "the condition speaks before the step" do
      assert Phase.word(Phase.of(usenet(:paused))) == "Paused"
      assert Phase.word(Phase.of(torrent(:stalled))) == "Stalled"
      assert Phase.word(Phase.of(usenet(:queued))) == "Queued"
      assert Phase.word(Phase.of(usenet(:error))) == "Failed"
    end

    test "each step has its word" do
      assert Phase.word(Phase.of(usenet(:fetching_nzb))) == "Fetching NZB"
      assert Phase.word(Phase.of(torrent(:downloading, %{status: "metaDL"}))) == "Fetching metadata"
      assert Phase.word(Phase.of(usenet(:downloading))) == "Downloading"
      assert Phase.word(Phase.of(usenet(:verifying))) == "Verifying"
      assert Phase.word(Phase.of(usenet(:repairing))) == "Repairing"
      assert Phase.word(Phase.of(usenet(:extracting))) == "Unpacking"
      assert Phase.word(Phase.of(usenet(:moving))) == "Moving"
      assert Phase.word(Phase.of(usenet(:completed))) == "Done"
      assert Phase.word(Phase.of(torrent(:other))) == "Unknown"
    end

    test "color is signal: calm while working, warning for a held job, error for a failed one" do
      assert Phase.text_class(Phase.of(usenet(:extracting))) == "text-info/80"
      assert Phase.text_class(Phase.of(usenet(:completed))) == "text-success/80"
      assert Phase.text_class(Phase.of(usenet(:queued))) == "text-base-content/55"
      assert Phase.text_class(Phase.of(usenet(:paused))) == "text-warning/80"
      assert Phase.text_class(Phase.of(torrent(:stalled))) == "text-warning/80"
      assert Phase.text_class(Phase.of(usenet(:error))) == "text-error/80"
      assert Phase.text_class(Phase.of(torrent(:other))) == "text-base-content/60"
    end
  end

  describe "working?/1" do
    test "true only for a positioned, unconditioned, unfinished job — what earns an indeterminate bar" do
      assert Phase.working?(Phase.of(usenet(:moving)))
      assert Phase.working?(Phase.of(usenet(:fetching_nzb)))
      refute Phase.working?(Phase.of(usenet(:completed)))
      refute Phase.working?(Phase.of(usenet(:paused)))
      refute Phase.working?(Phase.of(usenet(:error)))
      refute Phase.working?(Phase.of(torrent(:other)))
    end
  end

  describe "step_word/1" do
    test "names a ladder step for a hover label" do
      assert Phase.step_word(:fetch) == "Fetch NZB"
      assert Phase.step_word(:metadata) == "Fetch metadata"
      assert Phase.step_word(:download) == "Download"
      assert Phase.step_word(:verify) == "Verify"
      assert Phase.step_word(:repair) == "Repair"
      assert Phase.step_word(:unpack) == "Unpack"
      assert Phase.step_word(:move) == "Move"
      assert Phase.step_word(:done) == "Done"
    end
  end
end
