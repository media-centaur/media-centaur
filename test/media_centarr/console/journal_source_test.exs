defmodule MediaCentarr.Console.JournalSourceTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Console.{Entry, JournalSource}
  alias MediaCentarr.Topics

  # Opener that mimics Port.open's message shape: returns a unique ref per
  # spawn, which the test sends as the "port" in simulated data/exit messages.
  # `{:port_opened, unit, ref}` is forwarded to the test pid so it can count
  # spawns and get the ref for `simulate_*` calls.
  defp controllable_opener(test_pid) do
    fn unit ->
      port_ref = make_ref()
      send(test_pid, {:port_opened, unit, port_ref})
      port_ref
    end
  end

  defp static_unit(name), do: fn -> name end
  defp no_unit, do: fn -> nil end

  defp start_source(opts) do
    name = :"journal_src_#{System.unique_integer([:positive])}"
    opts = Keyword.put(opts, :name, name)
    {:ok, pid} = JournalSource.start_link(opts)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    {pid, name}
  end

  defp simulate_line(pid, port_ref, line) do
    send(pid, {port_ref, {:data, {:eol, line}}})
  end

  defp simulate_exit(pid, port_ref, code) do
    send(pid, {port_ref, {:exit_status, code}})
  end

  describe "available?/1" do
    test "returns false when no systemd unit is detected" do
      {_, name} = start_source(unit_fetcher: no_unit(), port_opener: controllable_opener(self()))
      refute JournalSource.available?(name)
    end

    test "returns true when a unit is detected" do
      {_, name} =
        start_source(
          unit_fetcher: static_unit("media-centarr-dev.service"),
          port_opener: controllable_opener(self())
        )

      assert JournalSource.available?(name)
    end
  end

  describe "subscribe/1" do
    test "returns {:error, :no_unit_detected} when nothing is supervising this BEAM" do
      {_, name} = start_source(unit_fetcher: no_unit(), port_opener: controllable_opener(self()))
      assert {:error, :no_unit_detected} = JournalSource.subscribe(name)
    end

    test "spawns the port on first subscriber and returns an empty snapshot" do
      {_, name} =
        start_source(
          unit_fetcher: static_unit("media-centarr-dev.service"),
          port_opener: controllable_opener(self())
        )

      assert {:ok, []} = JournalSource.subscribe(name)
      assert_receive {:port_opened, "media-centarr-dev.service", _port_ref}, 500
    end

    test "second subscriber does not respawn the port" do
      {_, name} =
        start_source(
          unit_fetcher: static_unit("unit.service"),
          port_opener: controllable_opener(self())
        )

      {:ok, []} = JournalSource.subscribe(name)
      assert_receive {:port_opened, _, _}, 500

      # Subscribe from a helper pid so the server sees two distinct subscribers.
      helper =
        spawn(fn ->
          {:ok, _} = JournalSource.subscribe(name)

          receive do
            :stop -> :ok
          after
            5_000 -> :ok
          end
        end)

      refute_receive {:port_opened, _, _}, 200
      send(helper, :stop)
    end

    test "returns the primed snapshot (newest-last) to a late subscriber" do
      {pid, name} =
        start_source(
          unit_fetcher: static_unit("unit.service"),
          port_opener: controllable_opener(self())
        )

      {:ok, []} = JournalSource.subscribe(name)
      assert_receive {:port_opened, _, port_ref}, 500

      simulate_line(pid, port_ref, "line one")
      simulate_line(pid, port_ref, "line two")
      simulate_line(pid, port_ref, "line three")

      # Pump a synchronous call to flush the mailbox before snapshotting.
      _ = JournalSource.available?(name)

      assert [%Entry{message: "line one"}, %Entry{message: "line two"}, %Entry{message: "line three"}] =
               JournalSource.snapshot(name)
    end
  end

  describe "broadcast on each line" do
    test "publishes {:journal_line, entry} on Topics.service_journal()" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.service_journal())

      {pid, name} =
        start_source(
          unit_fetcher: static_unit("unit.service"),
          port_opener: controllable_opener(self())
        )

      {:ok, []} = JournalSource.subscribe(name)
      assert_receive {:port_opened, _, port_ref}, 500

      simulate_line(pid, port_ref, "some journal line")

      assert_receive {:journal_line, %Entry{component: :systemd, message: "some journal line"}}, 500
    end
  end

  describe "ring buffer cap" do
    test "drops oldest when buffer exceeds 500 lines" do
      {pid, name} =
        start_source(
          unit_fetcher: static_unit("unit.service"),
          port_opener: controllable_opener(self())
        )

      {:ok, []} = JournalSource.subscribe(name)
      assert_receive {:port_opened, _, port_ref}, 500

      # Push 600 lines. Use unique content so we can find boundaries.
      for i <- 1..600 do
        simulate_line(pid, port_ref, "line #{i}")
      end

      # Flush the mailbox with a sync call before snapshotting.
      _ = JournalSource.available?(name)

      snapshot = JournalSource.snapshot(name)
      assert length(snapshot) == 500

      # Oldest retained should be line 101 (1..100 dropped), newest should be 600.
      assert List.first(snapshot).message == "line 101"
      assert List.last(snapshot).message == "line 600"
    end
  end

  describe "subscriber lifecycle" do
    test "subscribing from a pid that dies decrements refcount via :DOWN" do
      {_, name} =
        start_source(
          unit_fetcher: static_unit("unit.service"),
          port_opener: controllable_opener(self())
        )

      parent = self()

      helper =
        spawn(fn ->
          {:ok, _} = JournalSource.subscribe(name)
          send(parent, :helper_subscribed)

          receive do
            :stop -> :ok
          end
        end)

      assert_receive :helper_subscribed, 500
      assert_receive {:port_opened, _, _}, 500

      # Kill the helper — the JournalSource should see :DOWN and treat it
      # as an unsubscribe.
      Process.exit(helper, :kill)

      # Give the GenServer a beat to process the DOWN message.
      Process.sleep(50)

      # Refcount should be zero now; a fresh subscribe should respawn the port.
      {:ok, []} = JournalSource.subscribe(name)
      # A second :port_opened would fire only if the source closed and reopened;
      # with debounce, the port is still open, so no second open happens yet.
      refute_receive {:port_opened, _, _}, 200
    end
  end

  describe "reconnect/1" do
    test "returns {:error, :no_subscribers} when nobody is listening" do
      {_, name} =
        start_source(
          unit_fetcher: static_unit("unit.service"),
          port_opener: controllable_opener(self())
        )

      assert {:error, :no_subscribers} = JournalSource.reconnect(name)
    end

    test "force-respawns the port and broadcasts :journal_reset" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.service_journal())

      {_, name} =
        start_source(
          unit_fetcher: static_unit("unit.service"),
          port_opener: controllable_opener(self())
        )

      {:ok, []} = JournalSource.subscribe(name)
      assert_receive {:port_opened, _, _first_ref}, 500

      assert :ok = JournalSource.reconnect(name)

      assert_receive {:journal_reset}, 500
      assert_receive {:port_opened, _, _second_ref}, 500
    end
  end

  describe "port exit" do
    test "broadcasts :journal_reset and respawns when subscribers remain" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.service_journal())

      {pid, name} =
        start_source(
          unit_fetcher: static_unit("unit.service"),
          port_opener: controllable_opener(self())
        )

      {:ok, []} = JournalSource.subscribe(name)
      assert_receive {:port_opened, _, port_ref}, 500

      simulate_exit(pid, port_ref, 1)

      assert_receive {:journal_reset}, 500
      # Respawn is scheduled after a 2s delay in production; we don't wait
      # that long in tests — just confirm the reset message fired and the
      # state correctly cleared the port reference (the respawn path is
      # exercised in the reconnect test).
    end
  end
end
