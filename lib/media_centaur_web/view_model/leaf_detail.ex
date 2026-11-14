defmodule MediaCentaurWeb.ViewModel.LeafDetail do
  @moduledoc """
  The detail modal's entry for a leaf the library owns — a movie or a
  video object: the entity, its progress summary and records, and the
  title progress. The third of the three library entries beside
  `SeriesDetail` and `CollectionDetail`, with the same four base fields,
  so the library half of a title detail is one typed sum and the
  renderer matches on it rather than guessing at a bare map.

  `compose/3` reads the projection through `Library.ModalEntry` for a
  kind the caller has already resolved (`Library.Presentable.resolve/1`)
  and the profile's records and title progress through
  `Library.ProgressRecords.title_progress/2`; `build/2` is the pure step
  from the two.
  """

  alias MediaCentaur.Library.{ModalEntry, ProgressRecords, TitleProgress}

  @enforce_keys [:entity]
  defstruct [:entity, :progress, :progress_records, :title_progress]

  @type t :: %__MODULE__{
          entity: map(),
          progress: map() | nil,
          progress_records: list(),
          title_progress: TitleProgress.t() | nil
        }

  @doc "Loads the entry for a resolved leaf with `profile_id`'s progress; `:not_found` when it has no present file."
  @spec compose(Ecto.UUID.t(), :movie | :video_object, Ecto.UUID.t()) :: {:ok, t()} | :not_found
  def compose(profile_id, kind, id) when kind in [:movie, :video_object] and is_binary(id) do
    case ModalEntry.load_resolved(profile_id, kind, id) do
      {:ok, entry} -> {:ok, build(entry, ProgressRecords.title_progress(profile_id, entry.entity))}
      :not_found -> :not_found
    end
  end

  @doc """
  Pure: the entry from a loaded `%{entity, progress}` and the profile's
  `%{title_progress, records}` for that entity.
  """
  @spec build(%{entity: map(), progress: map() | nil}, %{
          title_progress: TitleProgress.t(),
          records: list()
        }) :: t()
  def build(%{entity: entity, progress: progress}, %{title_progress: title_progress, records: records}) do
    %__MODULE__{
      entity: entity,
      progress: progress,
      progress_records: records,
      title_progress: title_progress
    }
  end
end
