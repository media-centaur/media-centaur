defmodule MediaCentaur.HttpClient.CacheTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.HttpClient
  alias MediaCentaur.HttpClient.Cache
  alias MediaCentaur.HttpClient.Cache.Coordinator

  @stop_event [:media_centaur, :http, :request, :stop]

  # Positive waits are on concurrent tasks and telemetry round-trips.
  # `assert_receive` returns the instant the message lands, so a generous
  # ceiling costs nothing when the test passes and only bounds how long a real
  # failure takes to report — whereas the 100ms default loses its race with a
  # loaded scheduler and fails as a phantom bug in the cache. Every
  # `refute_receive` below keeps its own (short) budget: a negative wait is
  # paid in full on every single run.
  @wait_ms 15_000

  setup context do
    name = :"http_cache_test_#{System.unique_integer([:positive])}"
    stub = :"http_cache_stub_#{System.unique_integer([:positive])}"
    handler = "http-cache-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    start_supervised!({Coordinator, Keyword.merge([name: name], Map.get(context, :coordinator, []))})

    :telemetry.attach(
      handler,
      @stop_event,
      fn _event, _measurements, metadata, _config ->
        if metadata.host == "cache.test", do: send(test_pid, {:http_stop, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    client =
      HttpClient.new(__MODULE__,
        upstream: :tmdb,
        base_url: "http://cache.test",
        plug: {Req.Test, stub},
        retry: false,
        cache: [name: name, exclude_params: ["api_key"]]
      )

    %{name: name, stub: stub, client: client}
  end

  # A stub that reports every hit to the test process and answers with
  # the given headers and JSON body.
  defp stub_json(stub, body, headers, test_pid \\ self()) do
    Req.Test.stub(stub, fn conn ->
      send(test_pid, {:stub_hit, conn.method, conn.request_path, conn.req_headers})

      conn
      |> put_headers(headers)
      |> Req.Test.json(body)
    end)
  end

  # Plug stamps `cache-control: max-age=0, private, must-revalidate` on every
  # response; a test that gives no cache-control means "none", so drop it.
  defp put_headers(conn, headers) do
    conn = Plug.Conn.delete_resp_header(conn, "cache-control")

    Enum.reduce(headers, conn, fn {key, value}, conn -> Plug.Conn.put_resp_header(conn, key, value) end)
  end

  describe "fresh entries" do
    test "a second identical GET is served from the cache", %{stub: stub, client: client} do
      stub_json(stub, %{"id" => 1}, [{"cache-control", "public, max-age=60"}, {"etag", ~s(W/"a")}])

      assert {:ok, %{status: 200, body: %{"id" => 1}}} = Req.get(client, url: "/movie/1")
      assert {:ok, %{status: 200, body: %{"id" => 1}}} = Req.get(client, url: "/movie/1")

      assert_receive {:stub_hit, "GET", "/movie/1", _headers}, @wait_ms
      refute_receive {:stub_hit, _method, _path, _headers}

      assert_receive {:http_stop, %{cache: :miss, status: 200}}, @wait_ms
      assert_receive {:http_stop, %{cache: :hit, status: 200}}, @wait_ms
      assert Cache.stats(client) == %{entries: 1}
    end

    test "the key ignores excluded params and param order", %{stub: stub, client: client} do
      stub_json(stub, %{"results" => []}, [{"cache-control", "max-age=60"}])

      assert {:ok, _} =
               Req.get(client, url: "/search", params: [query: "sample", year: 2010, api_key: "one"])

      assert {:ok, _} =
               Req.get(client, url: "/search", params: [api_key: "two", year: 2010, query: "sample"])

      assert_receive {:stub_hit, _, "/search", _}, @wait_ms
      refute_receive {:stub_hit, _, _, _}
    end

    test "a different query is a different entry", %{stub: stub, client: client} do
      stub_json(stub, %{"results" => []}, [{"cache-control", "max-age=60"}])

      assert {:ok, _} = Req.get(client, url: "/search", params: [query: "one"])
      assert {:ok, _} = Req.get(client, url: "/search", params: [query: "two"])

      assert_receive {:stub_hit, _, "/search", _}, @wait_ms
      assert_receive {:stub_hit, _, "/search", _}, @wait_ms
    end
  end

  describe "what is never cached" do
    test "a response without max-age", %{stub: stub, client: client} do
      stub_json(stub, %{"id" => 1}, [])

      assert {:ok, _} = Req.get(client, url: "/movie/1")
      assert {:ok, _} = Req.get(client, url: "/movie/1")

      assert_receive {:stub_hit, _, _, _}, @wait_ms
      assert_receive {:stub_hit, _, _, _}, @wait_ms
      assert Cache.stats(client) == %{entries: 0}
    end

    test "a no-store response", %{stub: stub, client: client} do
      stub_json(stub, %{"id" => 1}, [{"cache-control", "no-store, max-age=60"}])

      assert {:ok, _} = Req.get(client, url: "/movie/1")
      assert {:ok, _} = Req.get(client, url: "/movie/1")

      assert_receive {:stub_hit, _, _, _}, @wait_ms
      assert_receive {:stub_hit, _, _, _}, @wait_ms
    end

    test "a non-200 response", %{stub: stub, client: client} do
      Req.Test.stub(stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("cache-control", "max-age=60")
        |> Plug.Conn.send_resp(404, ~s({"status_message":"missing"}))
      end)

      assert {:ok, %{status: 404}} = Req.get(client, url: "/movie/404")
      assert {:ok, %{status: 404}} = Req.get(client, url: "/movie/404")
      assert Cache.stats(client) == %{entries: 0}
    end

    test "a POST", %{stub: stub, client: client} do
      stub_json(stub, %{"ok" => true}, [{"cache-control", "max-age=60"}])

      assert {:ok, _} = Req.post(client, url: "/search", json: %{q: 1})
      assert {:ok, _} = Req.post(client, url: "/search", json: %{q: 1})

      assert_receive {:stub_hit, "POST", _, _}, @wait_ms
      assert_receive {:stub_hit, "POST", _, _}, @wait_ms
      assert_receive {:http_stop, %{cache: :uncached}}, @wait_ms
    end
  end

  describe "revalidation" do
    test "a stale entry is revalidated with If-None-Match and a 304 renews it", %{
      stub: stub,
      client: client
    } do
      test_pid = self()

      Req.Test.stub(stub, fn conn ->
        send(test_pid, {:stub_hit, conn.method, conn.request_path, conn.req_headers})

        case Plug.Conn.get_req_header(conn, "if-none-match") do
          [~s(W/"v1")] ->
            conn
            |> Plug.Conn.put_resp_header("cache-control", "max-age=60")
            |> Plug.Conn.send_resp(304, "")

          [] ->
            conn
            |> put_headers([{"cache-control", "max-age=0"}, {"etag", ~s(W/"v1")}])
            |> Req.Test.json(%{"id" => 1, "version" => 1})
        end
      end)

      # max-age=0: stored, and stale immediately.
      assert {:ok, %{status: 200, body: %{"version" => 1}}} = Req.get(client, url: "/movie/1")
      assert_receive {:stub_hit, "GET", "/movie/1", headers}, @wait_ms
      refute List.keymember?(headers, "if-none-match", 0)

      # Stale: revalidate. The caller sees a 200 with the stored body, not the 304.
      assert {:ok, %{status: 200, body: %{"version" => 1}}} = Req.get(client, url: "/movie/1")
      assert_receive {:stub_hit, "GET", "/movie/1", headers}, @wait_ms
      assert {"if-none-match", ~s(W/"v1")} in headers
      assert_receive {:http_stop, %{cache: :miss, status: 200}}, @wait_ms
      assert_receive {:http_stop, %{cache: :revalidate, status: 304}}, @wait_ms

      # The 304 renewed freshness for 60s: now a hit.
      assert {:ok, %{status: 200, body: %{"version" => 1}}} = Req.get(client, url: "/movie/1")
      refute_receive {:stub_hit, _, _, _}
      assert_receive {:http_stop, %{cache: :hit}}, @wait_ms
    end

    test "a stale entry answered with a 200 is replaced", %{stub: stub, client: client} do
      test_pid = self()
      counter = :counters.new(1, [])

      Req.Test.stub(stub, fn conn ->
        :counters.add(counter, 1, 1)
        version = :counters.get(counter, 1)
        send(test_pid, {:stub_hit, conn.method, conn.request_path, conn.req_headers})

        conn
        |> put_headers([{"cache-control", "max-age=0"}, {"etag", ~s(W/"v#{version}")}])
        |> Req.Test.json(%{"version" => version})
      end)

      assert {:ok, %{body: %{"version" => 1}}} = Req.get(client, url: "/movie/1")
      assert {:ok, %{body: %{"version" => 2}}} = Req.get(client, url: "/movie/1")
      assert_receive {:stub_hit, _, _, _}, @wait_ms
      assert_receive {:stub_hit, _, _, headers}, @wait_ms
      assert {"if-none-match", ~s(W/"v1")} in headers
    end
  end

  describe "reload" do
    test "fetches past a fresh entry and overwrites it", %{stub: stub, client: client} do
      test_pid = self()
      counter = :counters.new(1, [])

      Req.Test.stub(stub, fn conn ->
        :counters.add(counter, 1, 1)
        send(test_pid, {:stub_hit, conn.method, conn.request_path, conn.req_headers})

        conn
        |> Plug.Conn.put_resp_header("cache-control", "max-age=60")
        |> Req.Test.json(%{"version" => :counters.get(counter, 1)})
      end)

      assert {:ok, %{body: %{"version" => 1}}} = Req.get(client, url: "/tv/1")
      assert {:ok, %{body: %{"version" => 2}}} = Req.get(client, url: "/tv/1", reload: true)
      assert_receive {:http_stop, %{cache: :miss}}, @wait_ms
      assert_receive {:http_stop, %{cache: :reload, status: 200}}, @wait_ms

      # The reload's body is what the cache now serves.
      assert {:ok, %{body: %{"version" => 2}}} = Req.get(client, url: "/tv/1")
      assert_receive {:http_stop, %{cache: :hit}}, @wait_ms
    end
  end

  describe "single-flight" do
    test "concurrent misses on one key share one request", %{stub: stub, client: client} do
      test_pid = self()

      Req.Test.stub(stub, fn conn ->
        send(test_pid, {:stub_hit, conn.method, conn.request_path, conn.req_headers})
        send(test_pid, {:stub_blocked, self()})

        receive do
          :release -> :ok
        end

        conn
        |> Plug.Conn.put_resp_header("cache-control", "max-age=60")
        |> Req.Test.json(%{"id" => 7})
      end)

      tasks =
        for _ <- 1..5 do
          Task.async(fn ->
            Req.Test.allow(stub, test_pid, self())
            Req.get(client, url: "/tv/7")
          end)
        end

      assert_receive {:stub_hit, _, "/tv/7", _}, @wait_ms
      assert_receive {:stub_blocked, leader}, @wait_ms
      refute_receive {:stub_hit, _, _, _}, 50

      # Exactly one request is on the wire; release it.
      send(leader, :release)

      for task <- tasks do
        assert {:ok, %{status: 200, body: %{"id" => 7}}} = Task.await(task)
      end

      assert Cache.stats(client) == %{entries: 1}
    end

    test "a failed leader fails its followers without storing anything", %{stub: stub, client: client} do
      test_pid = self()
      # A gate process holds every admitted request in flight until the
      # test opens it, then releases latecomers immediately. The earlier
      # version had the stub send itself to the test and released only the
      # FIRST blocked pid it saw — so whenever the single-flight election
      # admitted a second request (a scheduling race, more likely on a
      # loaded machine) that request was never released and its task hung
      # until `Task.await` timed out.
      gate = start_supervised!({Task, fn -> hold_then_release(false, []) end}, id: :cache_gate)

      Req.Test.stub(stub, fn conn ->
        send(test_pid, {:stub_hit, conn.method, conn.request_path, conn.req_headers})
        send(gate, {:blocked, self()})

        receive do
          :release -> :ok
        end

        Req.Test.transport_error(conn, :econnrefused)
      end)

      tasks =
        for _ <- 1..3 do
          Task.async(fn ->
            Req.Test.allow(stub, test_pid, self())
            Req.get(client, url: "/tv/8")
          end)
        end

      assert_receive {:stub_hit, _, "/tv/8", _}, @wait_ms
      send(gate, :open)

      for task <- tasks do
        assert {:error, %Req.TransportError{reason: :econnrefused}} = Task.await(task)
      end

      assert Cache.stats(client) == %{entries: 0}
    end
  end

  describe "retention" do
    @tag coordinator: [max_entries: 2]
    test "the entry cap evicts the oldest entry", %{stub: stub, client: client} do
      stub_json(stub, %{"ok" => true}, [{"cache-control", "max-age=60"}])

      for id <- 1..3, do: assert({:ok, _} = Req.get(client, url: "/movie/#{id}"))
      assert Cache.stats(client) == %{entries: 2}

      # /movie/1 was evicted; /movie/3 is still a hit.
      assert {:ok, _} = Req.get(client, url: "/movie/3")
      assert {:ok, _} = Req.get(client, url: "/movie/1")

      for _ <- 1..3, do: assert_receive({:stub_hit, _, _, _}, @wait_ms)
      assert_receive {:stub_hit, _, "/movie/1", _}, @wait_ms
      refute_receive {:stub_hit, _, _, _}
    end

    @tag coordinator: [retention_ms: 0]
    test "the sweep drops entries past the hard retention cap", %{stub: stub, client: client, name: name} do
      stub_json(stub, %{"ok" => true}, [{"cache-control", "max-age=60"}])

      assert {:ok, _} = Req.get(client, url: "/movie/1")
      assert Cache.stats(client) == %{entries: 1}

      # Retention is a hard cap on age, not on freshness: a fresh entry goes too.
      Coordinator.sweep(name)
      assert Cache.stats(client) == %{entries: 0}
    end
  end

  describe "without a coordinator" do
    test "the client works uncached" do
      stub = :"http_cache_orphan_#{System.unique_integer([:positive])}"
      Req.Test.stub(stub, fn conn -> Req.Test.json(conn, %{"ok" => true}) end)

      client =
        HttpClient.new(__MODULE__,
          upstream: :tmdb,
          base_url: "http://orphan.test",
          plug: {Req.Test, stub},
          cache: [name: :"not_started_#{System.unique_integer([:positive])}"]
        )

      assert {:ok, %{status: 200, body: %{"ok" => true}}} = Req.get(client, url: "/movie/1")
      assert Cache.stats(client) == %{entries: 0}
    end
  end

  # Holds blocked stub processes until `:open`, then releases every one
  # that has arrived and every one that arrives afterwards.
  defp hold_then_release(open?, blocked) do
    receive do
      {:blocked, pid} when open? ->
        send(pid, :release)
        hold_then_release(true, blocked)

      {:blocked, pid} ->
        hold_then_release(false, [pid | blocked])

      :open ->
        Enum.each(blocked, &send(&1, :release))
        hold_then_release(true, [])
    end
  end
end
