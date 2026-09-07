defmodule MediaCentaur.Acquisition.TitleDownloadParams do
  @moduledoc """
  Stores one title's `MediaCentaur.Acquisition.DownloadParams`, keyed by
  TMDB identity — `{tmdb_id, media_type}` — and by nothing else.

  Keying on identity rather than on a tracked title is the whole point.
  These params used to be columns on `ReleaseTracking.Item`, so the only
  way to record "lower quality is fine for this show" was to *create a
  tracked title*, which is how adjusting a quality floor came to start
  following a show nobody asked to follow.

  An absent row and an all-`nil` row say the same thing, so `put/3`
  deletes a row that has been emptied and `get/2` answers with
  `DownloadParams.defaults/0` when there is none. Callers never have to
  distinguish "never set" from "reset".
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias MediaCentaur.Acquisition.DownloadParams
  alias MediaCentaur.Repo

  @type media_type :: :movie | :tv_series

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          tmdb_id: integer(),
          media_type: media_type(),
          params: DownloadParams.t()
        }

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "title_download_params" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    embeds_one :params, DownloadParams, on_replace: :delete

    timestamps()
  end

  @doc """
  The title's params, or the defaults when nothing has been said about
  it. Never returns `nil`, so every caller can read a field directly.
  """
  @spec get(integer(), media_type()) :: DownloadParams.t()
  def get(tmdb_id, media_type) do
    case fetch_row(tmdb_id, media_type) do
      %__MODULE__{params: %DownloadParams{} = params} -> params
      _absent -> DownloadParams.defaults()
    end
  end

  @doc """
  The params for many titles at once, as `{tmdb_id, media_type} =>
  params`. Absent titles are absent from the map — read them through
  `for_ref/2`, which supplies the defaults.
  """
  @spec get_many([{integer(), media_type()}]) :: %{
          {integer(), media_type()} => DownloadParams.t()
        }
  def get_many([]), do: %{}

  def get_many(refs) do
    tmdb_ids = refs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    wanted = MapSet.new(refs)

    from(p in __MODULE__, where: p.tmdb_id in ^tmdb_ids)
    |> Repo.all()
    |> Enum.filter(&MapSet.member?(wanted, {&1.tmdb_id, &1.media_type}))
    |> Map.new(&{{&1.tmdb_id, &1.media_type}, &1.params})
  end

  @doc "Reads one ref out of a `get_many/1` map, falling back to the defaults."
  @spec for_ref(%{{integer(), media_type()} => DownloadParams.t()}, {integer(), media_type()}) ::
          DownloadParams.t()
  def for_ref(by_ref, ref), do: Map.get(by_ref, ref, DownloadParams.defaults())

  @doc """
  Merges `attrs` into the title's params. An explicit `nil` clears that
  param back to the global default; emptying every param removes the row,
  since an absent record and an empty one mean the same thing.
  """
  @spec put(integer(), media_type(), map()) ::
          {:ok, DownloadParams.t()} | {:error, Ecto.Changeset.t()}
  def put(tmdb_id, media_type, attrs) do
    row = fetch_row(tmdb_id, media_type) || build_row(tmdb_id, media_type)
    current = row.params || DownloadParams.defaults()
    params = DownloadParams.changeset(current, attrs)

    with {:ok, merged} <- Ecto.Changeset.apply_action(params, :update) do
      write(row, merged)
    end
  end

  @doc "Whether anything is stored for this title at all."
  @spec stored?(integer(), media_type()) :: boolean()
  def stored?(tmdb_id, media_type), do: not is_nil(fetch_row(tmdb_id, media_type))

  @doc "Forgets everything stored for this title."
  @spec forget(integer(), media_type()) :: :ok
  def forget(tmdb_id, media_type) do
    case fetch_row(tmdb_id, media_type) do
      nil -> :ok
      row -> with {:ok, _} <- Repo.delete(row), do: :ok
    end
  end

  defp write(%__MODULE__{} = row, %DownloadParams{} = merged) do
    cond do
      DownloadParams.any?(merged) ->
        row
        |> change()
        |> put_embed(:params, merged)
        |> unique_constraint([:tmdb_id, :media_type])
        |> Repo.insert_or_update()
        |> case do
          {:ok, saved} -> {:ok, saved.params}
          {:error, changeset} -> {:error, changeset}
        end

      persisted?(row) ->
        with {:ok, _} <- Repo.delete(row), do: {:ok, DownloadParams.defaults()}

      true ->
        {:ok, DownloadParams.defaults()}
    end
  end

  defp persisted?(%__MODULE__{__meta__: %{state: :loaded}}), do: true
  defp persisted?(%__MODULE__{}), do: false

  defp build_row(tmdb_id, media_type) do
    %__MODULE__{tmdb_id: tmdb_id, media_type: media_type, params: DownloadParams.defaults()}
  end

  defp fetch_row(tmdb_id, media_type) do
    Repo.get_by(__MODULE__, tmdb_id: tmdb_id, media_type: media_type)
  end
end
