defmodule MediaManager.Pipeline.Stages.Ingest do
  @moduledoc """
  Pipeline stage 5: ingests the enriched payload into the library.

  **Phase 1 bridge** — delegates to `EntityResolver.resolve/3` which handles
  entity find-or-create, identifier management, image records, and TV hierarchy.

  EntityResolver re-fetches TMDB data internally (duplicating work from the
  FetchMetadata stage). This double-fetch is acceptable for the Phase 1 bridge
  and goes away in Phase 2 when `Library.Ingress` replaces this module.
  """
  require MediaManager.Log, as: Log

  alias MediaManager.Pipeline.Payload
  alias MediaManager.Library.EntityResolver

  @spec run(Payload.t()) :: {:ok, Payload.t()} | {:error, term()}
  def run(%Payload{tmdb_id: tmdb_id, tmdb_type: tmdb_type, parsed: parsed} = payload) do
    file_context = %{
      file_path: parsed.file_path,
      season_number: parsed.season,
      episode_number: parsed.episode,
      extra_title: if(parsed.type == :extra, do: parsed.title, else: nil)
    }

    parsed_type = effective_type(tmdb_type, parsed)

    Log.info(:pipeline, "ingesting tmdb:#{tmdb_id} type:#{parsed_type}")

    case EntityResolver.resolve(tmdb_id, parsed_type, file_context) do
      {:ok, entity, status} ->
        Log.info(:pipeline, "ingested entity #{entity.id} (#{status})")

        {:ok,
         %{
           payload
           | entity_id: entity.id,
             ingest_status: status
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp effective_type(_tmdb_type, %{type: :extra}), do: :extra
  defp effective_type(tmdb_type, _parsed), do: tmdb_type
end
