defmodule MediaCentaur.Pipeline.Stages.Parse do
  @moduledoc """
  Pipeline stage 1: parses the file path into title, year, type, season,
  and episode using `MediaCentaur.Parser`.

  Reads the extras folder names from `Settings.Config.extras_dirs/0` —
  the one accessor every path-parsing site shares, so this stage, import
  and review intake cannot disagree about whether a file is a bonus
  feature.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Parser
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Settings.Config

  @behaviour MediaCentaur.Pipeline.Stage

  @spec run(Payload.t()) :: {:ok, Payload.t()}
  @impl true
  def run(%Payload{file_path: file_path} = payload) do
    result = Parser.parse(file_path, extras_dirs: Config.extras_dirs())

    Log.info(:pipeline, fn ->
      "parsed #{Path.basename(file_path)} — " <>
        "title=#{inspect(result.title)}, type=#{result.type}" <>
        if(result.season, do: ", S#{result.season}E#{result.episode}", else: "") <>
        if(result.year, do: ", year=#{result.year}", else: "")
    end)

    {:ok, %{payload | parsed: result}}
  end
end
