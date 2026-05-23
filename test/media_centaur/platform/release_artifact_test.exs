defmodule MediaCentaur.Platform.ReleaseArtifactTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Platform.ReleaseArtifact

  # Most tests use injected os_type/arch opts so they exercise the
  # macOS branch from a Linux CI runner. The arity-0 / arity-1
  # default-args variants use the real :os.type/0 and runtime arch.

  describe "current_platform_tag/0 — live (uses real :os.type)" do
    test "returns linux-x86_64 on Linux x86_64" do
      # We're on the CI runner (ubuntu-22.04 / x86_64) when this fires.
      assert ReleaseArtifact.current_platform_tag() == "linux-x86_64"
    end
  end

  describe "current_platform_tag/1 — injected os_type + arch" do
    test "Linux x86_64 returns linux-x86_64" do
      assert ReleaseArtifact.current_platform_tag(
               os_type: {:unix, :linux},
               arch: "x86_64-pc-linux-gnu"
             ) == "linux-x86_64"
    end

    test "macOS Apple Silicon returns darwin-arm64" do
      assert ReleaseArtifact.current_platform_tag(
               os_type: {:unix, :darwin},
               arch: "aarch64-apple-darwin23.4.0"
             ) == "darwin-arm64"
    end

    test "macOS Intel raises (not yet a build target)" do
      assert_raise RuntimeError, ~r/unsupported macOS architecture/, fn ->
        ReleaseArtifact.current_platform_tag(
          os_type: {:unix, :darwin},
          arch: "x86_64-apple-darwin23.4.0"
        )
      end
    end

    test "unsupported Linux arch raises" do
      assert_raise RuntimeError, ~r/unsupported Linux architecture/, fn ->
        ReleaseArtifact.current_platform_tag(
          os_type: {:unix, :linux},
          arch: "armv7l-unknown-linux-gnueabihf"
        )
      end
    end

    test "unsupported OS raises" do
      assert_raise RuntimeError, ~r/unsupported OS/, fn ->
        ReleaseArtifact.current_platform_tag(
          os_type: {:win32, :nt},
          arch: "x86_64-pc-windows-msvc"
        )
      end
    end
  end

  describe "tarball_filename/2 — injected os_type + arch" do
    test "Linux variant" do
      assert ReleaseArtifact.tarball_filename("0.68.1",
               os_type: {:unix, :linux},
               arch: "x86_64-pc-linux-gnu"
             ) == "media-centaur-0.68.1-linux-x86_64.tar.gz"
    end

    test "macOS Apple Silicon variant" do
      assert ReleaseArtifact.tarball_filename("0.68.1",
               os_type: {:unix, :darwin},
               arch: "aarch64-apple-darwin23.4.0"
             ) == "media-centaur-0.68.1-darwin-arm64.tar.gz"
    end
  end

  describe "tarball_url/3 — injected os_type + arch" do
    test "macOS Apple Silicon URL" do
      assert ReleaseArtifact.tarball_url("v0.68.1", "0.68.1",
               os_type: {:unix, :darwin},
               arch: "aarch64-apple-darwin23.4.0"
             ) ==
               "https://github.com/media-centaur/media-centaur/releases/download/v0.68.1/media-centaur-0.68.1-darwin-arm64.tar.gz"
    end
  end

  describe "tarball_filename/1 — live (uses real :os.type)" do
    test "builds the canonical name for a version on Linux" do
      assert ReleaseArtifact.tarball_filename("0.68.1") ==
               "media-centaur-0.68.1-linux-x86_64.tar.gz"
    end

    test "embeds the version verbatim" do
      assert ReleaseArtifact.tarball_filename("9.99.99") ==
               "media-centaur-9.99.99-linux-x86_64.tar.gz"
    end
  end

  describe "tarball_url/2 — live (uses real :os.type)" do
    test "builds the canonical GitHub release URL on Linux" do
      assert ReleaseArtifact.tarball_url("v0.68.1", "0.68.1") ==
               "https://github.com/media-centaur/media-centaur/releases/download/v0.68.1/media-centaur-0.68.1-linux-x86_64.tar.gz"
    end
  end
end
