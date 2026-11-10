defmodule MediaCentaur.Pipeline.SupervisorTest do
  # async: false — drives the application's own pipeline supervisor: the
  # Broadway children start and stop, and Stats is killed and restarted.
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.Eventually

  alias MediaCentaur.FlagSupervisor
  alias MediaCentaur.Pipeline
  alias MediaCentaur.ServiceFlags

  setup do
    ServiceFlags.enable_background_services()
    ServiceFlags.turn_off(:start_pipeline, Pipeline.FlagSupervisor)
    refute Pipeline.Supervisor.pipeline_running?()
    :ok
  end

  test "set_enabled/1 starts the Broadway children, persists the flag, and stops them again" do
    :ok = Pipeline.Supervisor.set_enabled(true)
    assert Pipeline.Supervisor.pipeline_running?()
    assert is_pid(Process.whereis(Pipeline.Discovery))
    assert is_pid(Process.whereis(Pipeline.Import))

    :ok = Pipeline.Supervisor.set_enabled(false)
    refute Pipeline.Supervisor.pipeline_running?()
    assert eventually(fn -> Process.whereis(Pipeline.Discovery) == nil end)
  end

  test "a Stats crash leaves a pipeline whose flag is off stopped" do
    stats = Process.whereis(Pipeline.Stats)
    Process.exit(stats, :kill)

    assert eventually(fn ->
             case Process.whereis(Pipeline.Stats) do
               nil -> false
               pid -> pid != stats
             end
           end)

    refute Pipeline.Supervisor.pipeline_running?()
    assert Process.whereis(Pipeline.Discovery) == nil
  end

  test "the artwork pipeline has its own flag" do
    ServiceFlags.turn_off(:start_image_pipeline, Pipeline.Image.FlagSupervisor)
    refute Pipeline.Image.Supervisor.pipeline_running?()

    :ok = Pipeline.Image.Supervisor.set_enabled(true)
    assert Pipeline.Image.Supervisor.pipeline_running?()
    assert is_pid(Process.whereis(Pipeline.Image))
    refute Pipeline.Supervisor.pipeline_running?()

    :ok = Pipeline.Image.Supervisor.set_enabled(false)
    refute FlagSupervisor.running?(Pipeline.Image.FlagSupervisor)
  end
end
