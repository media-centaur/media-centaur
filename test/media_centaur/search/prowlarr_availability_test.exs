defmodule MediaCentaur.Search.ProwlarrAvailabilityTest do
  # Sync: reports write :persistent_term; Oban runs the probe job inline.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaur.Search.Prowlarr
  alias MediaCentaur.Search.ProwlarrAvailability
  alias MediaCentaur.Search.SearchResult

  @roster_ok [%{"id" => 1, "name" => "Sample Indexer", "enable" => true, "protocol" => "usenet"}]

  # Answers every probe path so an inline probe run never trips the test.
  defp stub_prowlarr(answer) do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/indexer"} -> Req.Test.json(conn, @roster_ok)
        {"GET", "/api/v1/indexerstatus"} -> Req.Test.json(conn, [])
        {"GET", "/api/v1/downloadclient"} -> Req.Test.json(conn, download_clients())
        {"POST", "/api/v1/downloadclient/testall"} -> Req.Test.json(conn, testall_all_valid())
        other -> answer.(conn, other)
      end
    end)
  end

  defp download_clients do
    [
      %{
        "id" => 1,
        "name" => "Sample Torrent Client",
        "implementation" => "QBittorrent",
        "enable" => true,
        "protocol" => "torrent",
        "fields" => []
      },
      %{
        "id" => 2,
        "name" => "Sample Usenet Client",
        "implementation" => "Sabnzbd",
        "enable" => true,
        "protocol" => "usenet",
        "fields" => []
      }
    ]
  end

  defp testall_all_valid do
    [
      %{"id" => 1, "isValid" => true, "validationFailures" => []},
      %{"id" => 2, "isValid" => true, "validationFailures" => []}
    ]
  end

  defp client_unavailable(conn) do
    conn
    |> Plug.Conn.put_status(500)
    |> Req.Test.json(%{
      "description" =>
        "NzbDrone.Core.Download.Clients.DownloadClientUnavailableException: Unable to connect to Sample Usenet Client"
    })
  end

  defp usenet_release do
    %SearchResult{
      guid: "sample-guid",
      indexer_id: 1,
      title: "Sample.Movie.2005.1080p.WEB-DL",
      protocol: :usenet
    }
  end

  describe "search/3 reports :prowlarr" do
    test "a transport error marks Prowlarr unreachable" do
      stub_prowlarr(fn conn, _other -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _reason} = Prowlarr.search("Sample Movie")
      assert %{state: {:down, _since, :unreachable}} = IntegrationAvailability.status(:prowlarr)
    end

    test "a 401 marks Prowlarr rejected" do
      stub_prowlarr(fn conn, _other -> conn |> Plug.Conn.put_status(401) |> Req.Test.text("") end)

      assert {:error, _reason} = Prowlarr.search("Sample Movie")
      assert %{state: {:down, _since, :rejected}} = IntegrationAvailability.status(:prowlarr)
    end

    test "a successful search marks Prowlarr up again" do
      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      stub_prowlarr(fn conn, _other -> Req.Test.json(conn, []) end)

      assert {:ok, []} = Prowlarr.search("Sample Movie")
      assert IntegrationAvailability.up?(:prowlarr)
    end
  end

  describe "grab/2 reports the hand-off" do
    test "DownloadClientUnavailable marks the release's protocol hand-off down and Prowlarr up" do
      stub_prowlarr(fn conn, {"POST", "/api/v1/search"} -> client_unavailable(conn) end)

      assert {:error, _reason} = Prowlarr.grab(usenet_release())

      assert %{state: {:down, _since, :client_unavailable}} =
               IntegrationAvailability.status({:handoff, :usenet})

      assert IntegrationAvailability.up?({:handoff, :torrent})
      assert IntegrationAvailability.up?(:prowlarr)
    end

    test "a successful grab marks the hand-off up" do
      {:changed, _state} =
        IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable})

      stub_prowlarr(fn conn, {"POST", "/api/v1/search"} -> Req.Test.json(conn, %{}) end)

      assert :ok = Prowlarr.grab(usenet_release())
      assert IntegrationAvailability.up?({:handoff, :usenet})
    end
  end

  describe "IndexerHealth.check/1 reports :prowlarr" do
    test "an unreachable roster marks Prowlarr unreachable; an ok roster marks it up" do
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :timeout) end)
      assert %IndexerHealth{state: :unreachable} = IndexerHealth.check()
      assert %{state: {:down, _since, :unreachable}} = IntegrationAvailability.status(:prowlarr)

      stub_prowlarr(fn conn, _other -> Req.Test.json(conn, []) end)
      assert %IndexerHealth{state: :ok} = IndexerHealth.check()
      assert IntegrationAvailability.up?(:prowlarr)
    end

    test "a blind roster marks Prowlarr down with Prowlarr's retry time" do
      retry_at = DateTime.add(DateTime.utc_now(:second), 600, :second)

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/indexer" ->
            Req.Test.json(conn, @roster_ok)

          "/api/v1/indexerstatus" ->
            Req.Test.json(conn, [
              %{"indexerId" => 1, "disabledTill" => DateTime.to_iso8601(retry_at)}
            ])
        end
      end)

      assert %IndexerHealth{state: :blind} = IndexerHealth.check()

      assert %{state: {:down, _since, :blind}, retry_at: ^retry_at} =
               IntegrationAvailability.status(:prowlarr)
    end
  end

  describe "a down transition enqueues the probe" do
    # Oban runs inline in tests, so the job the transition inserts executes
    # in this process — the probe's own request on the stub is the proof.
    setup do
      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        config
        |> Map.put(:prowlarr_url, "http://prowlarr.test")
        |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
      )

      Capabilities.save_test_result(:prowlarr, :ok)
      assert Capabilities.prowlarr_ready?()

      {:ok, tag: System.unique_integer([:positive]), test_pid: self()}
    end

    test "an unreachable search enqueues the Prowlarr probe, which reads the roster", context do
      %{tag: tag, test_pid: test_pid} = context

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/indexer"} ->
            send(test_pid, {:roster_probed, tag})
            Req.Test.json(conn, @roster_ok)

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            Req.Test.transport_error(conn, :econnrefused)
        end
      end)

      assert {:error, _reason} = Prowlarr.search("Sample Movie")

      assert_receive {:roster_probed, ^tag}, 1_000
      assert IntegrationAvailability.up?(:prowlarr)
    end

    test "a hand-off failure enqueues the hand-off probe, which tests the clients", context do
      %{tag: tag, test_pid: test_pid} = context

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/v1/search"} ->
            client_unavailable(conn)

          {"GET", "/api/v1/downloadclient"} ->
            Req.Test.json(conn, download_clients())

          {"POST", "/api/v1/downloadclient/testall"} ->
            send(test_pid, {:handoff_probed, tag})
            Req.Test.json(conn, testall_all_valid())
        end
      end)

      assert {:error, _reason} = Prowlarr.grab(usenet_release())

      assert_receive {:handoff_probed, ^tag}, 1_000
      assert IntegrationAvailability.up?({:handoff, :usenet})
    end
  end

  describe "probe_handoff/1" do
    test "folds test-all per slot: an invalid usenet client marks only that hand-off down" do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/downloadclient"} ->
            Req.Test.json(conn, download_clients())

          {"POST", "/api/v1/downloadclient/testall"} ->
            Req.Test.json(conn, [
              %{"id" => 1, "isValid" => true, "validationFailures" => []},
              %{
                "id" => 2,
                "isValid" => false,
                "validationFailures" => [%{"errorMessage" => "Unable to connect"}]
              }
            ])
        end
      end)

      assert :ok = ProwlarrAvailability.probe_handoff()

      assert %{state: {:down, _since, :client_unavailable}} =
               IntegrationAvailability.status({:handoff, :usenet})

      assert IntegrationAvailability.up?({:handoff, :torrent})
    end

    test "a slot with no enabled client on Prowlarr's side is left alone" do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/downloadclient"} ->
            Req.Test.json(conn, Enum.filter(download_clients(), &(&1["protocol"] == "usenet")))

          {"POST", "/api/v1/downloadclient/testall"} ->
            Req.Test.json(conn, [%{"id" => 2, "isValid" => true, "validationFailures" => []}])
        end
      end)

      {:changed, _state} =
        IntegrationAvailability.report({:handoff, :torrent}, {:down, :client_unavailable})

      assert :ok = ProwlarrAvailability.probe_handoff()
      refute IntegrationAvailability.up?({:handoff, :torrent})
      assert IntegrationAvailability.up?({:handoff, :usenet})
    end
  end
end
