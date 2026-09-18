defmodule MediaCentaur.TMDB.ClientTest do
  # Starts the response cache under its production name, so sync only.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.HttpClient.Cache.Coordinator
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.TMDB.RateLimiter

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

  # The console line is copy, and copy is pinned where it can be read
  # without a global Logger level: `log_line/2` is the whole vocabulary,
  # and `get/3` is the only caller — in the 200 branch, so a failed
  # request never claims a fetch.
  describe "availability" do
    test "a failed fetch opens :tmdb and a later answered one closes it" do
      Req.Test.stub(:tmdb, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _reason} = Client.get_movie(550)
      refute IntegrationAvailability.up?(:tmdb)

      Req.Test.stub(:tmdb, fn conn -> Req.Test.json(conn, %{"id" => 550}) end)

      assert {:ok, _body} = Client.get_movie(550)
      assert IntegrationAvailability.up?(:tmdb)
    end

    test "an answer served from the cache is no evidence either way" do
      assert {:ok, _first} = Client.get_movie(1)
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      assert {:ok, _cached} = Client.get_movie(1)
      refute IntegrationAvailability.up?(:tmdb)
    end
  end

  describe "log_line/2 — the console line says where the answer came from" do
    test "a detail fetch names its source" do
      assert Client.log_line("movie tmdb:1", :miss) == "fetched movie tmdb:1 — from TMDB"
      assert Client.log_line("movie tmdb:1", :hit) == "fetched movie tmdb:1 — from cache"

      assert Client.log_line("movie tmdb:1", :revalidate) ==
               "fetched movie tmdb:1 — revalidated with TMDB"

      assert Client.log_line("movie tmdb:1", :reload) == "fetched movie tmdb:1 — refetched from TMDB"
    end

    test "a client with no cache attached reads as a plain fetch" do
      assert Client.log_line("configuration", :uncached) == "fetched configuration — from TMDB"
    end

    test "a search carries its query" do
      assert Client.log_line("movies for Sample Showpiece (2010)", :hit) ==
               "fetched movies for Sample Showpiece (2010) — from cache"
    end
  end

  # The invariant both the client's and the limiter's moduledoc claim:
  # the rate-limit step is appended AFTER the cache lookup, and Req halts
  # the request steps the moment the lookup answers, so a hit never
  # spends a slot.
  test "a cache hit does not spend a rate-limit slot" do
    :ok = RateLimiter.reset()

    assert {:ok, _} = Client.get_movie(778_200)
    assert %{used: spent_by_fetch} = RateLimiter.status()
    assert spent_by_fetch >= 1

    assert {:ok, _} = Client.get_movie(778_200)
    assert %{used: ^spent_by_fetch} = RateLimiter.status()
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
