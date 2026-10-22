defmodule MediaCentaur.Playback.FakeTransport do
  @moduledoc """
  A `Playback.Transport` for tests: the test process stands in for the
  mpv. Commands the session sends arrive at the owner as
  `{:mpv_command, command}`; `open/2` reports `{:transport_opened, launch}`;
  the test feeds the session transport events with `emit/2`, which is the
  one message a transport may send its session.

  Files are located as `fake://<host path>`, so a test can see that the
  session asked the transport for the locator and mapped a reported path
  back through `identify/2`.
  """

  @behaviour MediaCentaur.Playback.Transport

  # This module defines the behaviour's `send/2`; the Erlang send is spelled out.
  import Kernel, except: [send: 2]

  defstruct [:owner, attached?: false]

  @type t :: %__MODULE__{owner: pid(), attached?: boolean()}

  @doc "A transport whose mpv is the `owner` process."
  @spec new(pid()) :: t()
  def new(owner), do: %__MODULE__{owner: owner}

  @doc "Delivers one transport event to the session, as a real transport's message would."
  @spec emit(pid(), MediaCentaur.Playback.Transport.event()) :: :ok
  def emit(session, event) do
    Kernel.send(session, {:transport, {:fake, event}})
    :ok
  end

  @impl true
  def open(transport, launch) do
    Kernel.send(transport.owner, {:transport_opened, launch})
    {[], transport}
  end

  @impl true
  def send(%{attached?: false}, _command), do: :ok

  def send(transport, command) do
    Kernel.send(transport.owner, {:mpv_command, command})
    :ok
  end

  @impl true
  def attached?(transport), do: transport.attached?

  @impl true
  def locator(_transport, content_url), do: "fake://" <> content_url

  @impl true
  def identify(_transport, "fake://" <> content_url), do: content_url
  def identify(_transport, _other), do: nil

  @impl true
  def handle_message(transport, {:transport, {:fake, {:attached, _kind} = event}}),
    do: {[event], %{transport | attached?: true}}

  def handle_message(transport, {:transport, {:fake, {:detached, _reason} = event}}),
    do: {[event], %{transport | attached?: false}}

  def handle_message(transport, {:transport, {:fake, {:closed, _outcome} = event}}),
    do: {[event], %{transport | attached?: false}}

  def handle_message(transport, {:transport, {:fake, event}}), do: {[event], transport}
  def handle_message(_transport, _message), do: :unhandled

  @impl true
  def close(transport, final?) do
    Kernel.send(transport.owner, {:transport_closed, final?})
    :ok
  end

  @impl true
  def describe(_transport), do: "fake mpv"
end
