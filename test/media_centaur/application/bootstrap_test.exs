defmodule MediaCentaur.Application.BootstrapTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Application.Bootstrap
  alias MediaCentaur.Repo
  alias MediaCentaur.Settings.Config

  defmodule Noop do
    use Oban.Worker, queue: :maintenance
    @impl true
    def perform(_job), do: :ok
  end

  test "overlays the database settings onto the config and returns :ignore" do
    :ok = Config.update(:auto_approve_threshold, 0.77)
    config = :persistent_term.get({Config, :config})
    :persistent_term.put({Config, :config}, Map.put(config, :auto_approve_threshold, 0.5))

    assert Bootstrap.run() == :ignore
    assert Config.get(:auto_approve_threshold) == 0.77
  end

  test "a job the last run left executing is available again" do
    {:ok, job} = Oban.insert(Noop.new(%{}))
    force_attrs(job, state: "executing", attempted_at: DateTime.add(DateTime.utc_now(), -60), attempt: 1)

    assert Bootstrap.run() == :ignore
    assert Repo.get!(Oban.Job, job.id).state == "available"
  end
end
