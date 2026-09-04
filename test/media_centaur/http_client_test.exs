defmodule MediaCentaur.HttpClientTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.HttpClient

  @stop_event [:media_centaur, :http, :request, :stop]

  setup do
    stub = :"http_client_test_#{System.unique_integer([:positive])}"
    handler = "http-client-test-#{System.unique_integer([:positive])}"
    path = "/probe/#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      @stop_event,
      fn _event, measurements, metadata, _config ->
        if metadata.path == path, do: send(test_pid, {:http_stop, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    %{stub: stub, path: path}
  end

  describe "new/2" do
    test "refuses a client without an upstream" do
      assert_raise ArgumentError, ~r/upstream/, fn ->
        HttpClient.new(__MODULE__, base_url: "http://example.test")
      end
    end

    test "refuses an unknown upstream" do
      assert_raise ArgumentError, ~r/upstream/, fn ->
        HttpClient.new(__MODULE__, upstream: :nowhere, base_url: "http://example.test")
      end
    end

    test "routes a registered module through its Req.Test stub" do
      Req.Test.stub(:tmdb, fn conn -> Req.Test.json(conn, %{"stubbed" => true}) end)

      client = HttpClient.new(MediaCentaur.TMDB.Client, upstream: :tmdb, base_url: "http://tmdb.test")

      assert {:ok, %{status: 200, body: %{"stubbed" => true}}} = Req.get(client, url: "/anything")
    end
  end

  describe "instrumentation" do
    test "emits one stop event per request with the upstream and wire outcome", %{
      stub: stub,
      path: path
    } do
      Req.Test.stub(stub, fn conn -> Req.Test.json(conn, %{"ok" => true}) end)

      client =
        HttpClient.new(__MODULE__,
          upstream: :steam,
          base_url: "http://steam.test",
          plug: {Req.Test, stub},
          retry: false
        )

      assert {:ok, %{status: 200}} = Req.get(client, url: path, params: [q: "sample"])

      assert_receive {:http_stop, %{duration: duration}, metadata}
      assert is_integer(duration) and duration >= 0

      assert %{
               upstream: :steam,
               method: :get,
               host: "steam.test",
               path: ^path,
               status: 200,
               error: nil,
               cache: :uncached
             } = metadata
    end

    test "reports a transport error as the outcome", %{stub: stub, path: path} do
      Req.Test.stub(stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      client =
        HttpClient.new(__MODULE__,
          upstream: :github,
          base_url: "http://github.test",
          plug: {Req.Test, stub},
          retry: false
        )

      assert {:error, %Req.TransportError{reason: :econnrefused}} = Req.get(client, url: path)

      assert_receive {:http_stop, _measurements, %{upstream: :github, status: nil, error: error}}
      assert %Req.TransportError{reason: :econnrefused} = error
    end
  end
end
