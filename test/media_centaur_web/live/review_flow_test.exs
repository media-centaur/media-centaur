defmodule MediaCentaurWeb.Live.ReviewFlowTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Live.ReviewFlow

  describe "counter/1" do
    test "blank while more than 100 remain, then the count" do
      assert ReviewFlow.counter("") == nil
      assert ReviewFlow.counter(String.duplicate("x", 399)) == nil
      assert ReviewFlow.counter(String.duplicate("x", 400)) == "100 left"
      assert ReviewFlow.counter(String.duplicate("x", 500)) == "0 left"
    end
  end

  describe "sent_message/2" do
    test "new, updated, and saved for later" do
      assert ReviewFlow.sent_message(false, {1, 2}) == "Review shared with your friends"
      assert ReviewFlow.sent_message(true, {1, 2}) == "Review updated"
      assert ReviewFlow.sent_message(false, {0, 2}) == "Saved — it shares when a relay connects"
      assert ReviewFlow.sent_message(true, {0, 0}) == "Saved — it shares when a relay connects"
    end
  end
end
