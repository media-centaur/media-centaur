defmodule MediaCentaur.IntegrationAvailability.Status do
  @moduledoc """
  One integration's availability: `:up`, or `{:down, since, reason}`.

  A pure value. `fold/4` folds one observation into it and says whether
  the state changed, so the store (`MediaCentaur.IntegrationAvailability`)
  can write and broadcast only on transitions. The onset `since` survives
  consecutive down observations — one outage stays one outage even when
  its reason moves (unreachable, then blind, as a dead VPN presents).

  `observed_at` is `nil` until something actually observes the
  integration: `initial/1` is the optimistic starting point, not an
  observation, and must not claim one.

  Reasons: `:unreachable` (transport error, 5xx, timeout), `:rejected`
  (401/403 — misconfigured is as useless as dead for held work),
  `:blind` (Prowlarr answers but every enabled indexer is backed off;
  `retry_at` carries Prowlarr's own retry time), `:client_unavailable`
  (Prowlarr cannot hand a release to the download client).
  """

  @enforce_keys [:integration, :state]
  defstruct [:integration, :state, :observed_at, :retry_at]

  @type integration :: :prowlarr | {:handoff, :usenet | :torrent} | :tmdb
  @type reason :: :unreachable | :rejected | :blind | :client_unavailable
  @type observation :: :up | {:down, reason()}
  @type state :: :up | {:down, DateTime.t(), reason()}
  @type t :: %__MODULE__{
          integration: integration(),
          state: state(),
          observed_at: DateTime.t() | nil,
          retry_at: DateTime.t() | nil
        }

  @doc "The status before any observation: up, and observed never."
  @spec initial(integration()) :: t()
  def initial(integration), do: %__MODULE__{integration: integration, state: :up, observed_at: nil}

  @spec up?(t()) :: boolean()
  def up?(%__MODULE__{state: :up}), do: true
  def up?(%__MODULE__{}), do: false

  @doc """
  Folds one observation. Returns `{:changed, status}` on an up/down
  transition, `{:unchanged, status}` otherwise. `opts[:retry_at]` is
  kept on a down status and cleared on up.
  """
  @spec fold(t(), observation(), DateTime.t(), keyword()) :: {:changed | :unchanged, t()}
  def fold(%__MODULE__{state: :up} = status, :up, now, _opts),
    do: {:unchanged, %{status | observed_at: now}}

  def fold(%__MODULE__{state: {:down, _since, _reason}} = status, :up, now, _opts),
    do: {:changed, %{status | state: :up, observed_at: now, retry_at: nil}}

  def fold(%__MODULE__{state: :up} = status, {:down, reason}, now, opts),
    do: {:changed, %{status | state: {:down, now, reason}, observed_at: now, retry_at: opts[:retry_at]}}

  def fold(%__MODULE__{state: {:down, since, _reason}} = status, {:down, reason}, now, opts),
    do:
      {:unchanged,
       %{status | state: {:down, since, reason}, observed_at: now, retry_at: opts[:retry_at]}}
end
