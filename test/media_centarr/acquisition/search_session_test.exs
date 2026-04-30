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
end
