defmodule MediaCentaur.Players.Pairing do
  @moduledoc """
  The open pairing code, one per install: the process that holds it.

  The owner starts pairing in Settings → Players, which mints a
  `Pairing.Code`; the device offers the digits on the pairing page.
  Expiry and the attempt budget are the code's own (`Pairing.Code`);
  this process only holds the current one and answers with the clock.
  Every change to the open code is broadcast by `Players` as
  `PairingChanged`, so the Settings section follows it live.

  Public API only (ADR-026): `start/0`, `current/0`, `redeem/1`,
  `cancel/0`. Nothing here touches the database; `Players.pair/2` turns
  a redeemed code into a row.
  """
  use GenServer

  alias MediaCentaur.Players.Pairing.Code

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Mints a new code, replacing any open one."
  @spec start() :: Code.t()
  def start, do: GenServer.call(__MODULE__, :start)

  @doc "The open code, or nil when none is open or the open one has expired."
  @spec current() :: Code.t() | nil
  def current, do: GenServer.call(__MODULE__, :current)

  @doc """
  Offers `attempt` against the open code. `:ok` consumes the code. A miss
  spends one attempt; the last miss, or an expired code, closes it, and
  `{:error, :invalid_code, :closed}` says so, so the caller can broadcast
  the closing. `{:error, :invalid_code, :open}` is a miss with attempts
  left, or no code open at all.
  """
  @spec redeem(String.t()) :: :ok | {:error, :invalid_code, :open | :closed}
  def redeem(attempt) when is_binary(attempt), do: GenServer.call(__MODULE__, {:redeem, attempt})

  @doc "Closes the open code. `true` when one was open."
  @spec cancel() :: boolean()
  def cancel, do: GenServer.call(__MODULE__, :cancel)

  @impl true
  def init(nil), do: {:ok, %{code: nil}}

  @impl true
  def handle_call(:start, _from, state) do
    code = Code.new(DateTime.utc_now())
    {:reply, code, %{state | code: code}}
  end

  def handle_call(:current, _from, state) do
    {:reply, open_code(state), state}
  end

  def handle_call({:redeem, attempt}, _from, state) do
    case open_code(state) do
      nil ->
        {:reply, {:error, :invalid_code, :open}, %{state | code: nil}}

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
    {:reply, open_code(state) != nil, %{state | code: nil}}
  end

  defp open_code(%{code: nil}), do: nil

  defp open_code(%{code: code}) do
    if Code.open?(code, DateTime.utc_now()), do: code
  end
end
