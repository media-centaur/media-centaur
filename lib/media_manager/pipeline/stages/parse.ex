defmodule MediaManager.Pipeline.Stages.Parse do
  @moduledoc """
  Pipeline stage 1: parses the file path into title, year, type, season,
  and episode using `MediaManager.Parser`.

  Reads `extras_dirs` from config so extras directories are recognised.
  """
  require MediaManager.Log, as: Log

  alias MediaManager.Pipeline.Payload

  @spec run(Payload.t()) :: {:ok, Payload.t()}
  def run(%Payload{file_path: file_path} = payload) do
    extras_dirs = extras_dirs_from_config()
    result = MediaManager.Parser.parse(file_path, extras_dirs: extras_dirs)

    Log.info(:pipeline, fn ->
      "parsed #{Path.basename(file_path)}: " <>
        "title=#{inspect(result.title)}, type=#{result.type}" <>
        if(result.season, do: ", S#{result.season}E#{result.episode}", else: "") <>
        if(result.year, do: ", year=#{result.year}", else: "")
    end)

    {:ok, %{payload | parsed: result}}
  end

  defp extras_dirs_from_config do
    case MediaManager.Config.get(:extras_dirs) do
      dirs when is_list(dirs) -> Enum.map(dirs, &String.downcase/1)
      _ -> nil
    end
  end
end
