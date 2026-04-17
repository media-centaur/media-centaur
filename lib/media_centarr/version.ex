defmodule MediaCentarr.Version do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Runtime access to the app's version and build metadata.

  The running version is read from `Application.spec(:media_centarr, :vsn)`,
  which is populated from `mix.exs` at compile time.

  Build metadata (build timestamp, git SHA) is written by the release CI
  workflow into `priv/build_info.json` before compile. In dev/test there is
  no such file and `build_info/1` returns `:dev_build`.

  ## Build info file format

      {
        "version": "0.4.0",
        "built_at": "2026-04-17T12:34:56Z",
        "git_sha": "abc1234"
      }
  """

  @type build_info ::
          %{
            version: String.t(),
            built_at: DateTime.t(),
            git_sha: String.t()
          }

  @app :media_centarr

  @doc "Returns the running application's version as a string."
  @spec current_version() :: String.t()
  def current_version do
    case Application.spec(@app, :vsn) do
      nil -> "0.0.0"
      vsn -> to_string(vsn)
    end
  end

  @doc """
  Reads the release's build info file.

  Returns `{:ok, info}` when the file exists and parses, or `:dev_build`
  when the file is absent or malformed.
  """
  @spec build_info(Path.t()) :: {:ok, build_info()} | :dev_build
  def build_info(path \\ default_build_info_path()) do
    with {:ok, body} <- File.read(path),
         {:ok, data} <- decode_json(body),
         {:ok, info} <- extract_fields(data) do
      {:ok, info}
    else
      _ -> :dev_build
    end
  end

  @doc """
  Compares two SemVer version strings. Leading `v` is stripped from either
  side. Returns `:gt`, `:eq`, `:lt`, or `:error` on parse failure.
  """
  @spec compare_versions(String.t(), String.t()) :: :gt | :eq | :lt | :error
  def compare_versions(remote, local) do
    with {:ok, remote_v} <- parse(remote),
         {:ok, local_v} <- parse(local) do
      Version.compare(remote_v, local_v)
    end
  end

  # --- private ---

  defp default_build_info_path do
    Application.app_dir(@app, "priv/build_info.json")
  end

  defp decode_json(body) do
    {:ok, JSON.decode!(body)}
  rescue
    _ -> :error
  end

  defp extract_fields(%{"version" => version, "built_at" => built_at, "git_sha" => git_sha})
       when is_binary(version) and is_binary(built_at) and is_binary(git_sha) do
    case DateTime.from_iso8601(built_at) do
      {:ok, datetime, _offset} ->
        {:ok, %{version: version, built_at: datetime, git_sha: git_sha}}

      _ ->
        :error
    end
  end

  defp extract_fields(_), do: :error

  defp parse(raw) when is_binary(raw) do
    raw
    |> String.trim_leading("v")
    |> Version.parse()
  end
end
