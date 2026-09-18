defmodule MediaCentaur.TMDB.Availability do
  @moduledoc """
  The one writer of `:tmdb` availability
  (`MediaCentaur.IntegrationAvailability`).

  `MediaCentaur.TMDB.Client` calls `observe_request/1` after every request
  it makes, and `MediaCentaur.TMDB.ProbeJob` keeps the value current with
  a `GET /configuration` every five minutes while down.

  Two rules keep the value honest:

    * **A cache hit is not evidence.** The response cache answers without
      asking TMDB anything (`HttpClient.Cache.outcome/1` grades it
      `:hit`), so it can neither open nor close the value.
    * **The image CDN never writes here.** `image.tmdb.org` is a
      different host from `api.themoviedb.org`; a failed artwork download
      says nothing about the API, and holding every metadata refresh on
      it would be the wrong blame. Artwork is held anyway, because the
      detail fetch it follows is.

  A 4xx that is not 401/403 is about the request — an unknown id — so it
  neither opens the value nor closes it: TMDB answering one 404 is no
  proof an outage is over, and the probe is what says so.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status
  alias MediaCentaur.TMDB.ProbeJob

  @type outcome :: {:ok, atom()} | {:error, term()}

  @doc "Folds one request outcome into `:tmdb`."
  @spec observe_request(outcome()) :: :unchanged | {:changed, Status.state()}
  def observe_request({:ok, :hit}), do: :unchanged
  def observe_request({:ok, _network}), do: report(:up)

  def observe_request({:error, {:http_error, status, _body}}) when status in [401, 403],
    do: report({:down, :rejected})

  def observe_request({:error, {:http_error, 429, _body}}), do: report({:down, :rate_limited})

  def observe_request({:error, {:http_error, status, _body}}) when status >= 500,
    do: report({:down, :unreachable})

  def observe_request({:error, {:http_error, _status, _body}}), do: :unchanged
  def observe_request({:error, _transport}), do: report({:down, :unreachable})

  defp report(observation) do
    case IntegrationAvailability.report(:tmdb, observation) do
      {:changed, {:down, _since, _reason}} = changed ->
        enqueue_probe()
        changed

      other ->
        other
    end
  end

  defp enqueue_probe do
    if Capabilities.tmdb_ready?() do
      job = ProbeJob.new(%{}, schedule_in: ProbeJob.cadence_seconds())

      # The enqueue sits on the request path: a database hiccup must cost
      # the probe, never the request that observed the outage.
      case Oban.insert(job) do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Log.warning(:tmdb, "probe not enqueued for tmdb — #{inspect(reason)}", mc_incident: :skip)
      end
    end

    :ok
  end
end
