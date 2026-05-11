defmodule MediaCentarr.Playback.MpvLogReader do
  @moduledoc """
  Reads the tail of an mpv `--log-file=` capture for inclusion in the exit
  classifier's `output_tail`.

  Production runs mpv with `--no-terminal`, which silences mpv's stderr —
  so when mpv fails to start, the backend's port-data capture is empty
  and `MpvExitClassifier` falls back to the generic "mpv exited (status
  N) before playback started" message. Routing mpv's own logs through a
  per-session file and slurping the tail at finalization time gives the
  classifier the real error string instead.
  """

  @spec tail_lines(binary(), pos_integer()) :: [String.t()]
  def tail_lines(content, count) when is_binary(content) and is_integer(count) and count > 0 do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(-count)
  end

  @spec read_tail(String.t() | nil, pos_integer()) :: [String.t()]
  def read_tail(nil, _count), do: []

  def read_tail(path, count) when is_binary(path) and is_integer(count) and count > 0 do
    case File.read(path) do
      {:ok, content} -> tail_lines(content, count)
      {:error, _reason} -> []
    end
  end

  @doc """
  Selects the best available exit-output tail for `MpvExitClassifier`.

  Prefers a non-empty port-data tail (mpv ran with a terminal and we captured
  stderr live). Falls back to the `--log-file=` capture when the port tail is
  empty — which is the production case because `--no-terminal` silences mpv's
  stderr entirely.
  """
  @spec fallback_tail([String.t()], String.t() | nil, pos_integer()) :: [String.t()]
  def fallback_tail([_ | _] = port_tail, _log_path, _count), do: port_tail
  def fallback_tail([], log_path, count), do: read_tail(log_path, count)
end
