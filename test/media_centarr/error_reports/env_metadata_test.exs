defmodule MediaCentarr.ErrorReports.EnvMetadataTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ErrorReports.EnvMetadata

  describe "collect/0" do
    test "returns a map with required keys" do
      meta = EnvMetadata.collect()
      assert is_binary(meta.app_version)
      assert is_binary(meta.otp_release)
      assert is_binary(meta.elixir_version)
      assert is_binary(meta.os)
      assert is_binary(meta.locale)
      assert is_binary(meta.uptime)
    end

    test "app_version matches the running app spec" do
      assert EnvMetadata.collect().app_version == to_string(Application.spec(:media_centarr, :vsn))
    end

    test "uptime format is human readable (e.g. '2h 14m')" do
      assert EnvMetadata.collect().uptime =~ ~r/^\d+[dhms]/
    end
  end

  describe "render/1" do
    test "emits a fixed-column text block" do
      rendered =
        EnvMetadata.render(%{
          app_version: "0.21.0",
          otp_release: "27",
          elixir_version: "1.17.0",
          os: "Linux 6.19.12-arch1-1 (x86_64)",
          locale: "en_US.UTF-8",
          uptime: "2h 14m"
        })

      assert rendered =~ "App:"
      assert rendered =~ "0.21.0"
      assert rendered =~ "Erlang:"
      assert rendered =~ "OS:"
      assert rendered =~ "Uptime:"
    end
  end
end
