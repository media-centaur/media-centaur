defmodule MediaCentaur.Players.Pairing do
  @moduledoc """
  The open pairing code, one per install: the process that holds it.

  The owner starts pairing in Settings → Players, which mints a
  `Pairing.Code`; the device offers the digits on the pairing page.
  Expiry and the attempt budget are the code's own (`Pairing.Code`);
  this process only holds the current one and answers with the clock.
  Every change to the open code is broadcast as `PairingChanged`, so the
  Settings section follows it live: by `Players` for what a caller did,
  and from here when the code's time runs out, the one change no caller
  makes.

  Public API only (ADR-026): `start/0`, `current/0`, `redeem/1`,
  `cancel/0`. Nothing here touches the database; `Players.pair/2` turns
  a redeemed code into a row.
  """
  use GenServer

  alias MediaCentaur.Players.Events
  alias MediaCentaur.Players.Pairing.Code

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Mints a new code, replacing any open one."
  @spec start() :: Code.t()
  def start, do: GenServer.call(__MODULE__, :start)

  @doc """
  The open code, or nil when none is open or the open one has expired —
  or when remote players is off and this process is not running (ADR-081).
  """
  @spec current() :: Code.t() | nil
  def current, do: if_running(fn -> GenServer.call(__MODULE__, :current) end, nil)

  @doc """
  Offers `attempt` against the open code. `:ok` consumes the code. A miss
  spends one attempt; the last miss, or an expired code, closes it, and
  `{:error, :invalid_code, :closed}` says so, so the caller can broadcast
  the closing. `{:error, :invalid_code, :open}` is a miss with attempts
  left, or no code held at all.
  """
  @spec redeem(String.t()) :: :ok | {:error, :invalid_code, :open | :closed}
  def redeem(attempt) when is_binary(attempt), do: GenServer.call(__MODULE__, {:redeem, attempt})

  @doc "Closes the code held, expired or not. `true` when there was one; false when none, or the feature is off."
  @spec cancel() :: boolean()
  def cancel, do: if_running(fn -> GenServer.call(__MODULE__, :cancel) end, false)

  @doc false
  # The code's time as if it had run out, its timer not yet fired.
  def __backdate_for_test__, do: GenServer.call(__MODULE__, :backdate)

  @doc false
  # The timer firing, without waiting out the code's lifetime.
  def __expire_for_test__, do: GenServer.call(__MODULE__, :expire)

  # Reading the code is a question anyone may ask; minting and redeeming
  # reach here only through surfaces the feature gates.
  defp if_running(call, absent) do
    if GenServer.whereis(__MODULE__), do: call.(), else: absent
  end

  @impl true
  def init(nil), do: {:ok, %{code: nil}}

  @impl true
  def handle_call(:start, _from, state) do
    code = Code.new(DateTime.utc_now())
    Process.send_after(self(), {:expire, code.expires_at}, to_timeout(minute: Code.lifetime_minutes()))
    {:reply, code, %{state | code: code}}
  end

  def handle_call(:current, _from, state) do
    {:reply, open_code(state), state}
  end

  def handle_call({:redeem, attempt}, _from, state) do
    case state.code do
      nil ->
        {:reply, {:error, :invalid_code, :open}, state}

      code ->
        case Code.redeem(code, attempt, DateTime.utc_now()) do
          :ok ->
            {:reply, :ok, %{state | code: nil}}

          {:miss, missed} ->
            {:reply, {:error, :invalid_code, :open}, %{state | code: missed}}

          closed when closed in [:spent, :expired] ->
            {:reply, {:error, :invalid_code, :closed}, %{state | code: nil}}
        end
    end
  end

  def handle_call(:cancel, _from, state) do
    {:reply, state.code != nil, %{state | code: nil}}
  end

  def handle_call(:backdate, _from, %{code: code} = state) do
    {:reply, :ok, %{state | code: %{code | expires_at: DateTime.add(DateTime.utc_now(), -1, :second)}}}
  end

  def handle_call(:expire, _from, %{code: code} = state) do
    send(self(), {:expire, code.expires_at})
    {:reply, :ok, state}
  end

  # A timer names the code it was set for: one replaced since has a later
  # expiry, and its timer finds nothing here to close.
  @impl true
  def handle_info({:expire, expires_at}, %{code: %Code{expires_at: expires_at}} = state) do
    Events.broadcast(%Events.PairingChanged{code: nil})
    {:noreply, %{state | code: nil}}
  end

  def handle_info({:expire, _replaced}, state), do: {:noreply, state}

  defp open_code(%{code: nil}), do: nil

  defp open_code(%{code: code}) do
    if Code.open?(code, DateTime.utc_now()), do: code
  end
end
