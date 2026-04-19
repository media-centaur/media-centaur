defmodule MediaCentarr.SelfUpdate.StagerTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.SelfUpdate.Stager

  @required [
    "bin/media-centarr-install",
    "bin/media_centarr",
    "share/systemd/media-centarr.service",
    "share/defaults/media-centarr.toml"
  ]

  defp tmp_dir(tag) do
    path =
      Path.join(
        System.tmp_dir!(),
        "stager-#{tag}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  # Build a tarball containing the given files (map path -> content).
  defp build_tarball(files, opts \\ []) do
    workdir = tmp_dir("build")
    tarball = Path.join(workdir, "release.tar.gz")

    entries =
      Enum.map(files, fn {path, content} ->
        full = Path.join(workdir, path)
        File.mkdir_p!(Path.dirname(full))
        File.write!(full, content)

        mode = Keyword.get(opts, :mode, 0o644)
        File.chmod!(full, mode)
        {String.to_charlist(path), String.to_charlist(full)}
      end)

    :ok = :erl_tar.create(String.to_charlist(tarball), entries, [:compressed])
    tarball
  end

  describe "validate_entries/2 — pure path + type safety" do
    test "accepts regular files and directories under relative paths" do
      entries = [
        {~c"bin/foo", :regular, 100, 0, 0o755, 0, 0},
        {~c"share/", :directory, 0, 0, 0o755, 0, 0}
      ]

      assert :ok = Stager.validate_entries(entries, 1_000_000)
    end

    test "rejects absolute paths" do
      entries = [{~c"/etc/passwd", :regular, 100, 0, 0o644, 0, 0}]
      assert {:error, :absolute_path} = Stager.validate_entries(entries, 1_000_000)
    end

    test "rejects paths with .. segments" do
      entries = [{~c"../escape.txt", :regular, 10, 0, 0o644, 0, 0}]
      assert {:error, :path_traversal} = Stager.validate_entries(entries, 1_000_000)
    end

    test "rejects paths with nested .. segments" do
      entries = [{~c"good/dir/../../escape.txt", :regular, 10, 0, 0o644, 0, 0}]
      assert {:error, :path_traversal} = Stager.validate_entries(entries, 1_000_000)
    end

    test "rejects symlinks" do
      entries = [{~c"link", :symlink, 0, 0, 0o777, 0, 0}]
      assert {:error, :symlink} = Stager.validate_entries(entries, 1_000_000)
    end

    test "rejects device files, FIFOs, and other non-regular types" do
      for type <- [:block_device, :character_device, :fifo, :other] do
        entries = [{~c"evil", type, 0, 0, 0o644, 0, 0}]
        assert {:error, :non_regular_file} = Stager.validate_entries(entries, 1_000_000)
      end
    end

    test "rejects when cumulative size exceeds the cap" do
      entries = [
        {~c"a", :regular, 400_000, 0, 0o644, 0, 0},
        {~c"b", :regular, 700_000, 0, 0o644, 0, 0}
      ]

      assert {:error, :oversized} = Stager.validate_entries(entries, 1_000_000)
    end
  end

  describe "extract/3 — happy path" do
    test "extracts a valid tarball, returns the target dir, and the required files exist" do
      target = tmp_dir("extract")
      File.rm_rf!(target)

      tarball =
        build_tarball(
          Enum.map(@required, fn path -> {path, "stub"} end) ++
            [{"share/defaults/media-centarr.service", "stub"}]
        )

      assert {:ok, ^target} = Stager.extract(tarball, target)
      assert File.exists?(Path.join(target, "bin/media-centarr-install"))
      assert File.exists?(Path.join(target, "bin/media_centarr"))
      assert File.exists?(Path.join(target, "share/systemd/media-centarr.service"))
      assert File.exists?(Path.join(target, "share/defaults/media-centarr.toml"))
    end

    test "creates the target dir with 0o700 permissions" do
      target = tmp_dir("perms")
      File.rm_rf!(target)

      tarball = build_tarball(Enum.map(@required, fn path -> {path, "stub"} end))

      {:ok, ^target} = Stager.extract(tarball, target)

      %File.Stat{mode: mode} = File.stat!(target)
      # Extract the permission bits — ignore the file-type high bits.
      assert Bitwise.band(mode, 0o777) == 0o700
    end

    # Regression: the real Updater pipeline writes the tarball INTO the
    # staging dir (via Downloader.target_dir) and then asks the Stager to
    # extract INTO that same dir. An earlier Stager implementation did
    # `File.rm_rf!(target_dir)` during prepare_staging — which deleted the
    # very tarball it was about to read, producing `{:tar_error, {path, :enoent}}`.
    test "extracts successfully when the tarball lives inside target_dir" do
      target = tmp_dir("inside")
      File.mkdir_p!(target)

      # Build a fixture tarball externally, then drop it INTO target before
      # calling extract — mimics the real Downloader → Stager handoff.
      external_tarball =
        build_tarball(Enum.map(@required, fn path -> {path, "stub"} end))

      tarball_in_target = Path.join(target, "media-centarr-9.9.9-linux-x86_64.tar.gz")
      File.cp!(external_tarball, tarball_in_target)

      assert {:ok, ^target} = Stager.extract(tarball_in_target, target)
      assert File.exists?(Path.join(target, "bin/media-centarr-install"))
      # The tarball itself should still be present — the extract step
      # must not wipe it out before reading.
      assert File.exists?(tarball_in_target)
    end
  end

  describe "extract/3 — failure paths" do
    test "returns {:error, {:missing_required, [...]}} when required files are absent" do
      target = tmp_dir("missing")
      File.rm_rf!(target)

      tarball = build_tarball([{"bin/media_centarr", "stub"}])

      assert {:error, {:missing_required, missing}} = Stager.extract(tarball, target)
      assert "bin/media-centarr-install" in missing
      assert "share/systemd/media-centarr.service" in missing
    end

    test "returns {:error, :path_traversal} when the tarball contains a .. path" do
      target = tmp_dir("traverse")
      File.rm_rf!(target)

      tarball = build_tarball([{"../escape.txt", "bad"}])

      assert {:error, :path_traversal} = Stager.extract(tarball, target)
      # Staging dir is not created on validation failure.
      refute File.exists?(target)
    end

    test "returns {:error, :absolute_path} when the tarball contains an absolute path" do
      target = tmp_dir("abs")
      File.rm_rf!(target)

      tarball = build_tarball([{"/tmp/escape.txt", "bad"}])

      assert {:error, :absolute_path} = Stager.extract(tarball, target)
    end
  end
end
