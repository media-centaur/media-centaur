defmodule MediaCentaur.Library.ModalEntry do
  @moduledoc """
  Builds the detail-modal entry for an entity id — the view-model the
  detail UI opens onto.

  Reads the `Library.Views.Detail` projection rather than the tables, so
  opening a modal costs a cache read rather than a preload graph. The
  presence check is per-container-kind because "is this thing watchable"
  differs by shape: a TV series is present if any episode is, a
  collection if any movie is, a leaf if it is present itself.

  Returns `nil` for an unknown id or one whose backing files have all
  gone — the caller renders the absent state rather than an empty modal.
  """

  alias MediaCentaur.Library.{
    MediaTrackOverrides,
    Presentable,
    ProgressRecords,
    ProgressSummary,
    Views
  }

  @doc """
  Loads a single library entry shaped for the detail modal — the
  `%{entity, progress, progress_records}` triple every host LiveView
  assigns to `:selected_entry`.

  Reads from `MediaCentaur.Library.Views.Detail` (Pillar-2 ETS
  projection, microsecond reads in production; live DB-fallback in test
  mode) — probes each container kind in turn and converts the first
  match's `DetailItem` to the legacy entity-map shape via
  `Views.DetailItem.to_entity_map/1`. Progress records come from
  `list_progress_records_for_container/2`; the summary from
  `ProgressSummary.compute/2`.

  Returns `:not_found` when no container matches *and has at least one
  present file* — orphan entities (record exists, no `WatchedFile`)
  don't appear in the modal. Same gating
  `Browser.fetch_typed_entries_by_ids/1` applied pre-Phase-3.2; the
  presence check now walks the projection's `present?` flags (or
  `:seasons/:movies` trees for series containers).

  Library Schema v2 Phase 3.2 Task D flipped this from the
  `Browser + load_extras_for_entity` chain to the projection.
  `load_extras_for_entity/1` is retired — extras flow on the DetailItem
  now.
  """
  @spec load(Ecto.UUID.t()) ::
          {:ok, %{entity: map(), progress: map() | nil, progress_records: list()}}
          | :not_found
  def load(id) when is_binary(id) do
    # Route through the single presentable authority: it applies the hoist
    # rule once (so opening a hoisted collection by its series id correctly
    # lands on the sole movie), then we build the view for the resolved
    # kind. `to_entity_map/1` keys off the projection's `presented_as`, so
    # the resolved kind and the built entity always agree.
    case Presentable.resolve(id) do
      {kind, resolved_id} -> load_resolved(kind, resolved_id)
      _ -> :not_found
    end
  end

  @doc """
  Builds the modal entry for an id whose presentable kind the caller has
  already resolved via `MediaCentaur.Library.Presentable.resolve/1`.

  The detail modal's loader (`MediaCentaurWeb.Live.EntityModal`) resolves
  once to dispatch between the per-kind composers, then calls this for the
  leaf kinds — re-resolving here would repeat those queries per open.
  """
  @spec load_resolved(atom(), Ecto.UUID.t()) ::
          {:ok, %{entity: map(), progress: map() | nil, progress_records: list()}}
          | :not_found
  def load_resolved(kind, id) do
    case present_detail_for(kind, id) do
      nil -> :not_found
      item -> {:ok, build_modal_entry(kind, item, id)}
    end
  end

  defp present_detail_for(container_type, id) do
    case Views.detail_by_container(container_type, id) do
      nil ->
        nil

      %Views.DetailItem{} = item ->
        if any_present?(container_type, item), do: item
    end
  end

  defp any_present?(:tv_series, %Views.DetailItem{seasons: seasons}) do
    Enum.any?(seasons || [], fn season ->
      Enum.any?(season.episodes || [], & &1.present?)
    end)
  end

  defp any_present?(:movie_series, %Views.DetailItem{movies: movies}) do
    Enum.any?(movies || [], & &1.present?)
  end

  defp any_present?(_type, %Views.DetailItem{present?: present}), do: present == true

  defp build_modal_entry(container_type, item, id) do
    entity = item |> Views.DetailItem.to_entity_map() |> MediaTrackOverrides.put_on_entity()
    progress_records = ProgressRecords.list_for_container(container_type, id)
    progress = ProgressSummary.compute(entity, progress_records)

    %{entity: entity, progress: progress, progress_records: progress_records}
  end
end
