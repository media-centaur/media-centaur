defmodule MediaCentarr.Repo do
  @moduledoc false
  use Boundary, top_level?: true, check: [in: false, out: false]

  use Ecto.Repo,
    otp_app: :media_centarr,
    adapter: Ecto.Adapters.SQLite3
end
