defmodule MediaCentaur.Review.EventsTest do
  @moduledoc """
  The ADR-060 worked example: `review:updates` has a closed message set,
  so every payload is a struct with `@enforce_keys` and every broadcast
  goes through one chokepoint.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Review.Events
  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.FilesApproved
  alias MediaCentaur.Topics

  setup do
    :ok = Topics.subscribe(Topics.review_updates())
  end

  describe "broadcast/1" do
    test "FileAdded reaches subscribers as a tagged struct" do
      assert :ok = Events.broadcast(%FileAdded{pending_file_id: "file-1"})

      assert_receive {:file_added, %FileAdded{pending_file_id: "file-1"}}
    end

    test "FileReviewed reaches subscribers as a tagged struct" do
      assert :ok = Events.broadcast(%FileReviewed{pending_file_id: "file-2"})

      assert_receive {:file_reviewed, %FileReviewed{pending_file_id: "file-2"}}
    end

    test "FilesApproved carries the approved ids" do
      assert :ok = Events.broadcast(%FilesApproved{pending_file_ids: ["file-1", "file-2"]})

      assert_receive {:files_approved, %FilesApproved{pending_file_ids: ["file-1", "file-2"]}}
    end
  end

  describe "payload construction" do
    test "every event enforces its keys" do
      assert_raise ArgumentError, fn -> struct!(FileAdded, %{}) end
      assert_raise ArgumentError, fn -> struct!(FileReviewed, %{}) end
      assert_raise ArgumentError, fn -> struct!(FilesApproved, %{}) end
    end

    test "subscribers can still map-match, because a struct is a map" do
      Events.broadcast(%FilesApproved{pending_file_ids: ["file-1"]})

      assert_receive {:files_approved, payload}
      assert %{pending_file_ids: ["file-1"]} = payload
    end
  end
end
