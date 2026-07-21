defmodule MediaCentaurWeb.LiveHelpersTest do
  use ExUnit.Case, async: true

  import MediaCentaurWeb.LiveHelpers

  describe "safe_existing_atom/2" do
    test "returns the existing atom for a known string" do
      assert safe_existing_atom("error") == :error
    end

    test "returns the default (nil) for an unknown string instead of raising" do
      assert safe_existing_atom("definitely_not_an_atom_zzz") == nil
    end

    test "returns the given default for an unknown string" do
      assert safe_existing_atom("definitely_not_an_atom_zzz", :movie) == :movie
    end
  end

  describe "sized_image_url/2" do
    test "appends a ?w= width hint to a bare URL" do
      assert sized_image_url("/media-images/abc/backdrop.jpg", 480) ==
               "/media-images/abc/backdrop.jpg?w=480"
    end

    test "preserves an existing query (e.g. a ?v= cache-buster) with &" do
      assert sized_image_url("/media-images/abc/backdrop.jpg?v=123", 320) ==
               "/media-images/abc/backdrop.jpg?v=123&w=320"
    end

    test "returns nil for nil so callers can :if on the result" do
      assert sized_image_url(nil, 480) == nil
    end

    test "leaves a remote URL untouched (ImageServer can't resize it)" do
      remote = "https://image.tmdb.org/t/p/w92/abc.jpg"
      assert sized_image_url(remote, 240) == remote
    end
  end

  describe "image_url/2" do
    test "returns local path for content_url" do
      entity = %{images: [%{role: "poster", content_url: "abc/poster.jpg"}]}
      assert image_url(entity, "poster") == "/media-images/abc/poster.jpg"
    end

    test "returns nil when no content_url" do
      entity = %{images: [%{role: "backdrop", content_url: nil}]}

      assert image_url(entity, "backdrop") == nil
    end

    test "returns nil when no image for role" do
      entity = %{images: [%{role: "poster", content_url: "x.jpg"}]}
      assert image_url(entity, "backdrop") == nil
    end

    test "returns nil when images is nil" do
      entity = %{images: nil}
      assert image_url(entity, "poster") == nil
    end

    test "returns nil when the map has no :images key at all" do
      # Regression: `DetailItem.movie_entry_to_map/1` emits movie rows
      # for a movie_series with no `:images` key. `image_url/2`
      # dot-accessed `entity.images`, which raises `KeyError` on a map
      # missing the key (not just a nil value), crashing the entire
      # detail-panel render (HomeLive) the moment a constituent movie
      # row was shown. A render helper must tolerate a missing optional
      # key, not take down the LiveView.
      entity = %{id: "x", name: "Sample Movie", content_url: "y", present?: true}
      assert image_url(entity, "poster") == nil
    end

    test "appends ?v=<updated_at unix> so replaced artwork busts the cache" do
      dt = ~U[2026-05-24 00:00:00Z]
      entity = %{images: [%{role: "poster", content_url: "abc/poster.jpg", updated_at: dt}]}

      assert image_url(entity, "poster") ==
               "/media-images/abc/poster.jpg?v=#{DateTime.to_unix(dt)}"
    end

    test "the URL changes when updated_at changes (re-downloaded artwork)" do
      base = %{role: "poster", content_url: "abc/poster.jpg"}
      before = %{images: [Map.put(base, :updated_at, ~U[2026-05-24 00:00:00Z])]}
      later = %{images: [Map.put(base, :updated_at, ~U[2026-05-24 01:00:00Z])]}

      refute image_url(before, "poster") == image_url(later, "poster")
    end

    test "falls back to a bare URL when the image carries no updated_at" do
      entity = %{images: [%{role: "poster", content_url: "abc/poster.jpg"}]}
      assert image_url(entity, "poster") == "/media-images/abc/poster.jpg"
    end
  end

  describe "time_ago/1" do
    test "returns empty string for nil" do
      assert time_ago(nil) == ""
    end

    test "returns just now for recent timestamps" do
      now = DateTime.utc_now()
      assert time_ago(now) == "just now"
    end

    test "returns minutes ago" do
      minutes_ago = DateTime.add(DateTime.utc_now(), -180, :second)
      assert time_ago(minutes_ago) == "3m ago"
    end

    test "returns hours ago" do
      hours_ago = DateTime.add(DateTime.utc_now(), -7200, :second)
      assert time_ago(hours_ago) == "2h ago"
    end

    test "returns days ago" do
      days_ago = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)
      assert time_ago(days_ago) == "3d ago"
    end

    test "returns formatted date for old timestamps" do
      old = DateTime.new!(~D[2025-01-15], ~T[12:00:00], "Etc/UTC")
      assert time_ago(old) == "Jan 15"
    end

    test "handles NaiveDateTime by converting to UTC" do
      naive = NaiveDateTime.utc_now()
      assert time_ago(naive) == "just now"
    end
  end

  describe "debounce/4" do
    test "schedules a message and stores the timer ref" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, my_timer: nil}}
      result = debounce(socket, :my_timer, :reload, 50)

      assert is_reference(result.assigns.my_timer)
      assert_receive :reload, 200
    end

    test "cancels an existing timer before scheduling a new one" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, my_timer: nil}}
      first = debounce(socket, :my_timer, :reload, 500)

      # Schedule a second debounce that should cancel the first
      second = debounce(first, :my_timer, :reload, 50)

      assert second.assigns.my_timer != first.assigns.my_timer
      # Only the second timer should fire
      assert_receive :reload, 200
      refute_receive :reload, 100
    end
  end

  describe "apply_playback_change/4" do
    test "adds a playing entry to sessions" do
      sessions = %{}
      now_playing = %{title: "Episode 1"}

      result = apply_playback_change(sessions, "entity-1", :playing, now_playing)

      assert result == %{
               "entity-1" => %{state: :playing, now_playing: %{title: "Episode 1"}}
             }
    end

    test "removes an entry on :stopped" do
      sessions = %{"entity-1" => %{state: :playing, now_playing: %{title: "Episode 1"}}}

      result = apply_playback_change(sessions, "entity-1", :stopped, nil)

      assert result == %{}
    end

    test "updates existing entry state" do
      sessions = %{"entity-1" => %{state: :playing, now_playing: %{title: "Episode 1"}}}

      result = apply_playback_change(sessions, "entity-1", :paused, %{title: "Episode 1"})

      assert result == %{
               "entity-1" => %{state: :paused, now_playing: %{title: "Episode 1"}}
             }
    end

    test "merges extra fields when provided" do
      sessions = %{}
      now_playing = %{title: "Episode 1"}
      started_at = ~U[2026-04-06 12:00:00Z]

      result =
        apply_playback_change(sessions, "entity-1", :playing, now_playing, %{
          started_at: started_at
        })

      assert result["entity-1"].started_at == started_at
      assert result["entity-1"].state == :playing
    end
  end

  describe "delete_gesture_state/3" do
    # The lifecycle of one delete button's gesture: idle → confirm
    # (armed, awaiting the second click) → deleting (async delete in
    # flight). `deleting` outranks `delete_confirm` so a button can't
    # claim it's both "click again to confirm" and "deleting". Shared by
    # the entity detail page (`:all | {:file, path} | {:folder, path}`
    # targets) and Review (`{:file, path} | {:folder, path}` targets).

    test "idle when the target is neither armed nor deleting" do
      assert delete_gesture_state(:all, nil, nil) == :idle
    end

    test "confirm when the target is the armed delete_confirm target" do
      assert delete_gesture_state(:all, nil, :all) == :confirm

      assert delete_gesture_state({:file, "/m/a.mkv"}, nil, {:file, "/m/a.mkv"}) ==
               :confirm
    end

    test "deleting when an async delete is in flight for the target" do
      assert delete_gesture_state(:all, :all, nil) == :deleting

      assert delete_gesture_state({:folder, "/m/Show"}, {:folder, "/m/Show"}, nil) ==
               :deleting
    end

    test "deleting outranks a stale confirm on the same target" do
      assert delete_gesture_state(:all, :all, :all) == :deleting
    end

    test "idle for a different target than the one in flight" do
      assert delete_gesture_state(:all, {:file, "/m/a.mkv"}, nil) == :idle
    end
  end

  describe "delete_in_flight?/1" do
    # While any delete is running, every delete button disables so the
    # user can't stack a second destructive op on the busy view.

    test "false when nothing is deleting" do
      refute delete_in_flight?(nil)
    end

    test "true for any in-flight target" do
      assert delete_in_flight?(:all)
      assert delete_in_flight?({:file, "/m/a.mkv"})
      assert delete_in_flight?({:folder, "/m/Show"})
    end
  end
end
