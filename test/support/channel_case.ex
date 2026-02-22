defmodule MediaManagerWeb.ChannelCase do
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
      @endpoint MediaManagerWeb.Endpoint
    end
  end

  setup tags do
    MediaManager.DataCase.setup_sandbox(tags)
    :ok
  end
end
