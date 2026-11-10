defmodule MediaCentaurWeb.DownloadsLive.SearchSessionTest do
  # async: false — a crashing search is a child of the application's task
  # supervisor; the others are the session's own linked tasks.
  use MediaCentaur.Case, async: false

  import MediaCentaur.Eventually

  alias MediaCentaur.Search.SearchResult
  alias MediaCentaurWeb.DownloadsLive.SearchSession

  # A search that never answers: the session owns it (linked), so it ends
  # with the session or with `Task.shutdown/2`.
  defp held, do: fn _term -> Task.async(fn -> receive do: (:never -> :ok) end) end

  # A search that crashes, off the session's link.
  defp crashing,
    do: fn _term -> Task.Supervisor.async_nolink(MediaCentaur.TaskSupervisor, fn -> exit(:boom) end) end

  defp start_session(search \\ held()) do
    name = :"sess_#{System.unique_integer([:positive])}"
    start_supervised!(Supervisor.child_spec({SearchSession, name: name, search: search}, id: name))
    name
  end

  describe "default state" do
    test "fresh GenServer returns empty session" do
      name = start_session()

      session = SearchSession.current(name)

      assert %SearchSession{
               query: "",
               expansion_preview: :idle,
               groups: [],
               selections: %{},
               grab_message: nil,
               grabbing?: false
             } = session
    end
  end

  describe "start_search/1" do
    setup do
      name = start_session()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "places one :loading group per expanded query and broadcasts", %{name: name} do
      assert {:ok, %{session: session, queries: queries}} =
               SearchSession.start_search(name, "Show S01E{01-03}")

      assert queries == ["Show S01E01", "Show S01E02", "Show S01E03"]
      assert session.query == "Show S01E{01-03}"
      assert length(session.groups) == 3
      assert Enum.all?(session.groups, fn group -> group.status == :loading end)
      assert Enum.map(session.groups, & &1.term) == queries
      assert session.selections == %{}
      assert session.grab_message == nil
      assert session.grabbing? == false

      assert_receive {:search_session, ^session}
    end

    test "wholesale replaces an existing session", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "First")
      {:ok, %{session: session}} = SearchSession.start_search(name, "Second")

      assert session.query == "Second"
      assert Enum.map(session.groups, & &1.term) == ["Second"]
      assert session.selections == %{}
    end

    test "rejects invalid brace syntax without mutating state", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "ok")
      before = SearchSession.current(name)

      assert {:error, :invalid_syntax} = SearchSession.start_search(name, "Bad {syntax")
      assert SearchSession.current(name) == before
    end
  end

  describe "record_search_result/3" do
    alias MediaCentaur.Search.SearchResult

    setup do
      name = start_session()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_search())
      {:ok, _} = SearchSession.start_search(name, "Show S01E{01-02}")
      assert_receive {:search_session, _}
      {:ok, name: name}
    end

    test "transitions :loading -> :ready and adds top-seeder default selection", %{name: name} do
      result = %SearchResult{
        guid: "guid-1",
        title: "Show S01E01 1080p",
        indexer_id: 1,
        quality: :hd_1080p,
        seeders: 42,
        size_bytes: 1_000_000,
        indexer_name: "Test"
      }

      :ok = SearchSession.record_search_result(name, "Show S01E01", {:ok, [result]})

      assert_receive {:search_session, session}
      [first_group, second_group] = session.groups
      assert first_group.term == "Show S01E01"
      assert first_group.status == :ready
      assert first_group.results == [result]
      assert second_group.status == :loading
      assert session.selections == %{"Show S01E01" => "guid-1"}
    end

    test "transitions :loading -> {:failed, reason} on error", %{name: name} do
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:error, :timeout})

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.status == {:failed, :timeout}
      assert group.results == []
    end

    test "is a silent no-op for an unknown term", %{name: name} do
      before = SearchSession.current(name)

      :ok = SearchSession.record_search_result(name, "Different Show", {:ok, []})

      refute_receive {:search_session, _}, 50
      assert SearchSession.current(name) == before
    end

    test "is a silent no-op for a terminal group", %{name: name} do
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:error, :timeout})
      assert_receive {:search_session, failed_session}
      assert Enum.find(failed_session.groups, &(&1.term == "Show S01E01")).status == {:failed, :timeout}

      :ok =
        SearchSession.record_search_result(
          name,
          "Show S01E01",
          {:ok,
           [%SearchResult{guid: "late", title: "Late", indexer_id: 1, quality: :hd_1080p, seeders: 1}]}
        )

      refute_receive {:search_session, _}, 50
      assert SearchSession.current(name).groups == failed_session.groups
    end
  end

  describe "simple mutators" do
    setup do
      name = start_session()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "set_selection/3 puts and replaces; clear_selection/2 removes", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      _session = SearchSession.set_selection(name, "Show", "guid-1")
      assert_receive {:search_session, %{selections: %{"Show" => "guid-1"}}}

      _session = SearchSession.set_selection(name, "Show", "guid-2")
      assert_receive {:search_session, %{selections: %{"Show" => "guid-2"}}}

      _session = SearchSession.clear_selection(name, "Show")
      assert_receive {:search_session, %{selections: selections}}
      assert selections == %{}
    end

    test "set_selection/3 also collapses the group whose term matches", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      _session = SearchSession.toggle_group(name, "Show")
      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == true

      _session = SearchSession.set_selection(name, "Show", "guid-1")

      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == false
      assert session.selections == %{"Show" => "guid-1"}
    end

    test "clear_selections/1 wipes the map", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}
      _session = SearchSession.set_selection(name, "Show", "guid-1")
      assert_receive {:search_session, _}

      _session = SearchSession.clear_selections(name)

      assert_receive {:search_session, %{selections: %{}}}
    end

    test "clear_results/1 empties groups and selections but preserves the query and grab_message",
         %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show {01-03}")
      _session = SearchSession.set_selection(name, "Show 01", "guid-1")
      _session = SearchSession.set_grab_message(name, {:ok, "1 grab(s) submitted"})

      _session = SearchSession.clear_results(name)

      session = SearchSession.current(name)
      assert session.query == "Show {01-03}"
      assert session.groups == []
      assert session.selections == %{}
      assert session.grab_message == {:ok, "1 grab(s) submitted"}
    end

    test "toggle_group/2 flips expanded? on the matching group only", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      _session = SearchSession.toggle_group(name, "Show")
      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == true

      _session = SearchSession.toggle_group(name, "Show")
      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == false
    end

    test "set_query_preview/2 updates query and expansion_preview without touching groups", %{name: name} do
      _session = SearchSession.set_query_preview(name, "Show {01-03}")

      assert_receive {:search_session, session}
      assert session.query == "Show {01-03}"
      assert session.expansion_preview == {:ok, 3}
      assert session.groups == []
    end

    test "set_query_preview/2 reports invalid syntax", %{name: name} do
      _session = SearchSession.set_query_preview(name, "Show {")
      assert_receive {:search_session, %{expansion_preview: {:error, :invalid_syntax}}}
    end

    test "set_query_preview/2 with blank input -> :idle", %{name: name} do
      _session = SearchSession.set_query_preview(name, "")
      assert_receive {:search_session, %{expansion_preview: :idle, query: ""}}
    end

    test "set_grabbing/2 + set_grab_message/2 round-trip", %{name: name} do
      _session = SearchSession.set_grabbing(name, true)
      assert_receive {:search_session, %{grabbing?: true}}

      _session = SearchSession.set_grab_message(name, {:ok, "1 grab(s) submitted"})
      assert_receive {:search_session, %{grab_message: {:ok, "1 grab(s) submitted"}}}

      _session = SearchSession.set_grabbing(name, false)
      assert_receive {:search_session, %{grabbing?: false, grab_message: {:ok, _}}}
    end

    test "clear/1 resets to default state", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      _session = SearchSession.clear(name)
      assert_receive {:search_session, session}
      assert session == %SearchSession{}
    end
  end

  describe "the session's own searches" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_search())
      :ok
    end

    test "start_search/2 runs one search per term and lands each outcome without a caller" do
      result = %SearchResult{guid: "g", title: "T", indexer_id: 1, quality: :hd_1080p, seeders: 1}
      name = start_session(fn _term -> Task.completed({:ok, [result]}) end)

      {:ok, %{session: started}} = SearchSession.start_search(name, "{A,B}")
      assert Enum.all?(started.groups, &(&1.status == :loading))

      landed =
        eventually(fn ->
          session = SearchSession.current(name)
          Enum.all?(session.groups, &(&1.status == :ready)) and session
        end)

      assert Enum.all?(landed.groups, &(&1.results == [result]))
      assert landed.selections == %{"A" => "g", "B" => "g"}
    end

    test "a search that crashes fails its group; the others keep loading" do
      name =
        start_session(fn
          "B" -> crashing().("B")
          term -> held().(term)
        end)

      {:ok, _} = SearchSession.start_search(name, "{A,B}")

      failed =
        eventually(fn ->
          session = SearchSession.current(name)

          match?({:failed, {:crashed, :boom}}, Enum.find(session.groups, &(&1.term == "B")).status) and
            session
        end)

      assert Enum.find(failed.groups, &(&1.term == "A")).status == :loading
    end

    test "replacing the session shuts its searches down" do
      test_pid = self()

      name =
        start_session(fn _term ->
          Task.async(fn ->
            send(test_pid, {:search_running, self()})
            receive do: (:never -> :ok)
          end)
        end)

      {:ok, _} = SearchSession.start_search(name, "First")
      assert_receive {:search_running, first_search}

      {:ok, _} = SearchSession.start_search(name, "Second")
      assert eventually(fn -> not Process.alive?(first_search) end)
    end
  end

  describe "retry_search_terms/2" do
    setup do
      name = start_session()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "re-runs the named {:failed, _} groups: back to :loading with a new search", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "{A,B,C}")
      assert_receive {:search_session, _}

      :ok = SearchSession.record_search_result(name, "B", {:error, :timeout})
      assert_receive {:search_session, failed}
      assert Enum.find(failed.groups, &(&1.term == "B")).status == {:failed, :timeout}

      _session = SearchSession.retry_search_terms(name, ["A", "B"])
      assert_receive {:search_session, after_retry}, 500

      assert Enum.find(after_retry.groups, &(&1.term == "A")).status == :loading
      assert Enum.find(after_retry.groups, &(&1.term == "B")).status == :loading
      assert Enum.find(after_retry.groups, &(&1.term == "C")).status == :loading
    end

    test "no-op for a term that is not {:failed, _}", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "X")
      assert_receive {:search_session, _}

      _session = SearchSession.retry_search_terms(name, ["X"])

      assert_receive {:search_session, session}
      assert hd(session.groups).status == :loading
    end
  end

  describe "featured field" do
    alias MediaCentaur.Search.SearchResult

    setup do
      name = start_session()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_search())
      {:ok, _} = SearchSession.start_search(name, "Show S01E{01-02}")
      assert_receive {:search_session, _}
      {:ok, name: name}
    end

    defp build_result(guid, quality, seeders) do
      %SearchResult{
        guid: guid,
        title: "Result #{guid}",
        indexer_id: 1,
        quality: quality,
        seeders: seeders,
        size_bytes: 1_000_000,
        indexer_name: "Test"
      }
    end

    test "initial groups from start_search have featured: nil", %{name: name} do
      session = SearchSession.current(name)
      assert Enum.all?(session.groups, &(&1.featured == nil))
    end

    test "record_search_result with no prior selection stamps top-ranked as featured", %{name: name} do
      lower = build_result("lower", nil, 1)
      higher = build_result("higher", :hd_1080p, 50)

      :ok = SearchSession.record_search_result(name, "Show S01E01", {:ok, [lower, higher]})

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.featured.guid == "higher"
    end

    test "record_search_result with empty results leaves featured: nil", %{name: name} do
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:ok, []})

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.featured == nil
    end

    test "record_search_result with {:error, _} leaves featured: nil", %{name: name} do
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:error, :timeout})

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.featured == nil
    end

    test "set_selection stamps featured = matching result on the targeted group only", %{name: name} do
      a = build_result("a", :hd_1080p, 50)
      b = build_result("b", :hd_1080p, 30)
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:ok, [a, b]})
      assert_receive {:search_session, _}

      _session = SearchSession.set_selection(name, "Show S01E01", "b")

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.featured.guid == "b"

      # Other group is untouched
      other = Enum.find(session.groups, &(&1.term == "Show S01E02"))
      assert other.featured == nil
    end

    test "set_selection with a guid not in results falls back to top-ranked", %{name: name} do
      top = build_result("top", :hd_1080p, 50)
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:ok, [top]})
      assert_receive {:search_session, _}

      _session = SearchSession.set_selection(name, "Show S01E01", "ghost")

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.featured.guid == "top"
    end

    test "clear_selection reverts featured to top-ranked", %{name: name} do
      a = build_result("a", :hd_1080p, 50)
      b = build_result("b", :hd_1080p, 30)
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:ok, [a, b]})
      assert_receive {:search_session, _}
      _session = SearchSession.set_selection(name, "Show S01E01", "b")
      assert_receive {:search_session, _}

      _session = SearchSession.clear_selection(name, "Show S01E01")

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.featured.guid == "a"
    end

    test "clear_selections reverts featured on every group", %{name: name} do
      a = build_result("a", :hd_1080p, 50)
      b = build_result("b", :hd_1080p, 30)
      c = build_result("c", :hd_1080p, 50)
      d = build_result("d", :hd_1080p, 30)
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:ok, [a, b]})
      assert_receive {:search_session, _}
      :ok = SearchSession.record_search_result(name, "Show S01E02", {:ok, [c, d]})
      assert_receive {:search_session, _}
      _session = SearchSession.set_selection(name, "Show S01E01", "b")
      assert_receive {:search_session, _}
      _session = SearchSession.set_selection(name, "Show S01E02", "d")
      assert_receive {:search_session, _}

      _session = SearchSession.clear_selections(name)

      assert_receive {:search_session, session}
      [g1, g2] = session.groups
      assert g1.featured.guid == "a"
      assert g2.featured.guid == "c"
    end

    test "retry_search_terms resets featured to nil for retried groups", %{name: name} do
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:error, :timeout})
      assert_receive {:search_session, _}

      _session = SearchSession.retry_search_terms(name, ["Show S01E01"])

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.status == :loading
      assert group.featured == nil
    end

    test "a crashed search leaves the other groups' featured intact" do
      separate =
        start_session(fn
          "B" -> crashing().("B")
          term -> held().(term)
        end)

      {:ok, _} = SearchSession.start_search(separate, "{A,B}")
      started = wait_for_groups(separate, 2)
      assert Enum.find(started.groups, &(&1.term == "A")).status == :loading

      result = build_result("a-top", :hd_1080p, 50)
      :ok = SearchSession.record_search_result(separate, "A", {:ok, [result]})

      settled = wait_for_status(separate, "B", {:failed, {:crashed, :boom}})
      a = Enum.find(settled.groups, &(&1.term == "A"))
      b = Enum.find(settled.groups, &(&1.term == "B"))

      assert a.status == :ready
      assert a.featured.guid == "a-top"
      assert b.featured == nil
    end

    defp wait_for_groups(name, count) do
      eventually(
        fn ->
          session = SearchSession.current(name)
          length(session.groups) == count and session
        end,
        message: fn ->
          "timed out waiting for #{count} groups; got #{length(SearchSession.current(name).groups)}"
        end
      )
    end

    defp wait_for_status(name, term, status) do
      group_for = fn -> Enum.find(SearchSession.current(name).groups, &(&1.term == term)) end

      eventually(
        fn ->
          group = group_for.()
          group && group.status == status && SearchSession.current(name)
        end,
        message: fn ->
          "timed out waiting for #{term} → #{inspect(status)}; got #{inspect(group_for.() && group_for.().status)}"
        end
      )
    end
  end
end
