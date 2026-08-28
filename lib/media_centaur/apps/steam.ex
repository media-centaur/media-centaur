defmodule MediaCentaur.Apps.Steam do
  @moduledoc """
  Steam add-method: discovers installed games and resolves them to
  uniform App attributes (command + artwork) at add time.

  Reads Steam's on-disk state directly — `steamapps/libraryfolders.vdf`
  for library folders, `appmanifest_*.acf` per installed game. Both are
  VDF text; `string_pairs/1` is a tolerant flat extraction of quoted
  key-value pairs (no recursive parser — the keys we need are unique
  per file).

  All functions take the Steam root explicitly; `detect_root/0` probes
  the conventional install locations (native, XDG, flatpak).
  """

  @roots [
    ".steam/steam",
    ".local/share/Steam",
    ".var/app/com.valvesoftware.Steam/.local/share/Steam"
  ]

  # Non-game manifests Steam installs alongside games.
  @non_game_name ~r/^(Steamworks Common Redistributables|Steam Linux Runtime|Proton)/

  # Filenames per role in the per-appid librarycache layout and on the
  # CDN; the legacy flat layout prefixes the same names with `{appid}_`.
  @art_files %{banner: "header.jpg", poster: "library_600x900.jpg"}
  @cdn "https://shared.steamstatic.com/store_item_assets/steam/apps"

  @type game :: %{app_id: integer(), name: String.t()}
  @type role :: :banner | :poster

  @doc "First conventional Steam root that exists, or nil."
  @spec detect_root() :: String.t() | nil
  def detect_root do
    home = System.user_home()
    home && Enum.find(Enum.map(@roots, &Path.join(home, &1)), &File.dir?/1)
  end

  @doc "Flat list of `{key, value}` string pairs in a VDF document."
  @spec string_pairs(String.t()) :: [{String.t(), String.t()}]
  def string_pairs(content) do
    ~r/"((?:\\.|[^"\\])*)"\s+"((?:\\.|[^"\\])*)"/
    |> Regex.scan(content)
    |> Enum.map(fn [_all, key, value] -> {key, value} end)
  end

  @doc "Installed games across all library folders, sorted by name."
  @spec installed_games(String.t()) :: [game()]
  def installed_games(root) do
    root
    |> library_folders()
    |> Enum.flat_map(&folder_games/1)
    |> Enum.uniq_by(& &1.app_id)
    |> Enum.reject(&Regex.match?(@non_game_name, &1.name))
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  @doc "The launch command for a game — flatpak-aware, resolved at add time."
  @spec command_for(integer(), String.t()) :: String.t()
  def command_for(app_id, root) do
    if String.contains?(root, ".var/app/com.valvesoftware.Steam") do
      "flatpak run com.valvesoftware.Steam steam://rungameid/#{app_id}"
    else
      "steam steam://rungameid/#{app_id}"
    end
  end

  @doc """
  Path to locally-cached Steam art for a role, or nil. Checks both
  librarycache layouts: per-appid subdirectory (current Steam) and the
  legacy flat `{appid}_header.jpg` naming.
  """
  @spec local_art_path(String.t(), integer(), role()) :: String.t() | nil
  def local_art_path(root, app_id, role) do
    cache = Path.join([root, "appcache", "librarycache"])
    filename = Map.fetch!(@art_files, role)

    candidates = [
      Path.join([cache, to_string(app_id), filename]),
      Path.join(cache, "#{app_id}_#{filename}")
    ]

    Enum.find(candidates, &File.regular?/1)
  end

  @doc "Steam CDN fallback URL for a role's art."
  @spec cdn_art_url(integer(), role()) :: String.t()
  def cdn_art_url(app_id, role) do
    "#{@cdn}/#{app_id}/#{Map.fetch!(@art_files, role)}"
  end

  defp library_folders(root) do
    vdf = Path.join([root, "steamapps", "libraryfolders.vdf"])

    extra =
      case File.read(vdf) do
        {:ok, content} ->
          for {"path", path} <- string_pairs(content), File.dir?(path), do: path

        {:error, _reason} ->
          []
      end

    Enum.uniq([root | extra])
  end

  defp folder_games(folder) do
    [folder, "steamapps", "appmanifest_*.acf"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.flat_map(fn manifest ->
      case File.read(manifest) do
        {:ok, content} -> manifest_game(content)
        {:error, _reason} -> []
      end
    end)
  end

  defp manifest_game(content) do
    pairs = Map.new(string_pairs(content))

    with %{"appid" => id_string, "name" => name} <- pairs,
         {app_id, ""} <- Integer.parse(id_string) do
      [%{app_id: app_id, name: name}]
    else
      _mismatch -> []
    end
  end
end
