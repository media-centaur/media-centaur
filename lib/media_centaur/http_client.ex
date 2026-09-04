defmodule MediaCentaur.HttpClient do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Builds the `Req` client an integration talks through.

  In production `new/2` is `Req.new/1`. In the test environment the client
  for `owner` is routed through the `Req.Test` stub registered for it under
  `config :media_centaur, :req_test_stubs, %{owner => stub_name}`, so no
  test reaches the network and no test has to smuggle a stubbed client
  into a cache: a client is built from its settings on every call.
  """

  @doc "A `Req` client for `owner` with `opts`, stubbed in test."
  @spec new(module(), keyword()) :: Req.Request.t()
  def new(owner, opts \\ []) when is_atom(owner) and is_list(opts) do
    case Application.get_env(:media_centaur, :req_test_stubs, %{}) do
      %{^owner => stub_name} -> Req.new(Keyword.put(opts, :plug, {Req.Test, stub_name}))
      _ -> Req.new(opts)
    end
  end
end
