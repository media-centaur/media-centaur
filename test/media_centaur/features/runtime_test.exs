defmodule MediaCentaur.Features.RuntimeTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Features
  alias MediaCentaur.Features.Runtime

  # A child that does nothing but exist: whether it is alive is the whole
  # question. Unnamed, so two runtimes (the app's and this test's) never
  # collide.
  defp probe, do: %{id: :probe, start: {Agent, :start_link, [fn -> :probe end]}}

  defp start_runtime(runtimes) do
    name = :"features_runtime_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Runtime, runtimes: runtimes, name: name})
    {name, pid}
  end

  test "a feature that is on at boot has its children running; one that is off has none" do
    Features.set(:apps, false)
    {name, _pid} = start_runtime(%{social: [probe()], apps: [probe()]})

    assert Runtime.running?(name, :social)
    refute Runtime.running?(name, :apps)
  end

  test "reconcile/1 stops a feature's children when its flag goes off and starts them when it comes back" do
    {name, _pid} = start_runtime(%{social: [probe()]})
    assert Runtime.running?(name, :social)

    Features.set(:social, false)
    Runtime.reconcile(name)
    refute Runtime.running?(name, :social)

    Features.set(:social, true)
    Runtime.reconcile(name)
    assert Runtime.running?(name, :social)
  end

  test "the flag's broadcast reconciles on its own" do
    {name, _pid} = start_runtime(%{social: [probe()]})
    assert Runtime.running?(name, :social)

    Features.set(:social, false)
    assert eventually(fn -> not Runtime.running?(name, :social) end)
  end

  test "a feature with no runtime is nothing to start" do
    {name, _pid} = start_runtime(%{})
    refute Runtime.running?(name, :social)
    assert Runtime.reconcile(name) == :ok
  end

  test "reset/1 puts every feature's runtime at the registry default without reading the flag" do
    Features.set(:apps, true)
    {name, _pid} = start_runtime(%{social: [probe()], apps: [probe()]})
    assert Runtime.running?(name, :apps)

    Runtime.reset(name)
    assert Runtime.running?(name, :social)
    refute Runtime.running?(name, :apps)
  end
end
