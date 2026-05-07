defmodule MediaCentarr.Acquisition.Pursuits.InboundListener do
  @moduledoc """
  Bridge from `pipeline:publish` events to `IdentityVerifier` jobs.

  Subscribes to `Topics.pipeline_publish/0` and, for each
  `{:entity_published, event}`, looks up active pursuits whose target
  matches the event's TMDB identifier (and, for TV, season + episode)
  and enqueues an `IdentityVerifier` Oban job per match. The verifier
  runs asynchronously and either satisfies or cancels the pursuit.

  The listener is intentionally thin — it derives a target map and
  delegates the read to `Pursuits.find_active_for_target/1` and the
  decision to the verifier. It contains no domain logic.
  """

  use GenServer
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.IdentityVerifier

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.pipeline_publish())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:entity_published, event}, state) do
    dispatch(event)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @doc """
  Dispatches `IdentityVerifier` jobs for every active pursuit matching
  the event. Returns the number of jobs enqueued. Returns `0` when the
  event does not name a TMDB-backed entity, when no pursuits match, or
  when all matching pursuits are in terminal/awaiting states.
  """
  @spec dispatch(map()) :: non_neg_integer()
  def dispatch(event) do
    case target_for(event) do
      nil ->
        0

      target ->
        target
        |> Pursuits.find_active_for_target()
        |> Enum.reduce(0, fn pursuit, acc ->
          case enqueue_for(pursuit, event[:file_path] || event["file_path"]) do
            {:ok, _job} ->
              Log.info(
                :acquisition,
                "identity verification queued — #{pursuit.title} (#{pursuit.id})"
              )

              acc + 1

            {:error, reason} ->
              Log.warning(
                :acquisition,
                "identity verification enqueue failed — #{pursuit.id}: #{inspect(reason)}"
              )

              acc
          end
        end)
    end
  end

  defp target_for(%{entity_type: :movie, identifier: %{source: "tmdb", external_id: id}})
       when not is_nil(id) do
    %{tmdb_id: to_string(id), tmdb_type: "movie"}
  end

  defp target_for(%{
         entity_type: :tv_series,
         identifier: %{source: "tmdb", external_id: id},
         season: %{season_number: season, episode: %{attrs: %{episode_number: episode}}}
       })
       when not is_nil(id) and is_integer(season) and is_integer(episode) do
    %{
      tmdb_id: to_string(id),
      tmdb_type: "tv",
      season_number: season,
      episode_number: episode
    }
  end

  defp target_for(%{
         entity_type: :tv_series,
         identifier: %{source: "tmdb", external_id: id},
         season: %{season_number: season}
       })
       when not is_nil(id) and is_integer(season) do
    %{tmdb_id: to_string(id), tmdb_type: "tv", season_number: season}
  end

  defp target_for(_), do: nil

  defp enqueue_for(_pursuit, nil), do: {:error, :no_file_path}

  defp enqueue_for(pursuit, file_path) when is_binary(file_path) do
    %{"pursuit_id" => pursuit.id, "file_path" => file_path}
    |> IdentityVerifier.new()
    |> Oban.insert()
  end
end
