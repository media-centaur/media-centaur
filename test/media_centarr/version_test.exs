defmodule MediaCentarr.VersionTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Version

  describe "current_version/0" do
    test "returns the mix.exs version as a string" do
      version = Version.current_version()
      assert is_binary(version)
      assert Version.compare_versions(version, "0.0.0") == :gt
    end
  end

  describe "build_info/0" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "build_info_#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(tmp) end)
      {:ok, path: tmp}
    end

    test "returns :dev_build when the build info file is missing", %{path: path} do
      assert Version.build_info(path) == :dev_build
    end

    test "returns parsed metadata when the build info file exists", %{path: path} do
      File.write!(
        path,
        JSON.encode!(%{
          "version" => "0.4.0",
          "built_at" => "2026-04-17T12:34:56Z",
          "git_sha" => "abc1234"
        })
      )

      assert {:ok, info} = Version.build_info(path)
      assert info.version == "0.4.0"
      assert info.git_sha == "abc1234"
      assert %DateTime{} = info.built_at
      assert DateTime.to_iso8601(info.built_at) == "2026-04-17T12:34:56Z"
    end

    test "returns :dev_build when the file is malformed", %{path: path} do
      File.write!(path, "not json at all")
      assert Version.build_info(path) == :dev_build
    end

    test "returns :dev_build when required fields are missing", %{path: path} do
      File.write!(path, JSON.encode!(%{"version" => "0.4.0"}))
      assert Version.build_info(path) == :dev_build
    end
  end

  describe "compare_versions/2" do
    test "returns :gt when remote is newer" do
      assert Version.compare_versions("0.5.0", "0.4.0") == :gt
    end

    test "returns :eq when versions match" do
      assert Version.compare_versions("0.4.0", "0.4.0") == :eq
    end

    test "returns :lt when remote is older" do
      assert Version.compare_versions("0.3.0", "0.4.0") == :lt
    end

    test "strips a leading v from either argument" do
      assert Version.compare_versions("v0.5.0", "0.4.0") == :gt
      assert Version.compare_versions("0.5.0", "v0.4.0") == :gt
    end

    test "returns :error on an unparseable version" do
      assert Version.compare_versions("garbage", "0.4.0") == :error
    end
  end
end
