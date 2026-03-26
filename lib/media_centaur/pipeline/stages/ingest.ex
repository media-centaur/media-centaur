defmodule MediaCentaur.Pipeline.Stages.Ingest do
  @moduledoc """
  Pipeline stage 5: ingests the enriched payload into the library.

  Delegates to `Library.Ingress.ingest/1` which consumes the pre-built
  metadata and staged images to create or update all library records
  without any TMDB calls.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Library.Ingress

  @spec run(Payload.t()) :: {:ok, Payload.t()} | {:error, term()}
  def run(%Payload{} = payload) do
    Log.info(:pipeline, "ingesting tmdb:#{payload.tmdb_id}")

    case Ingress.ingest(payload) do
      {:ok, entity, status, pending_images} ->
        Log.info(:pipeline, "ingested entity #{Format.short_id(entity.id)} — #{status}")

        {:ok,
         %{
           payload
           | entity_id: entity.id,
             ingest_status: status,
             pending_images: pending_images
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
