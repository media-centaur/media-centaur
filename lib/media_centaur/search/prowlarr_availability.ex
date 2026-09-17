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

  `probe_handoff/1` is the hand-off probe: one `downloadclient/testall`
  call, which reaches the clients from inside Prowlarr's network and
  touches no indexer, folded per slot.
  """

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status
  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaur.Search.ProbeJob
  alias MediaCentaur.Search.Prowlarr

  @slots [:usenet, :torrent]

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
    if Prowlarr.download_client_unavailable?(reason) do
      report(:prowlarr, :up)
      report_handoff(protocol, {:down, :client_unavailable})
    else
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

      for slot <- @slots do
        fold_slot(slot, Enum.filter(clients, &(&1.enabled and &1.protocol == slot)), valid_by_id)
      end

      :ok
    else
      {:error, _reason} = error ->
        observe_request(error)
        error
    end
  end

  # A slot Prowlarr has no enabled client for says nothing about the
  # hand-off: leave whatever the last real observation put there.
  defp fold_slot(_slot, [], _valid_by_id), do: :unchanged

  defp fold_slot(slot, enabled, valid_by_id) do
    if Enum.all?(enabled, &Map.get(valid_by_id, &1.id, false)),
      do: IntegrationAvailability.report({:handoff, slot}, :up),
      else: IntegrationAvailability.report({:handoff, slot}, {:down, :client_unavailable})
  end

  defp report_handoff(protocol, observation) when protocol in @slots do
    case IntegrationAvailability.report({:handoff, protocol}, observation) do
      {:changed, {:down, _since, _reason}} = changed ->
        enqueue_probe("handoff")
        changed

      other ->
        other
    end
  end

  # Prowlarr omitted the protocol: nothing to attribute the outcome to.
  defp report_handoff(_protocol, _observation), do: :unchanged

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
      {:ok, _job} =
        %{integration: integration}
        |> ProbeJob.new(schedule_in: ProbeJob.cadence_seconds())
        |> Oban.insert()
    end

    :ok
  end
end
