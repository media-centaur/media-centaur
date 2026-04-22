defmodule MediaCentarr.Playback.MpvExitClassifier do
  @moduledoc """
  Pure functions for classifying an MPV session's exit and building a short
  user-facing message from captured MPV output.

  ## Classification

  An MPV session is considered `:ended` (normal) when it produced at least one
  property event (time-pos, duration, pause, eof-reached) — this means the file
  actually loaded and playback started, regardless of how the session terminated.

  Any exit without a property event is a `:startup_failure` — MPV was launched
  and the IPC socket was reached, but playback never began. This is what we saw
  in production when a user clicked "next episode" and mpv died silently 2s
  later with no visible window.

  ## Output capture

  The per-session output tail is a plain list of the last N (default 50) lines
  of MPV's merged stdout+stderr. `append_output/2` handles incremental chunks
  from the port (which may split mid-line) and maintains the bounded window.
  """

  @max_lines 50
  @max_message_length 200

  @error_keywords ~w(fail error cannot unable refus denied no\ such invalid unsupported)

  @spec classify(%{
          seen_property_event?: boolean(),
          exit_status: integer() | nil,
          output_tail: [String.t()]
        }) :: {:ok, :ended} | {:error, :startup_failure, String.t()}
  def classify(%{seen_property_event?: true}), do: {:ok, :ended}

  def classify(%{seen_property_event?: false, exit_status: status, output_tail: tail}) do
    {:error, :startup_failure, build_message(tail, status)}
  end

  @doc """
  Appends port output data to an existing tail, splitting on newlines and
  capping the window at #{@max_lines} lines.

  The port may deliver data split mid-line; this function treats a trailing
  non-newline segment as its own line (preserved in the tail). A trailing
  newline produces no empty entry.
  """
  @spec append_output([String.t()], binary()) :: [String.t()]
  def append_output(tail, data) when is_binary(data) do
    lines =
      data
      |> String.split("\n")
      |> trim_trailing_empty()

    Enum.take(tail ++ lines, -@max_lines)
  end

  defp trim_trailing_empty(lines) do
    case List.last(lines) do
      "" -> Enum.drop(lines, -1)
      _ -> lines
    end
  end

  defp build_message([], nil), do: "mpv exited before playback started"
  defp build_message([], status), do: "mpv exited (status #{status}) before playback started"

  defp build_message(tail, _status) do
    tail
    |> pick_summary_line()
    |> strip_ansi()
    |> String.trim()
    |> truncate()
  end

  defp pick_summary_line(tail) do
    non_blank = Enum.reject(tail, &blank?/1)

    Enum.find(Enum.reverse(non_blank), &error_like?/1) ||
      List.last(non_blank) ||
      ""
  end

  defp blank?(line), do: String.trim(line) == ""

  defp error_like?(line) do
    downcased = String.downcase(line)
    Enum.any?(@error_keywords, &String.contains?(downcased, &1))
  end

  defp strip_ansi(line) do
    Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, line, "")
  end

  defp truncate(line) when byte_size(line) <= @max_message_length, do: line

  defp truncate(line) do
    String.slice(line, 0, @max_message_length - 1) <> "…"
  end
end
