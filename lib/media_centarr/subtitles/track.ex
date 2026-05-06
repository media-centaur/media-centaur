defmodule MediaCentarr.Subtitles.Track do
  @moduledoc """
  A single detected subtitle track.

  Independent of where the track came from — embedded in the video
  container, a sidecar file next to the video, or any future source.
  Detector modules build `Track` values; the orchestrator dedupes and
  aggregates over them; the UI renders them.

  Stored on `Library.WatchedFile.subtitle_tracks` as plain maps
  (`{:array, :map}` Ecto field). Use `from_map/1` to convert a stored
  map back into a struct, and `to_map/1` to write one out.
  """

  @enforce_keys [:kind, :source]
  defstruct [:kind, :language, :source]

  @type kind :: :embedded | :sidecar

  @type t :: %__MODULE__{
          kind: kind(),
          language: String.t() | nil,
          source: String.t()
        }

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = track) do
    %{
      "kind" => Atom.to_string(track.kind),
      "language" => track.language,
      "source" => track.source
    }
  end

  @spec from_map(map()) :: t() | nil
  def from_map(%{"kind" => kind, "source" => source} = map) do
    %__MODULE__{
      kind: parse_kind(kind),
      language: Map.get(map, "language"),
      source: source
    }
  end

  def from_map(_), do: nil

  defp parse_kind("embedded"), do: :embedded
  defp parse_kind("sidecar"), do: :sidecar
  defp parse_kind(other) when is_atom(other), do: other
end
