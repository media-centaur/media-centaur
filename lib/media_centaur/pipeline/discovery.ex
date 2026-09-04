defmodule MediaCentaur.Pipeline.Discovery do
  @moduledoc """
  Broadway pipeline that identifies what a file is — parses the filename,
  searches TMDB, and determines if it's a match or needs review.

  Processing flow: dedup check → parse → search.
  High-confidence matches emit `{:file_matched, ...}` to `"pipeline:matched"`.
  Low-confidence matches stop at needs_review for human approval.

  Broadway config: 1 producer (PubSub subscriber), 10 processors (partitioned
  by file path), 1 batcher (serialises match broadcasts, batch size 10,
  timeout 5s).

  See `docs/pipeline.md` for full architecture details.
  """
  use Broadway
  require MediaCentaur.Log, as: Log

  import Ecto.Query

  alias MediaCentaur.DateUtil
  alias MediaCentaur.Library.{ExtraFile, WatchedFile}
  alias MediaCentaur.Pipeline.{Payload, Stage}
  alias MediaCentaur.Pipeline.Stages.{Parse, Search}
  alias MediaCentaur.Repo
  alias MediaCentaur.Review.PendingFile

  @processor_concurrency 10

  def processor_concurrency, do: @processor_concurrency

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {MediaCentaur.Pipeline.Discovery.Producer, []},
        concurrency: 1
      ],
      processors: [default: [concurrency: @processor_concurrency, partition_by: &partition_key/1]],
      batchers: [default: [concurrency: 1, batch_size: 10, batch_timeout: 5_000]]
    )
  end

  @impl true
  def handle_message(:default, message, _context) do
    payload = message.data
    Log.info(:pipeline, "discovery — processing #{Path.basename(payload.file_path)}")

    case process(payload) do
      {:matched, payload} ->
        Log.info(:pipeline, "discovery — matched #{Path.basename(payload.file_path)}")
        Broadway.Message.update_data(message, fn _ -> payload end)

      :skipped ->
        Broadway.Message.update_data(message, fn _ -> payload end)

      {:needs_review, payload} ->
        Log.info(:pipeline, "discovery — needs review #{Path.basename(payload.file_path)}")
        Broadway.Message.update_data(message, fn _ -> payload end)

      {:error, reason} ->
        log_failure(reason, payload.file_path)
        Broadway.Message.failed(message, reason)
    end
  end

  @doc """
  True for TMDB error reasons that indicate an authentication problem
  (HTTP 401 / 403) — operators see these as `:tmdb` error log entries
  instead of buried `:pipeline` warnings, so a rejected API key is
  immediately obvious in the Console drawer.
  """
  @spec auth_failure?(term()) :: boolean()
  def auth_failure?({:http_error, status, _}) when status in [401, 403], do: true
  def auth_failure?(_), do: false

  defp log_failure(reason, file_path) do
    basename = Path.basename(file_path)

    if auth_failure?(reason) do
      {:http_error, status, _} = reason

      Log.error(
        :pipeline,
        "TMDB API key rejected (HTTP #{status}) — discovery failed for #{basename}; " <>
          "fix Settings → TMDB and the file will retry on the next key save or BEAM restart"
      )
    else
      Log.warning(:pipeline, "discovery — failed for #{basename}: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    # Discriminate on the discovery outcome, never on field presence: a
    # needs_review payload with a candidate also carries tmdb_id and
    # confidence (for the review UI), and broadcasting it here would
    # import the file behind the reviewer's back, stranding its
    # PendingFile in the queue forever.
    matched = Enum.filter(messages, fn message -> message.data.discovery_status == :matched end)

    Enum.each(matched, fn message ->
      payload = message.data

      MediaCentaur.Topics.publish(
        MediaCentaur.Topics.pipeline_matched(),
        {:file_matched,
         %{
           file_path: payload.file_path,
           media_dir: payload.media_directory,
           tmdb_id: payload.tmdb_id,
           tmdb_type: payload.tmdb_type,
           pending_file_id: nil
         }}
      )
    end)

    if matched != [] do
      Log.info(:pipeline, "discovery — broadcast #{length(matched)} matches")
    end

    messages
  end

  defp partition_key(%Broadway.Message{data: %Payload{file_path: path}}) do
    :erlang.phash2(path)
  end

  @doc """
  Processes a single payload through the Discovery pipeline.

  Returns:
  - `{:matched, payload}` — high-confidence TMDB match found
  - `{:needs_review, payload}` — low confidence or no results
  - `:skipped` — file already linked to an entity
  - `{:error, reason}` — TMDB failure or parse error
  """
  def process(%Payload{} = payload) do
    if already_linked?(payload.file_path) do
      Log.info(:pipeline, "skipped #{Path.basename(payload.file_path)} — already linked")
      :skipped
    else
      case run_discovery(payload) do
        {:ok, payload} ->
          {:matched, %{payload | discovery_status: :matched}}

        {:needs_review, payload} ->
          handle_needs_review(%{payload | discovery_status: :needs_review})

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp run_discovery(payload) do
    with {:ok, payload} <- Stage.run(:parse, Parse, payload) do
      result = Stage.run(:search, Search, payload)
      result
    end
  end

  defp handle_needs_review(payload) do
    :telemetry.execute([:media_centaur, :pipeline, :needs_review], %{}, %{
      file_path: payload.file_path
    })

    attrs = build_review_attrs(payload)

    MediaCentaur.Topics.publish(
      MediaCentaur.Topics.review_intake(),
      {:needs_review, attrs}
    )

    {:needs_review, payload}
  end

  defp build_review_attrs(payload) do
    Map.merge(PendingFile.parsed_attrs(payload.parsed), %{
      file_path: payload.file_path,
      media_directory: payload.media_directory,
      tmdb_id: payload.tmdb_id,
      tmdb_type: type_to_string(payload.tmdb_type),
      confidence: payload.confidence,
      match_title: payload.match_title,
      match_year: payload.match_year,
      match_poster_path: payload.match_poster_path,
      candidates: normalize_candidates(payload.candidates)
    })
  end

  defp type_to_string(nil), do: nil
  defp type_to_string(type) when is_atom(type), do: Atom.to_string(type)
  defp type_to_string(type) when is_binary(type), do: type

  defp normalize_candidates(nil), do: []
  defp normalize_candidates([]), do: []

  defp normalize_candidates(candidates) do
    Enum.map(candidates, &normalize_candidate/1)
  end

  defp normalize_candidate({raw_result, score, title_key}) do
    year_key = if title_key == "title", do: "release_date", else: "first_air_date"

    %{
      "tmdb_id" => raw_result["id"],
      "title" => raw_result[title_key],
      "year" => DateUtil.extract_year(raw_result[year_key]),
      "score" => score,
      "poster_path" => raw_result["poster_path"],
      "overview" => raw_result["overview"]
    }
  end

  defp already_linked?(file_path) do
    # Post-Phase-2-Task-B every WatchedFile carries a non-null
    # `playable_item_id` (the column is NOT NULL at the schema level),
    # so the legacy "any per-type FK set" disjunction collapses to a
    # simple existence check by path. The parallel ExtraFile path
    # (bonus features ingested via a different writer) also short-
    # circuits the pipeline — once a file is owned by either, the
    # presence-unification campaign Phase 5 requires Discovery to
    # treat it as done.
    Repo.exists?(from(w in WatchedFile, where: w.file_path == ^file_path, limit: 1)) or
      Repo.exists?(from(e in ExtraFile, where: e.file_path == ^file_path, limit: 1))
  end
end
