defmodule MediaCentaurWeb.Components.Title.Detail.Library do
  @moduledoc """
  The library half of a title detail — the facts that exist only when
  the library owns the title. Nil on `Title.Detail` for a title without
  files.

  `entry` is the typed composition of the owning container's content:
  a `ViewModel.SeriesDetail`, a `ViewModel.CollectionDetail` or a
  `ViewModel.LeafDetail`, each carrying `entity`, `progress`,
  `progress_records` and `resume_target`. `subject` is the entity the
  lockup speaks of — the selected member of a collection, composed as a
  `:movie`-shaped map (UIDR-023), else the container itself; `member`
  is that selected member row for the rail and its Watched toggle, nil
  outside a collection. `files` is the deferred file-info load
  (`:loading` until it lands by ref), and `available` whether the
  container's media directory is online.
  """

  alias MediaCentaurWeb.ViewModel.CollectionDetail
  alias MediaCentaurWeb.ViewModel.LeafDetail
  alias MediaCentaurWeb.ViewModel.MovieRow
  alias MediaCentaurWeb.ViewModel.SeriesDetail

  @enforce_keys [:entry, :subject]
  defstruct [:entry, :subject, :member, files: :loading, available: true]

  @type entry :: SeriesDetail.t() | CollectionDetail.t() | LeafDetail.t()
  @type files :: :loading | {:ok, [map()]} | :failed

  @type t :: %__MODULE__{
          entry: entry(),
          subject: map(),
          member: MovieRow.Library.t() | nil,
          files: files(),
          available: boolean()
        }

  @doc """
  The half for a loaded entry. A collection resolves its member — the
  one `member_id` names, else the resume target, else the first
  (`CollectionDetail.select_member/2`) — and speaks of it; any other
  entry speaks of its own entity.
  """
  @spec new(entry(), Ecto.UUID.t() | nil, keyword()) :: t()
  def new(entry, member_id \\ nil, opts \\ [])

  def new(%CollectionDetail{} = entry, member_id, opts) do
    case CollectionDetail.select_member(entry, member_id) do
      %MovieRow.Library{} = member ->
        %__MODULE__{
          entry: entry,
          subject: CollectionDetail.member_subject(member),
          member: member,
          available: Keyword.get(opts, :available, true)
        }

      nil ->
        %__MODULE__{entry: entry, subject: entry.entity, available: Keyword.get(opts, :available, true)}
    end
  end

  def new(entry, _member_id, opts),
    do: %__MODULE__{entry: entry, subject: entry.entity, available: Keyword.get(opts, :available, true)}
end
