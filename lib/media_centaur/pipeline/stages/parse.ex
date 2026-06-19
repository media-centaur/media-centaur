defmodule MediaCentaur.Pipeline.Stages.Parse do
  @moduledoc """
  Pipeline stage 1: parses the file path into title, year, type, season,
  and episode using `MediaCentaur.Parser`.

  Reads `extras_dirs` from config so extras directories are recognised.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Parser
  alias MediaCentaur.Pipeline.Payload

  @behaviour MediaCentaur.Pipeline.Stage

  @spec run(Payload.t()) :: {:ok, Payload.t()}
  @impl true
  def run(%Payload{file_path: file_path} = payload) do
    extras_dirs = extras_dirs_from_config()
    result = Parser.parse(file_path, extras_dirs: extras_dirs)

    Log.info(:pipeline, fn ->
      "parsed #{Path.basename(file_path)} — " <>
        "title=#{inspect(result.title)}, type=#{result.type}" <>
        if(result.season, do: ", S#{result.season}E#{result.episode}", else: "") <>
        if(result.year, do: ", year=#{result.year}", else: "")
    end)

    {:ok, %{payload | parsed: result}}
  end

  @doc """
  The configured extras directories, downcased, as the parser expects them.
  Public so the re-derive sweep (`MediaCentaur.Pipeline.ExtraRederive`) parses
  with exactly the same hint import used.
  """
  @spec extras_dirs_from_config() :: [String.t()] | nil
  def extras_dirs_from_config do
    case MediaCentaur.Config.get(:extras_dirs) do
      dirs when is_list(dirs) -> Enum.map(dirs, &String.downcase/1)
      _ -> nil
    end
  end
end
