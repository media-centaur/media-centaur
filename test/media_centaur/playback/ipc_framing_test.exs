defmodule MediaCentaur.Playback.IpcFramingTest do
  @moduledoc """
  Pure-function tests for the mpv JSON-IPC newline framing.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Playback.IpcFraming

  describe "feed/2" do
    test "returns a single complete line and an empty remainder" do
      assert {[~s|{"a":1}|], ""} = IpcFraming.feed("", ~s|{"a":1}\n|)
    end

    test "splits multiple complete lines delivered in one chunk" do
      data = ~s|{"a":1}\n{"b":2}\n|
      assert {[~s|{"a":1}|, ~s|{"b":2}|], ""} = IpcFraming.feed("", data)
    end

    test "carries an unterminated line into the remainder" do
      assert {[], ~s|{"partial"|} = IpcFraming.feed("", ~s|{"partial"|)
    end

    test "reassembles a line split across two feeds (the track-list regression)" do
      # mpv's `track-list` for a file with many subtitle tracks exceeds
      # the socket read buffer and arrives in fragments. Decoding a
      # fragment in isolation raises `Jason.DecodeError`; framing must
      # stitch the fragments back into one line.
      {lines1, buffer1} = IpcFraming.feed("", ~s|{"event":"track-list","da|)
      assert lines1 == []

      {lines2, buffer2} = IpcFraming.feed(buffer1, ~s|ta":[1,2,3]}\n|)
      assert lines2 == [~s|{"event":"track-list","data":[1,2,3]}|]
      assert buffer2 == ""
    end

    test "keeps the trailing partial line after one complete line" do
      assert {[~s|{"a":1}|], ~s|{"b|} = IpcFraming.feed("", ~s|{"a":1}\n{"b|)
    end

    test "prepends a carried buffer to the next chunk" do
      assert {[~s|{"a":1}|], ""} = IpcFraming.feed(~s|{"a|, ~s|":1}\n|)
    end
  end
end
