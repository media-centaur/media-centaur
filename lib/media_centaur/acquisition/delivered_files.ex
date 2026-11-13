defmodule MediaCentaur.Acquisition.DeliveredFiles do
  @moduledoc """
  Judges the files a download actually contains, as the client lists
  them, against what a video release must contain.

  Two things make a download unusable whatever its name says: it holds
  no video file (an archive-only upload never becomes a library file —
  nothing here unpacks), or it holds an executable, which no video
  release ships. `problem/1` names the first that applies, in the words
  the download's timeline shows; `nil` is a download with neither.

  An empty list is a torrent whose metadata the client has not fetched
  yet, not an empty download, and is not judged.

  Pure module — no I/O. `Pursuits.Observations` asks the client once per
  target and records the answer.
  """

  alias MediaCentaur.Watcher.VideoFile

  @executable_extensions ~w(.exe .scr .bat .cmd .msi .com .lnk .apk)

  @type file :: %{name: String.t(), size: integer() | nil}

  @spec problem([file()]) :: String.t() | nil
  def problem([]), do: nil

  def problem(files) when is_list(files) do
    names = Enum.map(files, & &1.name)

    cond do
      executable = Enum.find(names, &executable?/1) ->
        "The download contains an executable file (#{Path.basename(executable)})."

      not Enum.any?(names, &VideoFile.video?/1) ->
        "The download contains no video file (#{count(length(names))}: #{extensions(names)})."

      true ->
        nil
    end
  end

  defp executable?(name), do: extension(name) in @executable_extensions

  defp extension(name), do: name |> Path.extname() |> String.downcase()

  defp count(1), do: "1 file"
  defp count(number), do: "#{number} files"

  defp extensions(names) do
    names
    |> Enum.map(&extension/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(5)
    |> Enum.join(", ")
  end
end
