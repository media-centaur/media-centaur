defmodule Mix.Tasks.Social.DevTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @moduletag :capture_log
  @moduletag :tmp_dir

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.FakeRelay
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Recommendations.Translation
  alias MediaCentaur.TMDB.Title
  alias Mix.Tasks.Social.Dev

  @other_secret MediaCentaur.Secret.wrap(String.duplicate("0", 63) <> "7")

  defp run(args, tmp_dir, relay \\ nil) do
    relay_args = if relay, do: ["--relay", relay.url], else: []
    capture_io(fn -> Dev.run(args ++ ["--dir", tmp_dir] ++ relay_args) end)
  end

  defp stored_recommendation(name, note) do
    title = Title.new!(%{tmdb_id: 42, media_type: :movie, name: name})

    title
    |> Translation.to_event(note, Keys.pubkey(@other_secret))
    |> Event.sign(@other_secret)
  end

  describe "npub" do
    test "prints the friend's npub and nothing else, and keeps it across runs", %{tmp_dir: tmp_dir} do
      first = run(["npub"], tmp_dir)
      second = run(["npub"], tmp_dir)

      assert first == second
      assert {:ok, _pubkey} = first |> String.trim() |> Keys.from_npub()
      assert String.trim(first) == first |> String.split("\n", trim: true) |> List.first()
      assert File.exists?(Path.join(tmp_dir, "friend.nsec"))
    end
  end

  describe "recommend" do
    test "publishes a signed kind 32160 event the app can translate", %{tmp_dir: tmp_dir} do
      relay = FakeRelay.start(auth: true)

      output =
        run(
          ["recommend", "movie", "603", "--name", "Sample Movie", "--note", "try it", "--year", "1999"],
          tmp_dir,
          relay
        )

      assert output =~ "Published tmdb:movie:603"

      assert_received {:relay_in, ["EVENT", event_map]}
      assert {:ok, event} = Event.from_map(event_map)
      assert :ok = Event.verify(event)

      assert {:ok, attrs} = Translation.from_event(event)
      assert attrs.tmdb_id == 603
      assert attrs.media_type == :movie
      assert attrs.title.name == "Sample Movie"
      assert attrs.title.year == "1999"
      assert attrs.note == "try it"

      friend_npub = tmp_dir |> then(&run(["npub"], &1)) |> String.trim()
      assert Keys.to_npub(event.pubkey) == friend_npub
    end

    test "fails with the relay's reason when refused", %{tmp_dir: tmp_dir} do
      relay =
        FakeRelay.start(accept: false, reason: "restricted: this key is not a member of this relay")

      assert_raise Mix.Error, ~r/restricted: this key is not a member of this relay/, fn ->
        run(["recommend", "movie", "603", "--name", "Sample Movie"], tmp_dir, relay)
      end
    end

    test "prints usage when the name is missing", %{tmp_dir: tmp_dir} do
      assert_raise Mix.Error, ~r/--name/, fn -> run(["recommend", "movie", "603"], tmp_dir) end
    end

    test "rejects an unknown media type", %{tmp_dir: tmp_dir} do
      assert_raise Mix.Error, ~r/movie or tv_series/, fn ->
        run(["recommend", "series", "603", "--name", "Sample Show"], tmp_dir)
      end
    end
  end

  describe "delete" do
    test "publishes a signed kind 5 for the friend's own address", %{tmp_dir: tmp_dir} do
      relay = FakeRelay.start(auth: true)

      output = run(["delete", "movie", "603"], tmp_dir, relay)
      assert output =~ "Withdrew tmdb:movie:603"

      assert_received {:relay_in, ["EVENT", event_map]}
      assert {:ok, event} = Event.from_map(event_map)
      assert :ok = Event.verify(event)
      assert {:ok, attrs} = Translation.from_deletion(event)
      assert attrs.tmdb_id == 603
      assert attrs.media_type == :movie
      assert Keys.to_npub(attrs.author_pubkey) == String.trim(run(["npub"], tmp_dir))
    end

    test "fails with the relay's reason when refused", %{tmp_dir: tmp_dir} do
      relay = FakeRelay.start(accept: false, reason: "blocked: kind 5 is not stored by this relay")

      assert_raise Mix.Error, ~r/blocked: kind 5 is not stored by this relay/, fn ->
        run(["delete", "movie", "603"], tmp_dir, relay)
      end
    end
  end

  describe "feed" do
    test "prints a deletion as a withdrawn address", %{tmp_dir: tmp_dir} do
      deletion =
        @other_secret
        |> Keys.pubkey()
        |> Translation.to_deletion(:movie, 42, nil)
        |> Event.sign(@other_secret)

      output = run(["feed"], tmp_dir, FakeRelay.start(events: [deletion]))

      assert output =~ "tmdb:movie:42  withdrawn"
    end

    test "prints one line per stored recommendation", %{tmp_dir: tmp_dir} do
      relay =
        FakeRelay.start(
          auth: true,
          events: [stored_recommendation("Movie A", "great"), stored_recommendation("Movie B", nil)]
        )

      output = run(["feed"], tmp_dir, relay)

      assert output =~ "Movie A"
      assert output =~ "great"
      assert output =~ "Movie B"
      assert output =~ "npub1"
    end

    test "labels the friend's own events", %{tmp_dir: tmp_dir} do
      friend_secret = Keys.generate()
      File.write!(Path.join(tmp_dir, "friend.nsec"), Keys.to_nsec(friend_secret))
      title = Title.new!(%{tmdb_id: 603, media_type: :movie, name: "Sample Movie"})

      own =
        title
        |> Translation.to_event(nil, Keys.pubkey(friend_secret))
        |> Event.sign(friend_secret)

      relay = FakeRelay.start(events: [own])

      output = run(["feed"], tmp_dir, relay)

      assert output =~ "friend  tmdb:movie:603"
      assert output =~ "Sample Movie"
    end
  end

  describe "help" do
    test "no arguments prints usage with an example", %{tmp_dir: tmp_dir} do
      output = run([], tmp_dir)

      assert output =~ "mix social.dev recommend movie 603 --name"
      assert output =~ "mix social.dev delete"
      assert output =~ "just social"
    end

    test "an unknown subcommand fails with usage", %{tmp_dir: tmp_dir} do
      assert_raise Mix.Error, ~r/mix social.dev recommend/, fn -> run(["bogus"], tmp_dir) end
    end
  end
end
