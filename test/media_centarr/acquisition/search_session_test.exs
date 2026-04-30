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

    @tag :skip
    test "is a silent no-op for a terminal group (e.g. abandoned)", %{name: name} do
      # This test depends on :DOWN-driven sweep behavior implemented in Task 5.
      # The test will be unskipped when Task 5 lands.
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
end
