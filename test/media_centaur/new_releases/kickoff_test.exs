defmodule MediaCentaur.NewReleases.KickoffTest do
  use MediaCentaur.DataCase, async: false
  use Oban.Testing, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite

  alias MediaCentaur.NewReleases.{Kickoff, RefreshJob}

  test "enqueues one refresh, and a second kickoff adds nothing" do
    assert {:ok, %Oban.Job{}} = Kickoff.enqueue()
    assert {:ok, %Oban.Job{conflict?: true}} = Kickoff.enqueue()

    assert [_one] = all_enqueued(worker: RefreshJob)
  end
end
