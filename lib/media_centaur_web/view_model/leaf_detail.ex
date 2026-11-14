defmodule MediaCentaurWeb.ViewModel.LeafDetail do
  @moduledoc """
  The detail modal's entry for a leaf the library owns — a movie or a
  video object: the entity, the profile's progress records and the title
  progress. The third of the three library entries beside `SeriesDetail`
  and `CollectionDetail`, with the same three base fields, so the library
  half of a title detail is one typed sum and the renderer matches on it
  rather than guessing at a bare map.

  `compose/3` reads the projection and the profile's progress through
  `Library.ModalEntry` for a kind the caller has already resolved
  (`Library.Presentable.resolve/1`); `build/1` is the pure step from its
  result.
  """

  alias MediaCentaur.Library.{ModalEntry, TitleProgress}

  @enforce_keys [:entity]
  defstruct [:entity, :progress_records, :title_progress]

  @type t :: %__MODULE__{
          entity: map(),
          progress_records: list(),
          title_progress: TitleProgress.t() | nil
        }

  @doc "Loads the entry for a resolved leaf with `profile_id`'s progress; `:not_found` when it has no present file."
  @spec compose(Ecto.UUID.t(), :movie | :video_object, Ecto.UUID.t()) :: {:ok, t()} | :not_found
  def compose(profile_id, kind, id) when kind in [:movie, :video_object] and is_binary(id) do
    case ModalEntry.load_resolved(profile_id, kind, id) do
      {:ok, entry} -> {:ok, build(entry)}
      :not_found -> :not_found
    end
  end

  @doc "Pure: the entry from a loaded `%{entity, title_progress, progress_records}`."
  @spec build(%{entity: map(), title_progress: TitleProgress.t() | nil, progress_records: list()}) :: t()
  def build(%{entity: entity, title_progress: title_progress, progress_records: records}) do
    %__MODULE__{entity: entity, progress_records: records, title_progress: title_progress}
  end
end
