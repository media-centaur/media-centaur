defmodule MediaCentaur.TMDB.ClientTest do
  # Starts the response cache under its production name, so sync only.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.HttpClient.Cache.Coordinator
  alias MediaCentaur.TMDB.Client

  setup do
    start_supervised!(Coordinator)
    test_pid = self()

    Req.Test.stub(:tmdb, fn conn ->
      send(test_pid, {:tmdb_hit, conn.request_path})

      conn
      |> Plug.Conn.put_resp_header("cache-control", "public, max-age=60")
      |> Req.Test.json(%{"id" => 1, "results" => []})
    end)

    :ok
  end

  test "a detail fetch is served from the cache the second time" do
    assert {:ok, %{"id" => 1}} = Client.get_movie(1)
    assert {:ok, %{"id" => 1}} = Client.get_movie(1)

    assert_receive {:tmdb_hit, "/3/movie/1"}
    refute_receive {:tmdb_hit, _path}
  end

  test "reload: true fetches past a fresh entry" do
    assert {:ok, _} = Client.get_tv(2)
    assert {:ok, _} = Client.get_tv(2, reload: true)

    assert_receive {:tmdb_hit, "/3/tv/2"}
    assert_receive {:tmdb_hit, "/3/tv/2"}
  end

  test "the credential probe always reaches TMDB" do
    assert {:ok, _} = Client.configuration()
    assert {:ok, _} = Client.configuration()

    assert_receive {:tmdb_hit, "/3/configuration"}
    assert_receive {:tmdb_hit, "/3/configuration"}
  end

  test "a caller-supplied client is used as given" do
    stub = :tmdb_client_test_custom
    Req.Test.stub(stub, fn conn -> Req.Test.json(conn, %{"results" => [%{"id" => 9}]}) end)
    client = Req.new(plug: {Req.Test, stub})

    assert {:ok, [%{"id" => 9}]} = Client.search_movie("Sample Movie", 2010, client: client)
    refute_receive {:tmdb_hit, _path}
  end

  test "every request goes through the rate limiter and reports its wait" do
    handler = "tmdb-client-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:media_centaur, :http, :request, :stop],
      fn _event, _measurements, metadata, _config -> send(test_pid, {:http_stop, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, _} = Client.get_season(3, 1)

    assert_receive {:http_stop, %{upstream: :tmdb, path: "/3/tv/3/season/1", rate_limit_wait: wait}}
    assert is_integer(wait) and wait >= 0
  end
end
