defmodule MediaCentaur.Search.IndexerHealth do
  @moduledoc """
  The search provider's capability health — whether a live search can
  actually see any indexer right now (UIDR-016).

  Prowlarr's `/api/v1/search` returns `200 []` both for "no releases
  exist" and for "every indexer I'd ask is failing or backed off" — the
  two are indistinguishable from the response alone. This module makes
  the distinction observable: `check/1` snapshots Prowlarr's indexer
  roster and per-indexer back-off state (`Prowlarr.indexer_snapshot/1`),
  classifies it, and caches the observation so renderers and the
  `:subsystem` incident track (`Search.IncidentContext`, ADR-054) share
  one assessment.

  ## States

    * `:ok` — at least one enabled indexer is live.
    * `:degraded` — some enabled indexers are backed off after failures,
      others are live. Searches run but see less than they should.
    * `:blind` — every enabled indexer is backed off. Searches "succeed"
      with zero results without asking anyone.
    * `:unconfigured` — Prowlarr has no enabled indexers. Structurally
      blind, but a setup state rather than a fault, so it is not a
      `problem?/1`.
    * `:unreachable` — the Prowlarr API itself could not be reached.

  `blind?/1` groups the states in which a search result is meaningless
  (`:blind`, `:unreachable`) — the plan flow uses it to stop presenting
  an empty result as knowledge.

  ## Cache

  The latest observation lives in `:persistent_term` (runtime-only, in
  keeping with this boundary's no-durable-state rule). `cache_put/1`
  tracks the fault onset: `since` survives consecutive faulty
  observations (a dead VPN can present as `:unreachable` then `:blind`
  — one outage) and resets on recovery, giving the incident track its
  grace-window anchor.
  """

  alias MediaCentaur.Search.Prowlarr

  @enforce_keys [:state, :checked_at]
  defstruct [:state, :checked_at, :retry_at, :since, :reason, enabled_count: 0, backed_off: []]

  @type state :: :ok | :degraded | :blind | :unconfigured | :unreachable

  @type backed_off :: %{name: String.t(), retry_at: DateTime.t() | nil}

  @type t :: %__MODULE__{
          state: state(),
          checked_at: DateTime.t(),
          retry_at: DateTime.t() | nil,
          since: DateTime.t() | nil,
          reason: term(),
          enabled_count: non_neg_integer(),
          backed_off: [backed_off()]
        }

  @cache_key {__MODULE__, :cached}

  @doc """
  Snapshots Prowlarr's indexer state, classifies it, and caches the
  observation. Returns the cached struct (with `since` onset applied).
  """
  @spec check(Req.Request.t()) :: t()
  def check(client \\ Prowlarr.default_client()) do
    now = DateTime.utc_now(:second)

    health =
      case Prowlarr.indexer_snapshot(client) do
        {:ok, %{indexers: indexers, backoffs: backoffs}} -> classify(indexers, backoffs, now)
        {:error, reason} -> unreachable(reason, now)
      end

    cache_put(health)
  end

  @doc """
  Pure classification of an indexer roster against its back-off state.
  A back-off counts only for an *enabled* indexer and only while its
  `disabled_till` is still in the future. `retry_at` is the soonest an
  affected indexer comes back.
  """
  @spec classify([map()], [map()], DateTime.t()) :: t()
  def classify(indexers, backoffs, %DateTime{} = now) do
    enabled = Enum.filter(indexers, & &1.enabled)

    active_backoffs =
      Map.new(
        for backoff <- backoffs,
            match?(%DateTime{}, backoff.disabled_till),
            DateTime.after?(backoff.disabled_till, now),
            do: {backoff.indexer_id, backoff.disabled_till}
      )

    backed_off =
      for indexer <- enabled,
          retry_at = active_backoffs[indexer.id],
          not is_nil(retry_at),
          do: %{name: indexer.name, retry_at: retry_at}

    state =
      cond do
        enabled == [] -> :unconfigured
        backed_off == [] -> :ok
        length(backed_off) == length(enabled) -> :blind
        true -> :degraded
      end

    %__MODULE__{
      state: state,
      checked_at: now,
      enabled_count: length(enabled),
      backed_off: backed_off,
      retry_at: backed_off |> Enum.map(& &1.retry_at) |> Enum.min(DateTime, fn -> nil end)
    }
  end

  @doc "The observation for a Prowlarr API that could not be reached."
  @spec unreachable(term(), DateTime.t()) :: t()
  def unreachable(reason, %DateTime{} = now) do
    %__MODULE__{state: :unreachable, checked_at: now, reason: reason}
  end

  @doc "True when the state deserves user attention (UIDR-016 card)."
  @spec problem?(t() | nil) :: boolean()
  def problem?(%__MODULE__{state: state}), do: state in [:degraded, :blind, :unreachable]
  def problem?(nil), do: false

  @doc """
  True when a search result from this state is meaningless — nothing
  was actually asked (`:blind`) or askable (`:unreachable`).
  """
  @spec blind?(t() | nil) :: boolean()
  def blind?(%__MODULE__{state: state}), do: state in [:blind, :unreachable]
  def blind?(nil), do: false

  @doc """
  Caches the observation, preserving the fault onset: `since` carries
  over while consecutive observations remain faulty (`problem?/1`) and
  restarts at `checked_at` when the previous observation was healthy
  or absent.
  """
  @spec cache_put(t()) :: t()
  def cache_put(%__MODULE__{} = health) do
    health = %{health | since: onset(health, cached())}
    :persistent_term.put(@cache_key, health)
    health
  end

  @doc "The most recent observation, or `nil` before any check ran."
  @spec cached() :: t() | nil
  def cached, do: :persistent_term.get(@cache_key, nil)

  @doc "Removes the cached observation (test isolation)."
  @spec clear_cache() :: :ok
  def clear_cache do
    :persistent_term.erase(@cache_key)
    :ok
  end

  defp onset(%__MODULE__{} = health, previous) do
    cond do
      not problem?(health) -> nil
      problem?(previous) -> previous.since
      true -> health.checked_at
    end
  end
end
