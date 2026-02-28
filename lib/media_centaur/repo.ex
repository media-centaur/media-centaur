defmodule MediaCentaur.Repo do
  use AshSqlite.Repo,
    otp_app: :media_centaur

  @toml_path "~/.config/media-centaur/backend.toml"

  @doc """
  Overrides the database path at runtime from the user's TOML config file.

  This runs before the Repo process starts (and before the Config GenServer),
  so it reads the TOML file directly rather than going through Config.

  In test (Sandbox pool), the TOML override is skipped so tests use the
  dedicated test database configured in `config/test.exs`.
  """
  @impl true
  def init(_context, config) do
    database_path =
      if config[:pool] == Ecto.Adapters.SQL.Sandbox do
        config[:database]
      else
        read_database_path_from_toml() || config[:database]
      end

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
