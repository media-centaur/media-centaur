defmodule MediaCentaur.Showcase.Supervisor do
  use Boundary, top_level?: true, check: [in: false, out: false]
  use Supervisor

  @moduledoc """
  Rebuilds the demo instance's **in-memory** fabricated state, once per
  boot. Started by `MediaCentaur.Application` only when `:showcase_mode`
  is set, so a real install never supervises any of this.

  ## The axis these children sit on

  Showcase state divides by where it lives, not by which subsystem owns
  it:

    * **In the database** — the catalog, watch history, pursuits, status
      incidents, capability settings. `mix seed.showcase` writes it once
      and it travels with `priv/showcase/media-centaur.db`.
    * **In process memory** — the request time series behind Status →
      Connections, and the console's per-component rings. Both are keyed
      to wall-clock time and swept or capped, so anything written at seed
      time is gone by the time someone boots the demo. It has to be
      rebuilt here, relative to *this* boot.

  Getting that wrong is silent. `Showcase.seed_console_entries!/0` used
  to emit its log lines during the seed run, into the seeding VM's ring,
  which died with the Mix task — the demo's console was empty for as long
  as anyone had been looking at it. A new piece of fabricated state
  belongs in the seeder or here depending only on which of those two
  homes it has.

  Separate from `MediaCentaur.Showcase.Stubs`, which is not state at all:
  it substitutes upstream *behaviour* at call time, so Prowlarr and the
  download client answer from fixtures.
  """

  alias MediaCentaur.Showcase.{ConsoleLines, SyntheticTraffic}

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Supervisor.init([SyntheticTraffic, ConsoleLines], strategy: :one_for_one)
  end
end
