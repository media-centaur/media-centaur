defmodule MediaCentaur.FlagSupervisorTest do
  use MediaCentaur.Case, async: true

  import ExUnit.CaptureLog
  import MediaCentaur.Eventually

  alias MediaCentaur.FlagSupervisor
  alias MediaCentaur.Topics

  # The flag is an Agent the test flips; the probe child is an Agent whose
  # being alive is the whole question. Both unnamed, so concurrent tests
  # never collide.
  defp flag_agent(initial) do
    start_supervised!(%{id: {:flag, make_ref()}, start: {Agent, :start_link, [fn -> initial end]}})
  end

  defp probe(id \\ :probe), do: %{id: id, start: {Agent, :start_link, [fn -> :probe end]}}

  defp start_flagged(flag, opts \\ []) do
    topic = "flag_supervisor_test:#{System.unique_integer([:positive])}"

    children = Keyword.get(opts, :children, [probe()])
    relevant? = Keyword.get(opts, :relevant?, fn _message -> true end)

    pid =
      start_supervised!(
        Supervisor.child_spec(
          {FlagSupervisor,
           flag: fn -> Agent.get(flag, & &1) end,
           subscribe: fn -> Topics.subscribe(topic) end,
           relevant?: relevant?,
           children: children,
           label: "probe"},
          id: {:flagged, make_ref()}
        )
      )

    {pid, topic}
  end

  test "children run when the flag is on at start and are absent when it is off" do
    on = flag_agent(true)
    {sup_on, _topic} = start_flagged(on)
    assert FlagSupervisor.running?(sup_on)

    off = flag_agent(false)
    {sup_off, _topic} = start_flagged(off)
    refute FlagSupervisor.running?(sup_off)
  end

  test "reconcile/1 stops the children when the flag went off and starts them when it came back" do
    flag = flag_agent(true)
    {sup, _topic} = start_flagged(flag)

    Agent.update(flag, fn _ -> false end)
    assert :ok = FlagSupervisor.reconcile(sup)
    refute FlagSupervisor.running?(sup)

    Agent.update(flag, fn _ -> true end)
    assert :ok = FlagSupervisor.reconcile(sup)
    assert FlagSupervisor.running?(sup)
  end

  test "a message on the subscribed topic reconciles on its own" do
    flag = flag_agent(true)
    {sup, topic} = start_flagged(flag)

    Agent.update(flag, fn _ -> false end)
    Topics.publish(topic, {:flag_changed, :whatever})

    assert eventually(fn -> not FlagSupervisor.running?(sup) end)
  end

  test "a message relevant?/1 rejects is not a cue; the flag is not read for it" do
    flag = flag_agent(true)
    {sup, topic} = start_flagged(flag, relevant?: &match?({:this_flag, _}, &1))

    Agent.update(flag, fn _ -> false end)
    Topics.publish(topic, {:another_setting, :whatever})
    Topics.publish(topic, {:another_setting, :again})
    assert FlagSupervisor.running?(sup)

    Topics.publish(topic, {:this_flag, :changed})
    assert eventually(fn -> not FlagSupervisor.running?(sup) end)
  end

  test "force/2 runs or stops the children regardless of the flag, until the next reconcile" do
    flag = flag_agent(false)
    {sup, _topic} = start_flagged(flag)

    assert :ok = FlagSupervisor.force(sup, true)
    assert FlagSupervisor.running?(sup)

    assert :ok = FlagSupervisor.reconcile(sup)
    refute FlagSupervisor.running?(sup)
  end

  test "suspend/2 stops the children around the function and brings them back, even when it raises" do
    flag = flag_agent(true)
    {sup, _topic} = start_flagged(flag)

    assert :result =
             FlagSupervisor.suspend(sup, fn ->
               refute FlagSupervisor.running?(sup)
               :result
             end)

    assert FlagSupervisor.running?(sup)

    assert_raise RuntimeError, "boom", fn -> FlagSupervisor.suspend(sup, fn -> raise "boom" end) end
    assert FlagSupervisor.running?(sup)
  end

  test "a flag message during a suspension does not bring the children back early" do
    flag = flag_agent(true)
    {sup, topic} = start_flagged(flag)

    FlagSupervisor.suspend(sup, fn ->
      Topics.publish(topic, {:flag_changed, :whatever})
      assert :ok = FlagSupervisor.reconcile(sup)
      refute FlagSupervisor.running?(sup)
    end)

    assert FlagSupervisor.running?(sup)
  end

  test "a child that fails to start leaves the flag's children not running and the supervisor alive" do
    flag = flag_agent(true)
    failing = %{id: :failing, start: {Agent, :start_link, [fn -> raise "cannot start" end]}}

    log =
      capture_log(fn ->
        {sup, _topic} = start_flagged(flag, children: [failing])
        refute FlagSupervisor.running?(sup)
        assert Process.alive?(sup)
      end)

    assert log =~ "probe"
  end

  test "a child that crashes while running is restarted within the group" do
    flag = flag_agent(true)
    {sup, _topic} = start_flagged(flag, children: [probe(:restartable)])

    [first] = FlagSupervisor.children(sup)
    Process.exit(first, :kill)

    assert eventually(fn ->
             case FlagSupervisor.children(sup) do
               [second] -> second != first and Process.alive?(second)
               _ -> false
             end
           end)
  end
end
