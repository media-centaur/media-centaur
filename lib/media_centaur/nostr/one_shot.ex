defmodule MediaCentaur.Nostr.OneShot do
  @moduledoc """
  A synchronous, single-purpose relay session for callers that are not
  long-lived processes: connect, answer any `AUTH` challenge, do one thing,
  disconnect. Built for command-line tooling; the app's own connections
  live in `Social.Connections`.

  Each call starts one `Connection` owned by the caller, waits for
  `:connected`, opens a subscription and waits for its `EOSE`. That `EOSE`
  is the proof the relay is ready: `Connection` re-issues subscriptions
  only after a successful `AUTH`, so an allowlist relay's `CLOSED
  auth-required:` on the first attempt is expected and skipped.

  `{:auth, {:failed, _}}`, a `CLOSED` with any other reason,
  `{:disconnected, _}` and the timeout (`timeout_ms`, default 5 s) all
  return `{:error, reason}`. The connection is stopped on every path.
  """

  alias MediaCentaur.Nostr.Connection
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Filter

  @sub "oneshot"
  @default_timeout_ms 5_000

  @type signer :: (Event.t() -> Event.t())
  @type reason :: String.t() | :timeout | {:disconnected, term()} | {:auth_failed, String.t()}

  @doc "Publishes one signed event and returns the relay's verdict."
  @spec publish(String.t(), Event.t(), signer(), keyword()) :: :ok | {:error, reason()}
  def publish(url, %Event{id: id} = event, signer, opts \\ []) when is_binary(id) do
    session(url, signer, [Filter.new(ids: [id])], opts, fn conn, _events, deadline ->
      Connection.publish(conn, event)

      await(url, deadline, fn
        {:ok, ^id, true, _reason} -> {:halt, :ok}
        {:ok, ^id, false, reason} -> {:halt, {:error, reason}}
        _other -> :cont
      end)
    end)
  end

  @doc "Returns every stored event the relay serves for `filters`."
  @spec query(String.t(), [Filter.t()], signer(), keyword()) :: {:ok, [Event.t()]} | {:error, reason()}
  def query(url, filters, signer, opts \\ []) when is_list(filters) do
    session(url, signer, filters, opts, fn _conn, events, _deadline -> {:ok, events} end)
  end

  # --- session -----------------------------------------------------------

  defp session(url, signer, filters, opts, after_eose) do
    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    {:ok, conn} = Connection.start_link(url: url, owner: self(), signer: signer)

    try do
      with :ok <- await_connected(url, deadline),
           :ok <- Connection.subscribe(conn, @sub, filters),
           {:ok, events} <- await_eose(url, deadline) do
        after_eose.(conn, events, deadline)
      end
    after
      stop(conn)
    end
  end

  defp await_connected(url, deadline) do
    await(url, deadline, fn
      :connected -> {:halt, :ok}
      _other -> :cont
    end)
  end

  defp await_eose(url, deadline), do: collect_until_eose(url, deadline, [])

  defp collect_until_eose(url, deadline, events) do
    result =
      await(url, deadline, fn
        {:event, @sub, %Event{} = event} -> {:halt, {:event, event}}
        {:eose, @sub} -> {:halt, :eose}
        _other -> :cont
      end)

    case result do
      {:event, event} -> collect_until_eose(url, deadline, [event | events])
      :eose -> {:ok, Enum.reverse(events)}
      {:error, _reason} = error -> error
    end
  end

  # Waits for the next `{:nostr, url, message}`; fatal messages end the
  # session regardless of what `handler` is looking for.
  defp await(url, deadline, handler) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      receive do
        {:nostr, ^url, message} ->
          case fatal(message) || handler.(message) do
            {:halt, result} -> result
            :cont -> await(url, deadline, handler)
          end
      after
        remaining -> {:error, :timeout}
      end
    end
  end

  defp fatal({:auth, {:failed, reason}}), do: {:halt, {:error, {:auth_failed, reason}}}
  defp fatal({:disconnected, reason}), do: {:halt, {:error, {:disconnected, reason}}}
  defp fatal({:closed, @sub, "auth-required:" <> _rest}), do: nil
  defp fatal({:closed, @sub, reason}), do: {:halt, {:error, reason}}
  defp fatal(_message), do: nil

  defp stop(conn) do
    Process.unlink(conn)
    GenServer.stop(conn)
  catch
    :exit, _already_gone -> :ok
  end
end
