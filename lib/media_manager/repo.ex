defmodule MediaManager.Repo do
  use Ecto.Repo,
    otp_app: :media_manager,
    adapter: Ecto.Adapters.Postgres
end
