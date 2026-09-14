defmodule MediaCentaurWeb.ViewModel.LeafDetail do
  @moduledoc """
  The detail modal's entry for a leaf the library owns — a movie or a
  video object: the entity, its progress summary and records, and the
  resume target. The third of the three library entries beside
  `SeriesDetail` and `CollectionDetail`, with the same four base fields,
  so the library half of a title detail is one typed sum and the
  renderer matches on it rather than guessing at a bare map.

  `compose/2` reads the projection through `Library.ModalEntry` for a
  kind the caller has already resolved (`Library.Presentable.resolve/1`)
  and stamps the resume target (`Playback.ResumeTarget`); `build/1`
  is the pure step from a loaded entry.
  """

  alias MediaCentaur.Library.ModalEntry
  alias MediaCentaur.Playback.ResumeTarget

  @enforce_keys [:entity]
  defstruct [:entity, :progress, :progress_records, :resume_target]

  @type t :: %__MODULE__{
          entity: map(),
          progress: map() | nil,
          progress_records: list(),
          resume_target: map() | nil
        }

  @doc "Loads the entry for a resolved leaf; `:not_found` when it has no present file."
  @spec compose(:movie | :video_object, Ecto.UUID.t()) :: {:ok, t()} | :not_found
  def compose(kind, id) when kind in [:movie, :video_object] and is_binary(id) do
    case ModalEntry.load_resolved(kind, id) do
      {:ok, entry} -> {:ok, build(entry)}
      :not_found -> :not_found
    end
  end

  @doc "Pure: the entry from a loaded `%{entity, progress, progress_records}`."
  @spec build(%{entity: map(), progress: map() | nil, progress_records: list()}) :: t()
  def build(%{entity: entity, progress: progress, progress_records: records}) do
    %__MODULE__{
      entity: entity,
      progress: progress,
      progress_records: records,
      resume_target: ResumeTarget.compute(entity, records)
    }
  end
end
