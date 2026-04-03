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

  See `PIPELINE.md` for full architecture details.
  """
  use Broadway
  require MediaCentaur.Log, as: Log

  import Ecto.Query

  alias MediaCentaur.DateUtil
  alias MediaCentaur.Library.WatchedFile
  alias MediaCentaur.Pipeline.{Payload, Stage}
  alias MediaCentaur.Pipeline.Stages.{Parse, Search}
  alias MediaCentaur.Repo

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
        Log.warning(
          :pipeline,
          "discovery — failed for #{Path.basename(payload.file_path)}: #{inspect(reason)}"
        )

        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    matched =
      Enum.filter(messages, fn message ->
        message.data.tmdb_id != nil and message.data.confidence != nil
      end)

    Enum.each(matched, fn message ->
      payload = message.data

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        MediaCentaur.Topics.pipeline_matched(),
        {:file_matched,
         %{
           file_path: payload.file_path,
           watch_dir: payload.watch_directory,
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
        {:ok, payload} -> {:matched, payload}
        {:needs_review, payload} -> handle_needs_review(payload)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp run_discovery(payload) do
    with {:ok, payload} <- Stage.run(:parse, Parse, payload),
         result <- Stage.run(:search, Search, payload) do
      result
    end
  end

  defp handle_needs_review(payload) do
    :telemetry.execute([:media_centaur, :pipeline, :needs_review], %{}, %{
      file_path: payload.file_path
    })

    attrs = build_review_attrs(payload)

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.review_intake(),
      {:needs_review, attrs}
    )

    {:needs_review, payload}
  end

  defp build_review_attrs(payload) do
    {search_title, search_year} = search_params(payload.parsed)

    %{
      file_path: payload.file_path,
      watch_directory: payload.watch_directory,
      parsed_title: search_title,
      parsed_year: search_year,
      parsed_type: type_to_string(payload.parsed.type),
      season_number: payload.parsed.season,
      episode_number: payload.parsed.episode,
      tmdb_id: payload.tmdb_id,
      tmdb_type: type_to_string(payload.tmdb_type),
      confidence: payload.confidence,
      match_title: payload.match_title,
      match_year: payload.match_year,
      match_poster_path: payload.match_poster_path,
      candidates: normalize_candidates(payload.candidates)
    }
  end

  defp search_params(%{type: :extra, parent_title: title, parent_year: year}), do: {title, year}
  defp search_params(%{title: title, year: year}), do: {title, year}

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
    from(w in WatchedFile,
      where:
        w.file_path == ^file_path and
          (not is_nil(w.movie_id) or not is_nil(w.tv_series_id) or
             not is_nil(w.movie_series_id) or not is_nil(w.video_object_id)),
      limit: 1
    )
    |> Repo.exists?()
  end
end
