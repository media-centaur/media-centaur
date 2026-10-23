defmodule MediaCentaur.Playback.ChainTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.{Chain, Entry, FakeTransport, MpvProperties}

  defp entry(fields), do: struct!(%Entry{entity_id: "entity", content_url: "/media/a.mkv"}, fields)

  describe "queue_next?/4" do
    setup do
      %{
        entry: entry(episode_id: "ep-1"),
        attached: %FakeTransport{owner: self(), attached?: true},
        tail: %MpvProperties{playlist_count: 1, playlist_pos: 0}
      }
    end

    test "queues while the current entry is the playlist's last", context do
      assert Chain.queue_next?(nil, context.entry, context.tail, context.attached)
    end

    test "does not queue when a successor is already pending", context do
      refute Chain.queue_next?(entry(episode_id: "ep-2"), context.entry, context.tail, context.attached)
    end

    test "does not queue when the current entry is not the playlist tail", context do
      mid = %MpvProperties{playlist_count: 3, playlist_pos: 1}
      refute Chain.queue_next?(nil, context.entry, mid, context.attached)
    end

    test "does not queue while the transport is detached", context do
      detached = %FakeTransport{owner: self(), attached?: false}
      refute Chain.queue_next?(nil, context.entry, context.tail, detached)
    end

    test "does not queue for an entry that is not an episode", context do
      refute Chain.queue_next?(nil, entry(movie_id: "movie-1"), context.tail, context.attached)
    end
  end

  describe "advance/3" do
    test "lands on the pending entry when the path is its file" do
      pending = entry(episode_id: "ep-2", content_url: "/media/b.mkv")
      assert Chain.advance(pending, "entity", "/media/b.mkv") == {:ok, pending}
    end
  end
end
