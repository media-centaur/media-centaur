defmodule MediaCentarr.Acquisition.SearchSessionTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.SearchSession

  describe "default state" do
    test "fresh GenServer returns empty session" do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})

      session = SearchSession.current(name)

      assert %SearchSession{
               query: "",
               expansion_preview: :idle,
               groups: [],
               selections: %{},
               grab_message: nil,
               grabbing?: false,
               searching_pid: nil
             } = session
    end
  end

  describe "start_search/1" do
    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
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
      assert session.searching_pid == self()

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
    alias MediaCentarr.Acquisition.SearchResult

    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
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

    test "is a silent no-op for a terminal group (e.g. abandoned)", %{name: name} do
      parent = self()

      child =
        spawn(fn ->
          {:ok, _} = SearchSession.start_search(name, "Solo Show")
          send(parent, :ready_to_die)

          receive do
            :die -> :ok
          end
        end)

      assert_receive :ready_to_die
      assert_receive {:search_session, _}
      Process.exit(child, :kill)
      assert_receive {:search_session, swept_session}
      assert Enum.all?(swept_session.groups, fn group -> group.status == :abandoned end)

      :ok =
        SearchSession.record_search_result(
          name,
          "Solo Show",
          {:ok,
           [%SearchResult{guid: "late", title: "Late", indexer_id: 1, quality: :hd_1080p, seeders: 1}]}
        )

      refute_receive {:search_session, _}, 50
      assert SearchSession.current(name).groups == swept_session.groups
    end
  end

  describe "simple mutators" do
    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "set_selection/3 puts and replaces; clear_selection/2 removes", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      :ok = SearchSession.set_selection(name, "Show", "guid-1")
      assert_receive {:search_session, %{selections: %{"Show" => "guid-1"}}}

      :ok = SearchSession.set_selection(name, "Show", "guid-2")
      assert_receive {:search_session, %{selections: %{"Show" => "guid-2"}}}

      :ok = SearchSession.clear_selection(name, "Show")
      assert_receive {:search_session, %{selections: selections}}
      assert selections == %{}
    end

    test "set_selection/3 also collapses the group whose term matches", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      :ok = SearchSession.toggle_group(name, "Show")
      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == true

      :ok = SearchSession.set_selection(name, "Show", "guid-1")

      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == false
      assert session.selections == %{"Show" => "guid-1"}
    end

    test "clear_selections/1 wipes the map", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}
      :ok = SearchSession.set_selection(name, "Show", "guid-1")
      assert_receive {:search_session, _}

      :ok = SearchSession.clear_selections(name)

      assert_receive {:search_session, %{selections: %{}}}
    end

    test "clear_results/1 empties groups and selections but preserves the query and grab_message",
         %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show {01-03}")
      :ok = SearchSession.set_selection(name, "Show 01", "guid-1")
      :ok = SearchSession.set_grab_message(name, {:ok, "1 grab(s) submitted"})

      :ok = SearchSession.clear_results(name)

      session = SearchSession.current(name)
      assert session.query == "Show {01-03}"
      assert session.groups == []
      assert session.selections == %{}
      assert session.grab_message == {:ok, "1 grab(s) submitted"}
    end

    test "toggle_group/2 flips expanded? on the matching group only", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      :ok = SearchSession.toggle_group(name, "Show")
      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == true

      :ok = SearchSession.toggle_group(name, "Show")
      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == false
    end

    test "set_query_preview/2 updates query and expansion_preview without touching groups", %{name: name} do
      :ok = SearchSession.set_query_preview(name, "Show {01-03}")

      assert_receive {:search_session, session}
      assert session.query == "Show {01-03}"
      assert session.expansion_preview == {:ok, 3}
      assert session.groups == []
    end

    test "set_query_preview/2 reports invalid syntax", %{name: name} do
      :ok = SearchSession.set_query_preview(name, "Show {")
      assert_receive {:search_session, %{expansion_preview: {:error, :invalid_syntax}}}
    end

    test "set_query_preview/2 with blank input -> :idle", %{name: name} do
      :ok = SearchSession.set_query_preview(name, "")
      assert_receive {:search_session, %{expansion_preview: :idle, query: ""}}
    end

    test "set_grabbing/2 + set_grab_message/2 round-trip", %{name: name} do
      :ok = SearchSession.set_grabbing(name, true)
      assert_receive {:search_session, %{grabbing?: true}}

      :ok = SearchSession.set_grab_message(name, {:ok, "1 grab(s) submitted"})
      assert_receive {:search_session, %{grab_message: {:ok, "1 grab(s) submitted"}}}

      :ok = SearchSession.set_grabbing(name, false)
      assert_receive {:search_session, %{grabbing?: false, grab_message: {:ok, _}}}
    end

    test "clear/1 resets to default state", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      :ok = SearchSession.clear(name)
      assert_receive {:search_session, session}
      assert session == %SearchSession{}
    end
  end

  describe "monitor + abandonment" do
    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "kills sweep :loading -> :abandoned and clear searching_pid", %{name: name} do
      parent = self()

      child =
        spawn(fn ->
          {:ok, _} = SearchSession.start_search(name, "Show {01-03}")
          send(parent, :ready)

          receive do
            :die -> :ok
          end
        end)

      assert_receive :ready
      assert_receive {:search_session, before_session}
      assert before_session.searching_pid == child
      assert Enum.all?(before_session.groups, fn group -> group.status == :loading end)

      Process.exit(child, :kill)

      assert_receive {:search_session, after_session}, 500
      assert Enum.all?(after_session.groups, fn group -> group.status == :abandoned end)
      assert after_session.searching_pid == nil
      assert after_session.monitor_ref == nil
    end

    test ":ready groups are not swept on :DOWN", %{name: name} do
      alias MediaCentarr.Acquisition.SearchResult
      parent = self()

      child =
        spawn(fn ->
          {:ok, _} = SearchSession.start_search(name, "{A,B}")
          send(parent, :started)

          receive do
            :die -> :ok
          end
        end)

      assert_receive :started
      assert_receive {:search_session, _}

      :ok =
        SearchSession.record_search_result(
          name,
          "A",
          {:ok,
           [
             %SearchResult{guid: "g", title: "T", indexer_id: 1, quality: :hd_1080p, seeders: 1}
           ]}
        )

      assert_receive {:search_session, _}

      Process.exit(child, :kill)

      assert_receive {:search_session, swept}, 500
      assert Enum.find(swept.groups, &(&1.term == "A")).status == :ready
      assert Enum.find(swept.groups, &(&1.term == "B")).status == :abandoned
    end
  end

  describe "retry_search_terms/2" do
    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "transitions named :abandoned and {:failed, _} groups to :loading and re-monitors", %{
      name: name
    } do
      parent = self()

      child =
        spawn(fn ->
          {:ok, _} = SearchSession.start_search(name, "{A,B,C}")
          send(parent, :started)

          receive do
            :die -> :ok
          end
        end)

      assert_receive :started
      assert_receive {:search_session, _}

      :ok = SearchSession.record_search_result(name, "B", {:error, :timeout})
      assert_receive {:search_session, _}

      Process.exit(child, :kill)
      assert_receive {:search_session, swept}, 500
      # A, C are :abandoned; B is {:failed, :timeout}.
      assert Enum.find(swept.groups, &(&1.term == "A")).status == :abandoned
      assert Enum.find(swept.groups, &(&1.term == "B")).status == {:failed, :timeout}
      assert Enum.find(swept.groups, &(&1.term == "C")).status == :abandoned

      :ok = SearchSession.retry_search_terms(name, ["A", "B"])
      assert_receive {:search_session, after_retry}, 500

      assert Enum.find(after_retry.groups, &(&1.term == "A")).status == :loading
      assert Enum.find(after_retry.groups, &(&1.term == "B")).status == :loading
      assert Enum.find(after_retry.groups, &(&1.term == "C")).status == :abandoned
      assert after_retry.searching_pid == self()
      assert after_retry.monitor_ref != nil
    end

    test "no-op for terms that aren't :abandoned or {:failed, _}", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "X")
      assert_receive {:search_session, _}

      :ok = SearchSession.retry_search_terms(name, ["X"])

      assert_receive {:search_session, session}
      assert hd(session.groups).status == :loading
    end
  end

  describe "featured field" do
    alias MediaCentarr.Acquisition.SearchResult

    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
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

      :ok = SearchSession.set_selection(name, "Show S01E01", "b")

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

      :ok = SearchSession.set_selection(name, "Show S01E01", "ghost")

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.featured.guid == "top"
    end

    test "clear_selection reverts featured to top-ranked", %{name: name} do
      a = build_result("a", :hd_1080p, 50)
      b = build_result("b", :hd_1080p, 30)
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:ok, [a, b]})
      assert_receive {:search_session, _}
      :ok = SearchSession.set_selection(name, "Show S01E01", "b")
      assert_receive {:search_session, _}

      :ok = SearchSession.clear_selection(name, "Show S01E01")

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
      :ok = SearchSession.set_selection(name, "Show S01E01", "b")
      assert_receive {:search_session, _}
      :ok = SearchSession.set_selection(name, "Show S01E02", "d")
      assert_receive {:search_session, _}

      :ok = SearchSession.clear_selections(name)

      assert_receive {:search_session, session}
      [g1, g2] = session.groups
      assert g1.featured.guid == "a"
      assert g2.featured.guid == "c"
    end

    test "retry_search_terms resets featured to nil for retried groups", %{name: name} do
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:error, :timeout})
      assert_receive {:search_session, _}

      :ok = SearchSession.retry_search_terms(name, ["Show S01E01"])

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.status == :loading
      assert group.featured == nil
    end

    test ":DOWN sweep preserves featured on already-:ready groups", %{name: _name} do
      # Run a fresh session with a separate caller pid we can kill.
      separate = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: separate}, id: :sess_separate)
      parent = self()

      child =
        spawn(fn ->
          {:ok, _} = SearchSession.start_search(separate, "{A,B}")
          send(parent, :ready)

          receive do
            :die -> :ok
          end
        end)

      assert_receive :ready

      # Different topic/process — the parent test subscribed already, so we just
      # poll until the started session is visible.
      started = wait_for_groups(separate, 2)
      assert Enum.all?(started.groups, &(&1.status == :loading))

      result = build_result("a-top", :hd_1080p, 50)
      :ok = SearchSession.record_search_result(separate, "A", {:ok, [result]})

      Process.exit(child, :kill)

      swept = wait_for_status(separate, "B", :abandoned)
      a = Enum.find(swept.groups, &(&1.term == "A"))
      b = Enum.find(swept.groups, &(&1.term == "B"))

      assert a.status == :ready
      assert a.featured.guid == "a-top"
      assert b.status == :abandoned
      assert b.featured == nil
    end

    defp wait_for_groups(name, count, attempts \\ 50) do
      session = SearchSession.current(name)

      cond do
        length(session.groups) == count ->
          session

        attempts == 0 ->
          flunk("timed out waiting for #{count} groups; got #{length(session.groups)}")

        true ->
          Process.sleep(10)
          wait_for_groups(name, count, attempts - 1)
      end
    end

    defp wait_for_status(name, term, status, attempts \\ 50) do
      session = SearchSession.current(name)
      group = Enum.find(session.groups, &(&1.term == term))

      cond do
        group && group.status == status ->
          session

        attempts == 0 ->
          flunk(
            "timed out waiting for #{term} → #{inspect(status)}; got #{inspect(group && group.status)}"
          )

        true ->
          Process.sleep(10)
          wait_for_status(name, term, status, attempts - 1)
      end
    end
  end
end
