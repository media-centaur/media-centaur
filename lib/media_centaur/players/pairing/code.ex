defmodule MediaCentaur.Players.Pairing.Code do
  @moduledoc """
  One pairing code: six digits, open for `lifetime_minutes/0` from the
  instant it was minted, with `max_attempts/0` misses before it closes.
  Pure: `Pairing` (the process) holds one and asks it the questions, so
  expiry and the attempt budget are tested without a clock.

  Six digits are what a person types into a TV with a remote. The
  attempt budget is what keeps six digits enough: a device on the LAN
  guessing gets a handful of tries, not the five-minute window.
  """

  @lifetime_minutes 5
  @max_attempts 5

  @enforce_keys [:code, :expires_at, :attempts_left]
  defstruct [:code, :expires_at, :attempts_left]

  @type t :: %__MODULE__{
          code: String.t(),
          expires_at: DateTime.t(),
          attempts_left: non_neg_integer()
        }

  @doc "How long a code stays open, in minutes. Settings copy reads it here."
  @spec lifetime_minutes() :: pos_integer()
  def lifetime_minutes, do: @lifetime_minutes

  @doc "How many misses close a code."
  @spec max_attempts() :: pos_integer()
  def max_attempts, do: @max_attempts

  @doc "A fresh code minted at `now`."
  @spec new(DateTime.t()) :: t()
  def new(now) do
    digits = :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned() |> rem(1_000_000)

    %__MODULE__{
      code: String.pad_leading(Integer.to_string(digits), 6, "0"),
      expires_at: DateTime.add(now, @lifetime_minutes, :minute),
      attempts_left: @max_attempts
    }
  end

  @doc "Whether the code is still open at `now`: not yet at its expiry instant."
  @spec open?(t(), DateTime.t()) :: boolean()
  def open?(%__MODULE__{expires_at: expires_at}, now), do: DateTime.before?(now, expires_at)

  @doc """
  The outcome of a device offering `attempt` at `now`: `:ok` on a match
  while open; `:expired` once past the expiry; `{:miss, code}` with one
  attempt fewer; `:spent` when the miss used the last attempt.
  """
  @spec redeem(t(), String.t(), DateTime.t()) :: :ok | :expired | :spent | {:miss, t()}
  def redeem(%__MODULE__{} = code, attempt, now) when is_binary(attempt) do
    cond do
      not open?(code, now) -> :expired
      Plug.Crypto.secure_compare(code.code, attempt) -> :ok
      code.attempts_left <= 1 -> :spent
      true -> {:miss, %{code | attempts_left: code.attempts_left - 1}}
    end
  end
end
