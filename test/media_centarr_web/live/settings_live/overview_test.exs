defmodule MediaCentarrWeb.Live.SettingsLive.OverviewTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Live.SettingsLive.Overview

  @tmp_dir System.tmp_dir!()
  # Any executable present on both dev and CI hosts works for the "mpv binary
  # present" check — Overview calls File.stat on the path and only cares that
  # it exists with an exec bit set. `sh` is guaranteed on every POSIX system.
  @present_executable System.find_executable("sh") || "/bin/sh"

  # Build a minimal input shape matching what SettingsLive hands to
  # `Overview.build/1`. Individual tests override the parts they care about.
  defp input(overrides \\ %{}) do
    defaults = %{
      watchers_running: true,
      pipeline_running: true,
      image_pipeline_running: true,
      acquisition_running: true,
      prowlarr_test: nil,
      download_client_test: nil,
      config: %{
        tmdb_api_key_configured?: true,
        prowlarr_url: "http://localhost:9696",
        prowlarr_api_key_configured?: true,
        download_client_type: "qbittorrent",
        download_client_url: "http://localhost:8080",
        download_client_password_configured?: true,
        mpv_path: @present_executable,
        mpv_socket_dir: @tmp_dir,
        database_path: Path.join(@tmp_dir, "test.db"),
        watch_dirs: [@tmp_dir]
      }
    }

    deep_merge(defaults, overrides)
  end

  defp deep_merge(a, b) do
    Map.merge(a, b, fn
      _key, av, bv when is_map(av) and is_map(bv) -> deep_merge(av, bv)
      _key, _av, bv -> bv
    end)
  end

  defp find_item(groups, item_id) do
    groups
    |> Enum.flat_map(& &1.items)
    |> Enum.find(&(&1.id == item_id))
  end

  describe "build/1 — structure" do
    test "returns three groups in a stable order" do
      groups = Overview.build(input())
      assert Enum.map(groups, & &1.id) == [:services, :integrations, :storage]
    end

    test "every item has the required fields" do
      groups = Overview.build(input())

      for group <- groups, item <- group.items do
        assert Map.has_key?(item, :id)
        assert Map.has_key?(item, :label)
        assert Map.has_key?(item, :detail)
        assert Map.has_key?(item, :status)
        assert Map.has_key?(item, :link)
        assert item.status in [:ok, :warning, :error, :neutral]
      end
    end
  end

  describe "Services group" do
    test "all services running → all :ok" do
      groups = Overview.build(input())
      services = Enum.find(groups, &(&1.id == :services)).items

      assert Enum.all?(services, &(&1.status == :ok))
    end

    test "a stopped service shows :warning with 'Stopped' detail" do
      groups = Overview.build(input(%{image_pipeline_running: false}))
      item = find_item(groups, :image_pipeline)

      assert item.status == :warning
      assert item.detail =~ "Stopped"
    end

    test "service items link to the services section" do
      groups = Overview.build(input())
      item = find_item(groups, :watchers)
      assert item.link == "/settings?section=services"
    end
  end

  describe "Configuration group" do
    test "TMDB not configured → :error with actionable detail" do
      groups = Overview.build(input(%{config: %{tmdb_api_key_configured?: false}}))
      item = find_item(groups, :tmdb)

      assert item.status == :error
      assert item.detail =~ "Not configured"
      assert item.link == "/settings?section=tmdb"
    end

    test "Prowlarr unreachable but configured → :warning" do
      groups =
        Overview.build(
          input(%{
            prowlarr_test: %{status: :error, tested_at: DateTime.utc_now()}
          })
        )

      item = find_item(groups, :prowlarr)
      assert item.status == :warning
      assert item.detail =~ "Unreachable"
    end

    test "Prowlarr previously tested successfully → :ok with age" do
      tested_at = DateTime.add(DateTime.utc_now(), -300, :second)

      groups =
        Overview.build(
          input(%{
            prowlarr_test: %{status: :ok, tested_at: tested_at}
          })
        )

      item = find_item(groups, :prowlarr)
      assert item.status == :ok
      assert item.detail =~ "Connected"
      assert item.detail =~ "ago"
    end

    test "Prowlarr not configured → :error with feature disabled copy" do
      groups =
        Overview.build(input(%{config: %{prowlarr_api_key_configured?: false}}))

      item = find_item(groups, :prowlarr)
      assert item.status == :error
      assert item.detail =~ "Not configured"
    end

    test "MPV binary missing → :error" do
      groups = Overview.build(input(%{config: %{mpv_path: "/definitely/not/here/mpv"}}))
      item = find_item(groups, :mpv)
      assert item.status == :error
    end

    test "MPV binary present → :ok with the path as detail" do
      groups = Overview.build(input())
      item = find_item(groups, :mpv)
      assert item.status == :ok
      assert item.detail == @present_executable or item.detail == "Found"
    end
  end

  describe "Storage group" do
    test "database path dir missing → :warning" do
      groups =
        Overview.build(input(%{config: %{database_path: "/nope/does/not/exist/foo.db"}}))

      item = find_item(groups, :database)
      assert item.status == :warning
    end

    test "all watch dirs present → :ok" do
      groups = Overview.build(input())
      item = find_item(groups, :watch_dirs)
      assert item.status == :ok
    end

    test "a missing watch dir → :warning with count" do
      groups =
        Overview.build(input(%{config: %{watch_dirs: [@tmp_dir, "/gone"]}}))

      item = find_item(groups, :watch_dirs)
      assert item.status == :warning
      assert item.detail =~ "1"
    end

    test "no watch dirs configured → :warning" do
      groups = Overview.build(input(%{config: %{watch_dirs: []}}))
      item = find_item(groups, :watch_dirs)
      assert item.status == :warning
      assert item.detail =~ "None"
    end
  end

  describe "issue_count/1" do
    test "counts :error and :warning items across all groups" do
      groups =
        Overview.build(
          input(%{
            image_pipeline_running: false,
            config: %{tmdb_api_key_configured?: false}
          })
        )

      assert Overview.issue_count(groups) == 2
    end

    test "returns 0 when everything is :ok or :neutral" do
      groups = Overview.build(input())
      assert Overview.issue_count(groups) == 0
    end
  end
end
