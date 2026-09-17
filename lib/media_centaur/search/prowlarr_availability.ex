defmodule MediaCentaur.Search.ProwlarrAvailability do
  @moduledoc """
  The one writer of `:prowlarr` and hand-off availability
  (`MediaCentaur.IntegrationAvailability`).

  `MediaCentaur.Search.Prowlarr` calls `observe_request/1` after every
  search and `observe_grab/2` after every grab;
  `MediaCentaur.Search.IndexerHealth` calls `observe_roster/1` after
  every roster read. A grab that Prowlarr answers with
  `DownloadClientUnavailableException` says Prowlarr is up and the
  hand-off for that release's protocol is down.

  On a transition to down the owner enqueues
  `MediaCentaur.Search.ProbeJob`, which keeps the status fresh with free
  requests until the integration answers again. Nothing is enqueued for
  an unconfigured Prowlarr — a missing URL fails every request instantly
  and probing it would be noise.

  `probe_handoff/1` is the hand-off probe: two requests — the download
  client list, then `downloadclient/testall`, which reaches the clients
  from inside Prowlarr's network and touches no indexer — folded per
  slot. Two rules keep it honest:

    * A slot Prowlarr has **no enabled client** for is reported **up**.
      The value means "Prowlarr's link to a client of this protocol is
      known broken"; with no client there is no link to break. A grab of
      that protocol then proceeds and fails with Prowlarr's own answer,
      which is what the user needs to see — and a slot that went down
      before its client was removed can still clear.
    * A probe request that does not complete is **inconclusive**: it
      moves neither the hand-off nor `:prowlarr`. A client the probe
      cannot reach is no evidence about Prowlarr, and holding every
      search on it would be the wrong blame. Only `observe_roster/1` and
      `observe_request/1` decide `:prowlarr`.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status
  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaur.Search.ProbeJob
  alias MediaCentaur.Search.Prowlarr

  @type verdict :: :unchanged | {:changed, Status.state()}

  @doc "Folds a search or roster request outcome into `:prowlarr`."
  @spec observe_request(:ok | {:ok, term()} | {:error, term()}) :: verdict()
  def observe_request(:ok), do: report(:prowlarr, :up)
  def observe_request({:ok, _body}), do: report(:prowlarr, :up)

  def observe_request({:error, {:http_error, status, _body}}) when status in [401, 403],
    do: report(:prowlarr, {:down, :rejected})

  def observe_request({:error, {:http_error, status, _body}}) when status >= 500,
    do: report(:prowlarr, {:down, :unreachable})

  # Any other 4xx: Prowlarr is answering; the request was wrong.
  def observe_request({:error, {:http_error, _status, _body}}), do: report(:prowlarr, :up)
  def observe_request({:error, :missing_indexer_id}), do: :unchanged
  def observe_request({:error, _transport}), do: report(:prowlarr, {:down, :unreachable})

  @doc "Folds a grab outcome for a release of `protocol` into the hand-off, and into `:prowlarr`."
  @spec observe_grab(:ok | {:error, term()}, :usenet | :torrent | nil) :: :ok
  def observe_grab(:ok, protocol) do
    report(:prowlarr, :up)
    report_handoff(protocol, :up)
    :ok
  end

  def observe_grab({:error, reason} = error, protocol) do
    cond do
      Prowlarr.download_client_unavailable?(reason) ->
        report(:prowlarr, :up)
        report_handoff(protocol, {:down, :client_unavailable})

      # Any other status — Prowlarr answered. A 5xx that is not the
      # hand-off exception is Prowlarr's own fault with this release or
      # its indexer, not evidence that Prowlarr is unreachable.
      match?({:http_error, _status, _body}, reason) ->
        report(:prowlarr, :up)

      true ->
        observe_request(error)
    end

    :ok
  end

  @doc "Folds a roster observation into `:prowlarr`."
  @spec observe_roster(IndexerHealth.t()) :: verdict()
  def observe_roster(%IndexerHealth{state: :unreachable}), do: report(:prowlarr, {:down, :unreachable})

  def observe_roster(%IndexerHealth{state: :blind, retry_at: retry_at}),
    do: report(:prowlarr, {:down, :blind}, retry_at: retry_at)

  def observe_roster(%IndexerHealth{}), do: report(:prowlarr, :up)

  @doc "The hand-off probe: test every download client Prowlarr has, fold per slot."
  @spec probe_handoff(Req.Request.t()) :: :ok | {:error, term()}
  def probe_handoff(client \\ Prowlarr.default_client()) do
    with {:ok, clients} <- Prowlarr.list_download_clients(client),
         {:ok, results} <- Prowlarr.test_download_clients(client) do
      valid_by_id = Map.new(results, &{&1.id, &1.valid?})

      for slot <- IntegrationAvailability.handoff_slots() do
        fold_slot(slot, Enum.filter(clients, &(&1.enabled and &1.protocol == slot)), valid_by_id)
      end

      :ok
    else
      {:error, reason} = error ->
        # Inconclusive — see the moduledoc. The probe job snoozes and asks again.
        Log.warning(:acquisition, "prowlarr hand-off probe inconclusive — #{inspect(reason)}",
          mc_incident: :skip
        )

        error
    end
  end

  # No enabled client of this protocol: there is no link to be broken.
  defp fold_slot(slot, [], _valid_by_id), do: IntegrationAvailability.report({:handoff, slot}, :up)

  defp fold_slot(slot, enabled, valid_by_id) do
    if Enum.all?(enabled, &Map.get(valid_by_id, &1.id, false)),
      do: IntegrationAvailability.report({:handoff, slot}, :up),
      else: IntegrationAvailability.report({:handoff, slot}, {:down, :client_unavailable})
  end

  # Prowlarr omitted the protocol: nothing to attribute the outcome to.
  defp report_handoff(nil, _observation), do: :unchanged

  defp report_handoff(protocol, observation) do
    case IntegrationAvailability.report({:handoff, protocol}, observation) do
      {:changed, {:down, _since, _reason}} = changed ->
        enqueue_probe("handoff")
        changed

      other ->
        other
    end
  end

  defp report(:prowlarr, observation, opts \\ []) do
    case IntegrationAvailability.report(:prowlarr, observation, opts) do
      {:changed, {:down, _since, _reason}} = changed ->
        enqueue_probe("prowlarr")
        changed

      other ->
        other
    end
  end

  defp enqueue_probe(integration) do
    if Capabilities.prowlarr_ready?() do
      job = ProbeJob.new(%{integration: integration}, schedule_in: ProbeJob.cadence_seconds())

      # The enqueue sits on the request path: a database hiccup must
      # cost the probe, never the search that observed the outage.
      case Oban.insert(job) do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Log.warning(:acquisition, "probe not enqueued for #{integration} — #{inspect(reason)}",
            mc_incident: :skip
          )
      end
    end

    :ok
  end
end
