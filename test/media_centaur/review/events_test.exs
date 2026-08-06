defmodule MediaCentaur.Review.EventsTest do
  @moduledoc """
  The ADR-060 worked example: `review:updates` has a closed message set,
  so every payload is a struct with `@enforce_keys` and every broadcast
  goes through one chokepoint.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Review.Events
  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.GroupApproved
  alias MediaCentaur.Review.Events.GroupError
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

    test "GroupApproved carries the key and the count" do
      assert :ok = Events.broadcast(%GroupApproved{group_key: "group-1", count: 3})

      assert_receive {:group_approved, %GroupApproved{group_key: "group-1", count: 3}}
    end

    test "GroupError carries the key and the message" do
      assert :ok = Events.broadcast(%GroupError{group_key: "group-1", message: "boom"})

      assert_receive {:group_error, %GroupError{group_key: "group-1", message: "boom"}}
    end
  end

  describe "payload construction" do
    test "every event enforces its keys" do
      assert_raise ArgumentError, fn -> struct!(FileAdded, %{}) end
      assert_raise ArgumentError, fn -> struct!(FileReviewed, %{}) end
      assert_raise ArgumentError, fn -> struct!(GroupApproved, %{group_key: "k"}) end
      assert_raise ArgumentError, fn -> struct!(GroupError, %{group_key: "k"}) end
    end

    test "subscribers can still map-match, because a struct is a map" do
      Events.broadcast(%GroupApproved{group_key: "group-1", count: 3})

      assert_receive {:group_approved, payload}
      assert %{group_key: "group-1", count: 3} = payload
    end
  end
end
