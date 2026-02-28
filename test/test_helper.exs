ExUnit.start()
ExUnit.configure(exclude: [:external])
Ecto.Adapters.SQL.Sandbox.mode(MediaCentaur.Repo, :manual)
