defmodule MediaManager.Repo do
  use AshSqlite.Repo,
    otp_app: :media_manager

  @toml_path "~/.config/freedia-center/media-manager.toml"

  @doc """
  Overrides the database path at runtime from the user's TOML config file.

  This runs before the Repo process starts (and before the Config GenServer),
  so it reads the TOML file directly rather than going through Config.
  """
  @impl true
  def init(_context, config) do
    database_path = read_database_path_from_toml() || config[:database]

    {:ok, Keyword.put(config, :database, database_path)}
  end

  defp read_database_path_from_toml do
    path = Path.expand(@toml_path)

    with {:ok, contents} <- File.read(path),
         {:ok, toml} <- Toml.decode(contents),
         database_path when is_binary(database_path) <- toml["database_path"] do
      Path.expand(database_path)
    else
      _ -> nil
    end
  end
end
