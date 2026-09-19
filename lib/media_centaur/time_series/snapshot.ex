defmodule MediaCentaur.TimeSeries.Snapshot do
  @moduledoc """
  The store's on-disk copy: one file holding
  `{:media_centaur_time_series, 1, fields, rows}` in External Term Format,
  compressed, written to `<path>.tmp` and renamed into place so a crash
  mid-write leaves the previous file intact.

  `read/2` accepts only a file whose tag, version and field list match the
  schema given; anything else is `{:error, reason}` and the caller starts
  empty. Observational data is never migrated (ADR-070).
  """

  alias MediaCentaur.TimeSeries.Schema

  @tag :media_centaur_time_series
  @version 1

  @spec write(Path.t(), Schema.t(), [tuple()]) :: :ok | {:error, term()}
  def write(path, %Schema{fields: fields}, rows) do
    binary = :erlang.term_to_binary({@tag, @version, fields, rows}, compressed: 6)
    tmp = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp, binary) do
      File.rename(tmp, path)
    end
  end

  @spec read(Path.t(), Schema.t()) :: {:ok, [tuple()]} | :empty | {:error, term()}
  def read(path, %Schema{fields: fields}) do
    case File.read(path) do
      {:error, :enoent} -> :empty
      {:error, reason} -> {:error, reason}
      {:ok, binary} -> decode(binary, fields)
    end
  end

  defp decode(binary, fields) do
    case :erlang.binary_to_term(binary, [:safe]) do
      {@tag, @version, ^fields, rows} when is_list(rows) -> {:ok, rows}
      {@tag, @version, _other_fields, _rows} -> {:error, :schema_mismatch}
      _other -> {:error, :unrecognised}
    end
  rescue
    ArgumentError -> {:error, :corrupt}
  end
end
