defmodule MediaCentaur.GlobalStateSandboxTest do
  # Manipulates process-global state directly — must not run beside
  # anything else. Same reason every writer of a global cache in this
  # suite is `async: false`.
  use ExUnit.Case, async: false

  alias MediaCentaur.Console.Buffer
  alias MediaCentaur.Console.Entry
  alias MediaCentaur.GlobalStateSandbox
  alias MediaCentaurWeb.IncomingLive.SearchSession

  describe "restore!/0 — :persistent_term" do
    test "puts back an app-owned term a test changed" do
      key = {MediaCentaur.Settings.Config, :config}
      pristine = :persistent_term.get(key)

      :persistent_term.put(key, Map.put(pristine, :port, 65_432))
      GlobalStateSandbox.restore!()

      assert :persistent_term.get(key) == pristine
    end

    test "erases an app-owned term that did not exist at capture" do
      # Deliberately a module that does not exist: the baseline is derived
      # from the namespace, not from a list of known caches, so a cache
      # added tomorrow is covered without editing GlobalStateSandbox.
      key = {MediaCentaur.SomeCacheAddedTomorrow, :state}
      :persistent_term.put(key, :leaked)

      GlobalStateSandbox.restore!()

      assert :persistent_term.get(key, :__unset) == :__unset
    end

    test "leaves terms this application does not own alone" do
      # Third-party libraries keep their own terms here (Phoenix, Ecto,
      # Req). Resetting those would reset the test harness itself.
      key = {:some_dependency, :config}
      :persistent_term.put(key, :not_ours)
      on_exit(fn -> :persistent_term.erase(key) end)

      GlobalStateSandbox.restore!()

      assert :persistent_term.get(key) == :not_ours
    end
  end

  describe "restore!/0 — long-lived singletons" do
    test "empties the Console ring buffer" do
      Buffer.append(
        Entry.new(
          id: 1,
          timestamp: DateTime.utc_now(),
          level: :info,
          component: :library,
          message: "a line from an earlier test"
        )
      )

      Buffer.flush()
      assert Buffer.recent(nil) != []

      GlobalStateSandbox.restore!()

      assert Buffer.recent(nil) == []
    end

    test "resets the acquisition search session" do
      SearchSession.set_query_preview("a query from an earlier test")
      assert SearchSession.current().query != ""

      GlobalStateSandbox.restore!()

      assert SearchSession.current().query == ""
    end
  end

  describe "restore!/1 — only for a test that owns the machine" do
    test "an async test resets nothing" do
      # Async tests run concurrently, so a reset in one of them clears state
      # its peers installed for themselves. An unconditional reset erased the
      # stubbed TMDB client an async test had put in place and sent the stage
      # to the real API.
      key = {MediaCentaur.SomeCacheAddedTomorrow, :state}
      :persistent_term.put(key, :installed_by_a_peer)
      on_exit(fn -> :persistent_term.erase(key) end)

      GlobalStateSandbox.restore!(%{async: true})

      assert :persistent_term.get(key, :__unset) == :installed_by_a_peer
    end
  end

  describe "the supervision tree's inventory" do
    test "every long-lived child is classified" do
      unclassified =
        MediaCentaur.Supervisor
        |> Supervisor.which_children()
        |> Enum.map(fn {id, _pid, _type, _modules} -> id end)
        |> Enum.reject(&Map.has_key?(GlobalStateSandbox.dispositions(), &1))

      assert unclassified == [],
             """
             These supervision-tree children carry state across the whole
             test run and nothing says what happens to it between tests:

                 #{inspect(unclassified)}

             Add each to `MediaCentaur.GlobalStateSandbox.dispositions/0`
             with how its state is contained — :sandboxed, :stateless,
             :reset (and wire the reset), or :accepted with the reason no
             test can read it.
             """
    end

    test "every child classified :reset is actually reset" do
      reset_children =
        GlobalStateSandbox.dispositions()
        |> Enum.filter(fn {_id, {disposition, _why}} -> disposition == :reset end)
        |> Enum.map(fn {id, _} -> id end)
        |> Enum.sort()

      wired = GlobalStateSandbox.resets() |> Enum.map(fn {module, _fun} -> module end) |> Enum.sort()

      assert reset_children == wired
    end
  end
end
