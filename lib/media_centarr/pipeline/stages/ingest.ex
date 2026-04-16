defmodule MediaCentarr.Pipeline.Stages.Ingest do
  @moduledoc """
  Pipeline stage 5: publishes enriched metadata for library ingestion.

  Broadcasts `{:entity_published, event}` to `"pipeline:publish"`.
  `Library.Inbound` subscribes and creates all library records.
  """
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Pipeline.Payload

  @spec run(Payload.t()) :: {:ok, Payload.t()}
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
      watch_dir: payload.watch_directory
    }

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.pipeline_publish(),
      {:entity_published, event}
    )

    Log.info(:pipeline, "published entity event for tmdb:#{payload.tmdb_id}")

    {:ok, payload}
  end
end
