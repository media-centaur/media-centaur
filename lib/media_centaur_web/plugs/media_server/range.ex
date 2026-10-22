defmodule MediaCentaurWeb.Plugs.MediaServer.Range do
  @moduledoc """
  The one `Range` header shape a media player sends, against a file size.

  ffmpeg's HTTP demuxer (libmpv's) asks for a single open-ended or closed
  byte range and reopens on seek, so this is the whole surface: one
  `bytes=start-end`, `bytes=start-`, or `bytes=-suffix` range. Several
  ranges, a malformed header, or a start past the end are unsatisfiable
  and answered `416` by the plug. No header means the whole file.
  """

  @type outcome ::
          :whole | {:partial, offset :: non_neg_integer(), length :: pos_integer()} | :unsatisfiable

  @doc "What to serve for a `Range` header (`nil` for none) of a file `size` bytes long."
  @spec parse(String.t() | nil, non_neg_integer()) :: outcome()
  def parse(nil, _size), do: :whole
  def parse(_header, 0), do: :unsatisfiable

  def parse("bytes=" <> spec, size) do
    case String.split(spec, ",") do
      [single] -> single |> String.trim() |> parse_single(size)
      _several -> :unsatisfiable
    end
  end

  def parse(_other_unit, _size), do: :unsatisfiable

  defp parse_single("-" <> suffix, size) do
    case Integer.parse(suffix) do
      {count, ""} when count > 0 -> {:partial, max(size - count, 0), min(count, size)}
      _ -> :unsatisfiable
    end
  end

  defp parse_single(spec, size) do
    case String.split(spec, "-", parts: 2) do
      [first, ""] -> from_first(first, size - 1, size)
      [first, last] -> from_first(first, last, size)
      _ -> :unsatisfiable
    end
  end

  defp from_first(first, last, size) do
    with {start, ""} <- Integer.parse(first),
         {finish, ""} <- parse_last(last),
         true <- start >= 0 and start < size and finish >= start do
      finish = min(finish, size - 1)
      {:partial, start, finish - start + 1}
    else
      _ -> :unsatisfiable
    end
  end

  defp parse_last(last) when is_integer(last), do: {last, ""}
  defp parse_last(last) when is_binary(last), do: Integer.parse(last)
end
