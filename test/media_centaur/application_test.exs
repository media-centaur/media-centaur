defmodule MediaCentaur.ApplicationTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Application, as: App

  describe "post_supervisor_hooks/2" do
    test "returns an error tuple unchanged without invoking any post-start hooks" do
      # If the hooks ran, they'd hit the Repo / SelfUpdate, either
      # crashing (Repo not available in a failed-start scenario) or
      # producing observable side effects. A pattern-matched early
      # return on {:error, _} guarantees neither happens — this test
      # pins that contract.
      assert App.post_supervisor_hooks({:error, :simulated_child_failure}, DateTime.utc_now()) ==
               {:error, :simulated_child_failure}

      assert App.post_supervisor_hooks({:error, {:shutdown, :something}}, DateTime.utc_now()) ==
               {:error, {:shutdown, :something}}
    end
  end
end
