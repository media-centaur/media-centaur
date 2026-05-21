defmodule MediaCentarr.Platform.ReleaseArtifactTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Platform.ReleaseArtifact

  # These tests assume the CI runner is Linux x86_64 — the only
  # platform the release pipeline builds for in Phase 3. macOS tag
  # detection is exercised once Phase 5 lands the Darwin impls.

  describe "current_platform_tag/0" do
    test "returns linux-x86_64 on Linux x86_64" do
      # We're on the CI runner (ubuntu-22.04 / x86_64) when this fires.
      assert ReleaseArtifact.current_platform_tag() == "linux-x86_64"
    end
  end

  describe "tarball_filename/1" do
    test "builds the canonical name for a version on Linux" do
      assert ReleaseArtifact.tarball_filename("0.68.1") ==
               "media-centarr-0.68.1-linux-x86_64.tar.gz"
    end

    test "embeds the version verbatim" do
      assert ReleaseArtifact.tarball_filename("9.99.99") ==
               "media-centarr-9.99.99-linux-x86_64.tar.gz"
    end
  end

  describe "tarball_url/2" do
    test "builds the canonical GitHub release URL on Linux" do
      assert ReleaseArtifact.tarball_url("v0.68.1", "0.68.1") ==
               "https://github.com/media-centarr/media-centarr/releases/download/v0.68.1/media-centarr-0.68.1-linux-x86_64.tar.gz"
    end
  end
end
