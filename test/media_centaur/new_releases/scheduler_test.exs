defmodule MediaCentaur.NewReleases.SchedulerTest do
  use MediaCentaur.DataCase, async: false
  use Oban.Testing, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite

  alias MediaCentaur.NewReleases.{RefreshJob, Scheduler}

  test "starting the schedule enqueues one refresh, and a second start adds nothing" do
    assert {:ok, %Oban.Job{}} = Scheduler.enqueue()
    assert {:ok, %Oban.Job{conflict?: true}} = Scheduler.enqueue()

    assert [_one] = all_enqueued(worker: RefreshJob)
  end

  test "the runtime child enqueues the refresh as it starts" do
    start_supervised!(Scheduler)
    assert [_one] = all_enqueued(worker: RefreshJob)
  end

  test "the next run is today's 04:03 UTC while it is ahead, else tomorrow's" do
    assert Scheduler.delay_until_next_run(~U[2026-11-02 04:02:00Z]) == to_timeout(minute: 1)
    assert Scheduler.delay_until_next_run(~U[2026-11-02 04:03:00Z]) == to_timeout(day: 1)
    assert Scheduler.delay_until_next_run(~U[2026-11-02 23:03:00Z]) == to_timeout(hour: 5)
  end
end
