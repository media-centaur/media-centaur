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
end
