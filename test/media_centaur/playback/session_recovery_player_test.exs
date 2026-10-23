defmodule MediaCentaur.Playback.SessionRecoveryPlayerTest do
  @moduledoc """
  Recovery over a player channel: the test process is the channel and
  answers the mpv questions recovery asks, so the resolution from a media
  URL back to an entity and a profile is pinned without a device.
  """

  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Playback.LaunchFlags
  alias MediaCentaur.Playback.Transport.Remote.PlayerRegistry
  alias MediaCentaur.Playback.Transport.Remote

  @base "http://tv.test:2160"

  setup %{tmp_dir: tmp_dir} do
    media_dir = register_media_dir(tmp_dir)
    movie = create_standalone_movie(%{name: "Sample Movie"})
    path = Path.join(media_dir, "Sample.Movie.2010.mkv")
    File.write!(path, "")
    presence = FilePresence.stamp(path, media_dir)

    create_linked_file(%{file_path: path, media_dir: media_dir, movie_id: movie.id})

    media_urls = %{
      for_file: fn presence_id -> "#{@base}/media/#{presence_id}?t=token" end,
      presence_id: fn url ->
        case URI.parse(url) do
          %URI{path: "/media/" <> id} -> id
          _other -> nil
        end
      end
    }

    player_id = Ecto.UUID.generate()
    :ok = PlayerRegistry.register(player_id, media_urls)
    %{player_id: player_id, presence: presence, path: path, movie: movie}
  end

  # The channel's half of recovery: answer each `get_property` the task asks.
  defp answer_properties(answers) do
    receive do
      {:channel, {:request, from, ref, ["get_property", name]}} ->
        send(from, {ref, Map.fetch!(answers, name)})
        answer_properties(answers)
    after
      500 -> :ok
    end
  end

  defp success(data), do: %{"error" => "success", "data" => data}

  @tag :tmp_dir
  test "a player playing one of our files is recovered with its position and profile",
       %{player_id: player_id, presence: presence, path: path, movie: movie} do
    profile_id = MediaCentaur.Profiles.owner().id
    task = Task.async(fn -> Remote.recover(player_id) end)

    answer_properties(%{
      "path" => success("#{@base}/media/#{presence.id}?t=token"),
      "time-pos" => success(1234.5),
      "script-opts" => success(%{LaunchFlags.profile_script_opt() => profile_id})
    })

    assert [params] = Task.await(task)
    assert params.entity_id == movie.id
    assert params.content_url == path
    assert params.start_position == 1234.5
    assert params.profile_id == profile_id
    assert params.reattach? == true
    assert params.movie_id == movie.id
  end

  @tag :tmp_dir
  test "a player playing nothing, or a file that is not ours, is skipped", %{player_id: player_id} do
    task = Task.async(fn -> Remote.recover(player_id) end)
    answer_properties(%{"path" => success(nil)})
    assert Task.await(task) == []

    task = Task.async(fn -> Remote.recover(player_id) end)
    answer_properties(%{"path" => success("http://elsewhere.test/video.mkv")})
    assert Task.await(task) == []
  end

  @tag :tmp_dir
  test "a player whose mpv carries no profile is skipped", %{player_id: player_id, presence: presence} do
    task = Task.async(fn -> Remote.recover(player_id) end)

    answer_properties(%{
      "path" => success("#{@base}/media/#{presence.id}?t=token"),
      "time-pos" => success(10.0),
      "script-opts" => success(%{})
    })

    assert Task.await(task) == []
  end

  @tag :tmp_dir
  test "a player with no channel is skipped" do
    assert Remote.recover(Ecto.UUID.generate()) == []
  end
end
