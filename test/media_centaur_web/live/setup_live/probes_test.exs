defmodule MediaCentaurWeb.Live.SetupLive.ProbesTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Live.SetupLive.Probe
  alias MediaCentaurWeb.Live.SetupLive.Probes

  describe "tmdb/1" do
    test "ok when api key configured" do
      assert %Probe.Result{
               id: :tmdb,
               status: :ok,
               critical?: true
             } = Probes.tmdb(%{tmdb_api_key_configured?: true})
    end

    test "not_configured when api key missing" do
      assert %Probe.Result{
               id: :tmdb,
               status: :not_configured,
               critical?: true
             } = Probes.tmdb(%{tmdb_api_key_configured?: false})
    end
  end

  describe "mpv/1" do
    test "ok when configured path is an executable file" do
      tmp = make_executable!()
      result = Probes.mpv(%{mpv_path: tmp.path})

      assert %Probe.Result{
               id: :mpv,
               status: :ok,
               current_value: path,
               critical?: false
             } = result

      assert path == tmp.path
    end

    test "error when path is missing" do
      assert %Probe.Result{id: :mpv, status: :error} =
               Probes.mpv(%{mpv_path: "/nonexistent/path/mpv"})
    end

    test "error with detected_candidates when path missing but mpv is on the system" do
      tmp = make_executable!()

      result =
        Probes.mpv(%{
          mpv_path: "/nonexistent/path/mpv",
          binary_paths: [Path.dirname(tmp.path)],
          binary_name_override: Path.basename(tmp.path)
        })

      assert result.status == :error
      assert tmp.path in result.detected_candidates
    end

    test "not_configured when path is nil" do
      assert %Probe.Result{id: :mpv, status: :not_configured} =
               Probes.mpv(%{mpv_path: nil})
    end
  end

  describe "ffprobe/1" do
    test "ok when configured path is an executable file" do
      tmp = make_executable!()

      assert %Probe.Result{id: :ffprobe, status: :ok, current_value: path} =
               Probes.ffprobe(%{ffprobe_path: tmp.path})

      assert path == tmp.path
    end

    test "error when path is missing" do
      assert %Probe.Result{id: :ffprobe, status: :error} =
               Probes.ffprobe(%{ffprobe_path: "/nonexistent/ffprobe"})
    end

    test "ffprobe is not critical" do
      assert %Probe.Result{critical?: false} =
               Probes.ffprobe(%{ffprobe_path: nil})
    end
  end

  describe "prowlarr/1" do
    test "ok when api key configured" do
      assert %Probe.Result{id: :prowlarr, status: :ok, critical?: false} =
               Probes.prowlarr(%{prowlarr_api_key_configured?: true})
    end

    test "not_configured when api key missing" do
      assert %Probe.Result{id: :prowlarr, status: :not_configured} =
               Probes.prowlarr(%{prowlarr_api_key_configured?: false})
    end
  end

  describe "download_client/1" do
    test "ok when password configured" do
      assert %Probe.Result{id: :download_client, status: :ok, critical?: false} =
               Probes.download_client(%{download_client_password_configured?: true})
    end

    test "not_configured when password missing" do
      assert %Probe.Result{id: :download_client, status: :not_configured} =
               Probes.download_client(%{download_client_password_configured?: false})
    end
  end

  describe "media_dirs/1" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "probes_watch_#{Ecto.UUID.generate()}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{tmp: tmp}
    end

    test "not_configured when no entries" do
      assert %Probe.Result{
               id: :media_dirs,
               status: :not_configured,
               critical?: true
             } = Probes.media_dirs([])
    end

    test "ok when all configured dirs exist", %{tmp: tmp} do
      entries = [%{"dir" => tmp}]

      assert %Probe.Result{id: :media_dirs, status: :ok, current_value: ^entries} =
               Probes.media_dirs(entries)
    end

    test "warning when some dirs are missing", %{tmp: tmp} do
      entries = [
        %{"dir" => tmp},
        %{"dir" => "/nonexistent/wherever"}
      ]

      assert %Probe.Result{id: :media_dirs, status: :warning} = Probes.media_dirs(entries)
    end

    test "error when all configured dirs are missing" do
      entries = [%{"dir" => "/nope/a"}, %{"dir" => "/nope/b"}]
      assert %Probe.Result{id: :media_dirs, status: :error} = Probes.media_dirs(entries)
    end
  end

  describe "all/1" do
    test "returns a list of Probe.Result structs in step order" do
      input = %{
        tmdb_api_key_configured?: false,
        mpv_path: nil,
        ffprobe_path: nil,
        prowlarr_api_key_configured?: false,
        download_client_password_configured?: false,
        media_dirs_entries: []
      }

      results = Probes.all(input)
      ids = Enum.map(results, & &1.id)

      assert ids == [:media_dirs, :tmdb, :mpv, :ffprobe, :prowlarr, :download_client]
      assert Enum.all?(results, &match?(%Probe.Result{}, &1))
    end
  end

  # ---- helpers ----

  defp make_executable! do
    tmp_dir = Path.join(System.tmp_dir!(), "probes_bin_#{Ecto.UUID.generate()}")
    File.mkdir_p!(tmp_dir)
    path = Path.join(tmp_dir, "fake-bin-#{Ecto.UUID.generate()}")
    File.write!(path, "#!/bin/sh\nexit 0\n")
    File.chmod!(path, 0o755)

    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{path: path, dir: tmp_dir}
  end
end
