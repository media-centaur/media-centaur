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

    test "clear_selections/1 wipes the map", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}
      :ok = SearchSession.set_selection(name, "Show", "guid-1")
      assert_receive {:search_session, _}

      :ok = SearchSession.clear_selections(name)

      assert_receive {:search_session, %{selections: %{}}}
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
end
