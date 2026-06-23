defmodule MediaCentaur.Reconciliation do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.TMDB],
    exports: [
      Artifact,
      AwaitingFile,
      Engine,
      Interpretation,
      Model,
      Placement,
      Resolution,
      ShowReview,
      Spine,
      SpineNode,
      Models.GapFill,
      Models.TitleMatch
    ]

  @moduledoc """
  Reconciles **artifacts** (files, and later release candidates) against a
  show's **canonical episode spine** (TMDB numbering) — the engine behind
  cour-aware ingest (see `campaigns/reconciliation-engine.md`).

  The system must never fabricate canonical structure to fit an artifact's
  self-description (a file labelled `S02E01` for a single-season show must
  not mint a phantom Season 2). Instead, plural **interpretation models**
  (`Reconciliation.Model`) propose how a batch maps onto the spine —
  `Models.GapFill` is the reliable floor; title/absolute/offset models
  corroborate — each yielding `Interpretation`s with a confidence and a
  human-readable rationale. Agreement collapses to a high-confidence
  proposal; disagreement surfaces as alternatives the user arbitrates.

  ## Vocabulary

  - `SpineNode` — one canonical `{season, episode}` position; `present?`
    marks what the library already has, so the *gap* is what a batch
    reconciles against.
  - `Artifact` — a file with **claims** (`claimed_season/episode/title`):
    evidence, not truth.
  - `Placement` — a proposed `artifact → {season, episode}` link.
  - `Interpretation` — one model's full proposal: placements + confidence
    + rationale.

  ## Pure core vs. persistence

  The engine + models are **pure** (`Engine`, `Models.*`) — they read an
  assembled spine + artifacts and never touch I/O. This module is the
  context root and owns the one piece of durable state: the
  **awaiting-file queue** (`AwaitingFile`). A confirmed mapping is just a
  library `WatchedFile` link (a `present?` spine node), so there is no
  separate "placement" or "pin" table — proposals are re-derived each run
  (deriver model, ADR-057). The impure spine assembly (TMDB fetch +
  library present-set) and the confirm-writes-links path arrive with the
  review surface.
  """

  import Ecto.Query, only: [from: 2]

  alias MediaCentaur.Library
  alias MediaCentaur.Reconciliation.{Artifact, AwaitingFile, Engine, ShowReview, Spine}
  alias MediaCentaur.Repo

  @doc """
  Parks a file diverted out of ingest (its parsed season isn't in TMDB's
  season list) into the awaiting-mapping queue. Idempotent on `file_path` —
  re-discovering the same file updates its claims rather than duplicating.
  """
  @spec divert(map()) :: {:ok, AwaitingFile.t()} | {:error, Ecto.Changeset.t()}
  def divert(attrs) do
    case file_path(attrs) do
      nil -> Repo.insert(AwaitingFile.changeset(%AwaitingFile{}, attrs))
      path -> upsert_awaiting(path, attrs)
    end
  end

  defp upsert_awaiting(path, attrs) do
    case Repo.get_by(AwaitingFile, file_path: path) do
      nil -> Repo.insert(AwaitingFile.changeset(%AwaitingFile{}, attrs))
      existing -> Repo.update(AwaitingFile.changeset(existing, attrs))
    end
  end

  defp file_path(attrs), do: attrs[:file_path] || attrs["file_path"]

  @doc "All files still awaiting a mapping decision, oldest first."
  @spec list_awaiting() :: [AwaitingFile.t()]
  def list_awaiting do
    Repo.all(from f in AwaitingFile, where: f.status == :pending, order_by: [asc: f.inserted_at])
  end

  @doc "Pending awaiting files for one show (by series TMDB id)."
  @spec awaiting_for_tmdb(integer()) :: [AwaitingFile.t()]
  def awaiting_for_tmdb(tmdb_id) do
    Repo.all(
      from f in AwaitingFile,
        where: f.status == :pending and f.tmdb_id == ^tmdb_id,
        order_by: [asc: f.claimed_season, asc: f.claimed_episode]
    )
  end

  @doc "Marks an awaiting file resolved (its mapping was confirmed and linked)."
  @spec resolve_awaiting(AwaitingFile.t() | Ecto.UUID.t()) ::
          {:ok, AwaitingFile.t()} | {:error, Ecto.Changeset.t()}
  def resolve_awaiting(file_or_id), do: set_status(file_or_id, :resolved)

  @doc "Marks an awaiting file dismissed (the user opted not to map it)."
  @spec dismiss_awaiting(AwaitingFile.t() | Ecto.UUID.t()) ::
          {:ok, AwaitingFile.t()} | {:error, Ecto.Changeset.t()}
  def dismiss_awaiting(file_or_id), do: set_status(file_or_id, :dismissed)

  defp set_status(%AwaitingFile{} = file, status) do
    file |> AwaitingFile.changeset(%{status: status}) |> Repo.update()
  end

  defp set_status(id, status) when is_binary(id) do
    set_status(Repo.get!(AwaitingFile, id), status)
  end

  @doc """
  Assembles the full read model for one show's mapping review: loads the
  awaiting files, resolves the library series (for the present-set),
  assembles the TMDB spine, and runs the engine. Returns a `ShowReview`.

  `opts[:pinned]` (a list of `Placement`) is threaded into the engine for
  in-session partial-accept — models re-propose around those nodes.
  """
  @spec resolve_show(integer(), keyword()) :: ShowReview.t()
  def resolve_show(tmdb_id, opts \\ []) do
    awaiting = awaiting_for_tmdb(tmdb_id)
    series = Library.find_by_external_id(:tv_series, to_string(tmdb_id))
    present_keys = if series, do: Library.present_episode_keys(series.id), else: MapSet.new()

    spine = Spine.assemble(tmdb_id, present_keys)
    artifacts = Enum.map(awaiting, &to_artifact/1)
    resolution = Engine.resolve(spine, artifacts, Keyword.take(opts, [:pinned]))

    %ShowReview{
      tmdb_id: tmdb_id,
      series_title: series_title(series, awaiting),
      tv_series_id: series && series.id,
      awaiting_files: awaiting,
      spine: spine,
      resolution: resolution
    }
  end

  defp to_artifact(%AwaitingFile{} = file) do
    %Artifact{
      id: file.id,
      claimed_season: file.claimed_season,
      claimed_episode: file.claimed_episode,
      claimed_title: file.claimed_title
    }
  end

  defp series_title(nil, [%AwaitingFile{series_title: title} | _]), do: title
  defp series_title(nil, _awaiting), do: nil
  defp series_title(series, _awaiting), do: series.name

  @doc """
  Confirms the engine's recommended mapping for a show — the one-click
  "looks right" path. Equivalent to `confirm/2` with the recommended
  placements as targets.
  """
  @spec confirm_recommended(ShowReview.t()) ::
          {:ok, %{linked: non_neg_integer(), failed: non_neg_integer()}}
          | {:error, :series_not_in_library}
  def confirm_recommended(%ShowReview{tv_series_id: nil}), do: {:error, :series_not_in_library}

  def confirm_recommended(%ShowReview{resolution: %{recommended: nil}}),
    do: {:ok, %{linked: 0, failed: 0}}

  def confirm_recommended(%ShowReview{resolution: %{recommended: recommended}} = review) do
    targets = Map.new(recommended.placements, &{&1.artifact_id, {&1.season, &1.episode}})
    confirm(review, targets)
  end

  @doc """
  Links the chosen files to their canonical episodes and resolves their
  awaiting records. `targets` maps an awaiting-file id to a
  `{season, episode}` canonical node — supporting per-file override and
  partial-accept (omit a file to leave it pending).

  A confirmed mapping **materializes the real TMDB episode** (creating the
  season/episode row from the spine title when the library hadn't imported
  it yet) and links the file — it never fabricates a phantom season. Each
  file is linked independently, so a single failure doesn't roll back the
  others (matching partial-accept semantics).
  """
  @spec confirm(ShowReview.t(), %{Ecto.UUID.t() => {integer(), integer()}}) ::
          {:ok, %{linked: non_neg_integer(), failed: non_neg_integer()}}
          | {:error, :series_not_in_library}
  def confirm(%ShowReview{tv_series_id: nil}, _targets), do: {:error, :series_not_in_library}

  def confirm(%ShowReview{} = review, targets) do
    awaiting_by_id = Map.new(review.awaiting_files, &{&1.id, &1})
    title_by_node = Map.new(review.spine, &{{&1.season, &1.episode}, &1.title})

    results =
      Enum.map(targets, fn {awaiting_id, {season, episode}} ->
        link_one(
          review.tv_series_id,
          awaiting_by_id[awaiting_id],
          season,
          episode,
          title_by_node[{season, episode}]
        )
      end)

    linked = Enum.count(results, &(&1 == :ok))
    {:ok, %{linked: linked, failed: length(results) - linked}}
  end

  defp link_one(_tv_series_id, nil, _season, _episode, _title), do: :error

  defp link_one(tv_series_id, %AwaitingFile{} = file, season, episode_number, title) do
    with {:ok, episode} <- ensure_episode(tv_series_id, season, episode_number, title),
         {:ok, playable_item_id} <- ensure_episode_playable_item(episode),
         {:ok, _watched} <-
           Library.link_file(%{
             file_path: file.file_path,
             media_dir: file.media_dir,
             playable_item_id: playable_item_id
           }),
         {:ok, _resolved} <- resolve_awaiting(file) do
      :ok
    else
      _ -> :error
    end
  end

  defp ensure_episode(tv_series_id, season_number, episode_number, title) do
    with {:ok, season} <-
           Library.find_or_create_season_for_tv_series(%{
             tv_series_id: tv_series_id,
             season_number: season_number,
             name: "Season #{season_number}"
           }) do
      case Library.find_episode_by_season_episode(tv_series_id, season_number, episode_number) do
        nil ->
          Library.create_episode(%{
            season_id: season.id,
            episode_number: episode_number,
            name: title
          })

        episode ->
          {:ok, episode}
      end
    end
  end

  defp ensure_episode_playable_item(episode) do
    case Library.create_playable_item(%{
           container_type: :episode,
           container_id: episode.id,
           position: episode.episode_number || 1
         }) do
      {:ok, item} ->
        {:ok, item.id}

      {:error, %Ecto.Changeset{}} ->
        case Library.list_playable_items_for(:episode, episode.id) do
          [item | _] -> {:ok, item.id}
          [] -> :error
        end
    end
  end
end
