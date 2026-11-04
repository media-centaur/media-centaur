defmodule MediaCentaurWeb.Live.ReviewFlowTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, own_person: 0]

  alias MediaCentaurWeb.Live.ReviewFlow

  @connected %{"wss://a" => %{state: :connected}, "wss://b" => %{state: :connecting}}
  @none_connected %{"wss://a" => %{state: :connecting}}

  describe "audience_line/2" do
    test "names the people who will see it when a relay is connected; the reader is not an audience" do
      people = [person("Nick"), own_person(), person("Sam")]
      assert ReviewFlow.audience_line(people, @connected) == "Nick and Sam will see it"
    end

    test "nothing when a relay is connected but no one is followed" do
      assert ReviewFlow.audience_line([own_person()], @connected) == nil
    end

    test "relays configured, none connected" do
      assert ReviewFlow.audience_line([person("Nick")], @none_connected) ==
               "Friends see it once a relay connects"
    end

    test "no relay configured" do
      assert ReviewFlow.audience_line([person("Nick")], %{}) == "Add a relay in Settings to share it"
    end
  end

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
