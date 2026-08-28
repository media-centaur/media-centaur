defmodule MediaCentaur.Apps.SteamTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Apps.Steam

  defp tmp_steam_root(context_name) do
    root =
      Path.join(
        System.tmp_dir!(),
        "mc-steam-#{context_name}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "steamapps"))
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp write_manifest(root, app_id, name) do
    File.write!(Path.join([root, "steamapps", "appmanifest_#{app_id}.acf"]), """
    "AppState"
    {
    \t"appid"\t\t"#{app_id}"
    \t"name"\t\t"#{name}"
    \t"installdir"\t\t"#{name}"
    }
    """)
  end

  describe "string_pairs/1" do
    test "extracts quoted key-value pairs from VDF text" do
      vdf = ~s("AppState"\n{\n\t"appid"\t\t"100"\n\t"name"\t\t"Sample Game"\n})
      pairs = Steam.string_pairs(vdf)
      assert {"appid", "100"} in pairs
      assert {"name", "Sample Game"} in pairs
    end

    test "handles escaped quotes inside values" do
      assert [{"name", ~S(Sample \"Quoted\" Game)}] =
               Steam.string_pairs(~S("name" "Sample \"Quoted\" Game"))
    end
  end

  describe "installed_games/1" do
    test "lists games from appmanifest files across library folders" do
      root = tmp_steam_root("games")
      write_manifest(root, 100, "Sample Game")

      extra = Path.join(root, "extra-library")
      File.mkdir_p!(Path.join(extra, "steamapps"))
      write_manifest(extra, 200, "Movie Tie-In Game")

      File.write!(Path.join([root, "steamapps", "libraryfolders.vdf"]), """
      "libraryfolders"
      {
      \t"0"
      \t{
      \t\t"path"\t\t"#{root}"
      \t}
      \t"1"
      \t{
      \t\t"path"\t\t"#{extra}"
      \t}
      }
      """)

      games = Steam.installed_games(root)
      assert %{app_id: 100, name: "Sample Game"} in games
      assert %{app_id: 200, name: "Movie Tie-In Game"} in games
    end

    test "works without a libraryfolders.vdf (root steamapps only)" do
      root = tmp_steam_root("novdf")
      write_manifest(root, 100, "Sample Game")
      assert [%{app_id: 100, name: "Sample Game"}] = Steam.installed_games(root)
    end

    test "filters runtimes and redistributables" do
      root = tmp_steam_root("filter")
      write_manifest(root, 228_980, "Steamworks Common Redistributables")
      write_manifest(root, 1_628_350, "Steam Linux Runtime 3.0 (sniper)")
      write_manifest(root, 2_348_590, "Proton 8.0")
      write_manifest(root, 100, "Sample Game")

      assert [%{app_id: 100}] = Steam.installed_games(root)
    end

    test "sorts by name" do
      root = tmp_steam_root("sort")
      write_manifest(root, 2, "Zebra Game")
      write_manifest(root, 1, "Alpha Game")
      assert ["Alpha Game", "Zebra Game"] = Enum.map(Steam.installed_games(root), & &1.name)
    end
  end

  describe "command_for/2" do
    test "native install launches via the steam binary" do
      assert Steam.command_for(100, "/home/user/.local/share/Steam") ==
               "steam steam://rungameid/100"
    end

    test "flatpak install launches via flatpak run" do
      root = "/home/user/.var/app/com.valvesoftware.Steam/.local/share/Steam"

      assert Steam.command_for(100, root) ==
               "flatpak run com.valvesoftware.Steam steam://rungameid/100"
    end
  end

  describe "local_art_path/3" do
    test "finds art in the flat librarycache layout" do
      root = tmp_steam_root("flat-art")
      cache = Path.join([root, "appcache", "librarycache"])
      File.mkdir_p!(cache)
      File.write!(Path.join(cache, "100_header.jpg"), "jpg")

      assert Steam.local_art_path(root, 100, :banner) == Path.join(cache, "100_header.jpg")
      assert Steam.local_art_path(root, 100, :poster) == nil
    end

    test "finds art in the per-appid librarycache layout" do
      root = tmp_steam_root("dir-art")
      cache = Path.join([root, "appcache", "librarycache", "100"])
      File.mkdir_p!(cache)
      File.write!(Path.join(cache, "library_600x900.jpg"), "jpg")

      assert Steam.local_art_path(root, 100, :poster) ==
               Path.join(cache, "library_600x900.jpg")
    end
  end

  describe "cdn_art_url/2" do
    test "builds the store asset URL per role" do
      assert Steam.cdn_art_url(100, :banner) ==
               "https://shared.steamstatic.com/store_item_assets/steam/apps/100/header.jpg"

      assert Steam.cdn_art_url(100, :poster) ==
               "https://shared.steamstatic.com/store_item_assets/steam/apps/100/library_600x900.jpg"
    end
  end
end
