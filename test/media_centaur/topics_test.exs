defmodule MediaCentaur.TopicsTest do
  @moduledoc """
  The transport seam introduced by ADR-060. `Topics` owns the PubSub
  server name so no other module has to know it.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Topics

  describe "publish/2 and subscribe/1" do
    test "a subscriber receives a message published on the same topic" do
      :ok = Topics.subscribe(Topics.review_updates())

      assert :ok = Topics.publish(Topics.review_updates(), {:file_added, "abc"})

      assert_receive {:file_added, "abc"}
    end

    test "a subscriber does not receive messages published on other topics" do
      :ok = Topics.subscribe(Topics.review_updates())

      assert :ok = Topics.publish(Topics.settings_updates(), {:setting_changed, "theme"})

      refute_receive {:setting_changed, _}, 50
    end

    test "publishing to a topic with no subscribers succeeds" do
      assert :ok = Topics.publish(Topics.console_logs(), {:log, "nobody is listening"})
    end
  end

  describe "unsubscribe/1" do
    test "stops delivery of subsequent messages" do
      :ok = Topics.subscribe(Topics.review_updates())
      :ok = Topics.unsubscribe(Topics.review_updates())

      :ok = Topics.publish(Topics.review_updates(), {:file_added, "abc"})

      refute_receive {:file_added, _}, 50
    end
  end
end
