defmodule MediaCentaur.Downloads.WiringTest do
  @moduledoc """
  The wiring file `prowlarr-stack` writes: read and validated whole, compared
  with the saved connection settings into a proposal, saved on accept, and a
  declined wiring stays declined until its values change.
  """

  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Downloads.Wiring
  alias MediaCentaur.Downloads.Wiring.Proposal
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings.Config

  @moduletag :tmp_dir

  @wiring %{
    "format" => 1,
    "stack_version" => "1.5.0",
    "prowlarr" => %{"url" => "http://127.0.0.1:9696", "api_key" => "prowlarr-key"},
    "torrent" => %{
      "type" => "qbittorrent",
      "url" => "http://127.0.0.1:8080",
      "username" => "admin",
      "password" => "torrent-password"
    },
    "usenet" => %{"type" => "sabnzbd", "url" => "http://127.0.0.1:8085", "api_key" => "usenet-key"},
    "completed_dir" => "/mnt/videos/completed"
  }

  setup %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "wiring.json")
    Application.put_env(:media_centaur, :stack_wiring_path, path)

    for key <- [
          :prowlarr_url,
          :prowlarr_api_key,
          :download_client_type,
          :download_client_url,
          :download_client_username,
          :download_client_password,
          :usenet_download_client_type,
          :usenet_download_client_url,
          :usenet_download_client_api_key
        ],
        do: Config.update(key, nil)

    %{path: path}
  end

  defp write(path, wiring), do: File.write!(path, JSON.encode!(wiring))

  describe "read/1" do
    test "no file is no wiring", %{path: path} do
      assert Wiring.read(path) == :absent
    end

    test "reads format 1 with every credential wrapped", %{path: path} do
      write(path, @wiring)

      assert {:ok, %Wiring{} = wiring} = Wiring.read(path)
      assert wiring.prowlarr.url == "http://127.0.0.1:9696"
      assert Secret.expose(wiring.prowlarr.api_key) == "prowlarr-key"
      assert wiring.torrent.username == "admin"
      assert Secret.expose(wiring.torrent.password) == "torrent-password"
      assert Secret.expose(wiring.usenet.api_key) == "usenet-key"
      assert wiring.completed_dir == "/mnt/videos/completed"
      refute inspect(wiring) =~ "prowlarr-key"
    end

    test "a slot the stack left out is absent", %{path: path} do
      write(path, Map.delete(@wiring, "usenet"))

      assert {:ok, %Wiring{usenet: nil, torrent: %{}}} = Wiring.read(path)
    end

    test "a format this version does not know is an error", %{path: path} do
      write(path, %{@wiring | "format" => 2})

      assert Wiring.read(path) == {:error, {:unknown_format, 2}}
    end

    test "a file that is not the document is malformed", %{path: path} do
      File.write!(path, "not json")
      assert Wiring.read(path) == {:error, :malformed}

      write(path, Map.delete(@wiring, "prowlarr"))
      assert Wiring.read(path) == {:error, :malformed}
    end

    test "a client type without a driver refuses the whole wiring", %{path: path} do
      write(path, put_in(@wiring, ["torrent", "type"], "otherclient"))

      assert Wiring.read(path) == {:error, {:unsupported_client, "otherclient"}}
    end

    test "a client type in the other protocol's slot is refused", %{path: path} do
      write(path, put_in(@wiring, ["torrent", "type"], "sabnzbd"))

      assert Wiring.read(path) == {:error, {:unsupported_client, "sabnzbd"}}
    end

    test "a file another user can write is refused", %{path: path} do
      write(path, @wiring)
      File.chmod!(path, 0o666)

      assert Wiring.read(path) == {:error, :writable_by_others}
    end
  end

  describe "proposal/0" do
    test "none without a file" do
      assert Wiring.proposal() == :none
    end

    test "every connection is new on an install with nothing saved", %{path: path} do
      write(path, @wiring)

      assert {:proposal, %Proposal{} = proposal} = Wiring.proposal()

      assert [
               %{id: :prowlarr, url: "http://127.0.0.1:9696", new?: true},
               %{id: :download_client, url: "http://127.0.0.1:8080", new?: true},
               %{id: :usenet_download_client, url: "http://127.0.0.1:8085", new?: true}
             ] = proposal.connections

      assert proposal.completed_dir == "/mnt/videos/completed"
    end

    test "names only the connections and fields that differ", %{path: path} do
      write(path, @wiring)
      {:ok, _subjects} = accept_current()
      write(path, put_in(@wiring, ["usenet", "api_key"], "regenerated"))

      assert {:proposal, proposal} = Wiring.proposal()

      assert [%{id: :usenet_download_client, new?: false, changes: [:usenet_download_client_api_key]}] =
               proposal.connections
    end

    test "none when the saved settings already match", %{path: path} do
      write(path, @wiring)
      {:ok, _subjects} = accept_current()

      assert Wiring.proposal() == :none
    end

    test "says whether the completed directory is inside a media directory", %{path: path} do
      write(path, @wiring)

      assert {:proposal, %Proposal{completed_dir_watched?: false}} = Wiring.proposal()

      :persistent_term.put(
        {Config, :config},
        Map.put(:persistent_term.get({Config, :config}), :media_dirs, ["/mnt/videos"])
      )

      assert {:proposal, %Proposal{completed_dir_watched?: true}} = Wiring.proposal()
    end

    test "reports a wiring it cannot read", %{path: path} do
      write(path, %{@wiring | "format" => 9})

      assert Wiring.proposal() == {:error, {:unknown_format, 9}}
    end
  end

  describe "accept/1" do
    test "saves Prowlarr and both slots and names what it saved", %{path: path} do
      write(path, @wiring)
      {:proposal, proposal} = Wiring.proposal()

      assert Wiring.accept(proposal.digest) ==
               {:ok, [:prowlarr, :download_client, :usenet_download_client]}

      assert Config.get(:prowlarr_url) == "http://127.0.0.1:9696"
      assert Secret.expose(Config.get(:prowlarr_api_key)) == "prowlarr-key"
      assert Config.get(:download_client_type) == "qbittorrent"
      assert Config.get(:download_client_username) == "admin"
      assert Secret.expose(Config.get(:download_client_password)) == "torrent-password"
      assert Config.get(:usenet_download_client_url) == "http://127.0.0.1:8085"
      assert Capabilities.configured?(:usenet_download_client)
    end

    test "refuses a file that changed since the proposal was shown", %{path: path} do
      write(path, @wiring)
      {:proposal, proposal} = Wiring.proposal()
      write(path, put_in(@wiring, ["prowlarr", "url"], "http://127.0.0.1:9999"))

      assert Wiring.accept(proposal.digest) == :stale
      assert Config.get(:prowlarr_url) == nil
    end

    test "leaves alone a slot the wiring does not carry", %{path: path} do
      Config.update(:usenet_download_client_type, "sabnzbd")
      Config.update(:usenet_download_client_url, "http://own.example:8085")
      write(path, Map.delete(@wiring, "usenet"))
      {:proposal, proposal} = Wiring.proposal()

      assert Wiring.accept(proposal.digest) == {:ok, [:prowlarr, :download_client]}
      assert Config.get(:usenet_download_client_url) == "http://own.example:8085"
    end
  end

  describe "decline/1" do
    test "a declined wiring is not proposed again until a value changes", %{path: path} do
      write(path, @wiring)
      {:proposal, proposal} = Wiring.proposal()

      assert Wiring.decline(proposal.digest) == :ok
      assert Wiring.proposal() == :none

      write(path, %{@wiring | "stack_version" => "1.6.0"})
      assert Wiring.proposal() == :none

      write(path, put_in(@wiring, ["prowlarr", "api_key"], "regenerated"))
      assert {:proposal, _proposal} = Wiring.proposal()
    end
  end

  test "an instance in showcase mode reads no wiring", %{path: path} do
    write(path, @wiring)

    :persistent_term.put(
      {Config, :config},
      Map.put(:persistent_term.get({Config, :config}), :showcase_mode, true)
    )

    assert Wiring.proposal() == :none
  end

  describe "completed_dir_status/0" do
    defp watch(media_dirs) do
      :persistent_term.put(
        {Config, :config},
        Map.put(:persistent_term.get({Config, :config}), :media_dirs, media_dirs)
      )
    end

    defp write_with_completed_dir(path, dir) do
      write(path, Map.put(@wiring, "completed_dir", dir))
    end

    test "ok without a wiring file" do
      assert Wiring.completed_dir_status() == :ok
    end

    test "ok while the wiring is only proposed, not in use", %{path: path, tmp_dir: tmp_dir} do
      write_with_completed_dir(path, Path.join(tmp_dir, "absent"))

      assert Wiring.completed_dir_status() == :ok
    end

    test "ok when the directory exists inside a media directory", %{path: path, tmp_dir: tmp_dir} do
      completed = Path.join(tmp_dir, "completed")
      File.mkdir_p!(completed)
      watch([tmp_dir])
      write_with_completed_dir(path, completed)
      {:ok, _subjects} = accept_current()

      assert Wiring.completed_dir_status() == :ok
    end

    test "missing when the directory does not exist", %{path: path, tmp_dir: tmp_dir} do
      completed = Path.join(tmp_dir, "completed")
      watch([tmp_dir])
      write_with_completed_dir(path, completed)
      {:ok, _subjects} = accept_current()

      assert Wiring.completed_dir_status() == {:missing, completed}
    end

    test "not watched when the directory is outside every media directory", %{
      path: path,
      tmp_dir: tmp_dir
    } do
      completed = Path.join(tmp_dir, "completed")
      File.mkdir_p!(completed)
      watch([Path.join(tmp_dir, "library")])
      write_with_completed_dir(path, completed)
      {:ok, _subjects} = accept_current()

      assert Wiring.completed_dir_status() == {:not_watched, completed}
    end
  end

  defp accept_current do
    {:proposal, proposal} = Wiring.proposal()
    Wiring.accept(proposal.digest)
  end
end
