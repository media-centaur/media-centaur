defmodule MediaCentaurWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a channel.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier to
  test channel interactions.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import MediaCentaurWeb.ChannelCase, only: [json_roundtrip: 1]
      import MediaCentaur.TestFactory
      @endpoint MediaCentaurWeb.Endpoint
    end
  end

  def json_roundtrip(payload), do: payload |> Jason.encode!() |> Jason.decode!()

  setup tags do
    MediaCentaur.DataCase.setup_sandbox(tags)
    :ok
  end
end
