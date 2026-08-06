defmodule MediaCentaur.Pipeline.Stages.Ingest do
  @moduledoc """
  Pipeline stage 4: publishes enriched metadata for library ingestion.

  Broadcasts `{:entity_published, event}` to `"pipeline:publish"`.
  `Library.Inbound` subscribes and creates all library records.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Reconciliation

  @behaviour MediaCentaur.Pipeline.Stage

  @spec run(Payload.t()) :: {:ok, Payload.t()}
  @impl true
  def run(%Payload{} = payload) do
    Log.info(:pipeline, "publishing entity for tmdb:#{payload.tmdb_id}")

    event = %{
      entity_type: payload.metadata.entity_type,
      entity_attrs: payload.metadata.entity_attrs,
      identifier: payload.metadata.identifier,
      images: payload.metadata.images,
      season: payload.metadata.season,
      child_movie: payload.metadata.child_movie,
      extra: payload.metadata.extra,
      file_path: payload.file_path,
      media_dir: payload.media_directory
    }

    MediaCentaur.Topics.publish(
      MediaCentaur.Topics.pipeline_publish(),
      {:entity_published, event}
    )

    maybe_divert(payload)

    Log.info(:pipeline, "published entity event for tmdb:#{payload.tmdb_id}")

    {:ok, payload}
  end

  # A TV file whose parsed season isn't in TMDB's canonical season list was
  # flagged by `FetchMetadata` (the `divert` payload). The published event
  # carries `season: nil`, so `Library.Inbound` creates the series but no
  # phantom season and links nothing; here we park the file in the
  # reconciliation queue for show-scoped episode mapping.
  defp maybe_divert(%Payload{metadata: %{divert: claims}} = payload) when is_map(claims) do
    Reconciliation.divert(
      Map.merge(claims, %{file_path: payload.file_path, media_dir: payload.media_directory})
    )

    Log.info(:pipeline, "parked file for reconciliation — tmdb:#{payload.tmdb_id}")
  end

  defp maybe_divert(_payload), do: :ok
end
