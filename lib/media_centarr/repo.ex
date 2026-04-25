defmodule MediaCentarr.Repo do
  @moduledoc false
  use Boundary, top_level?: true, check: [in: false, out: false]

  use Ecto.Repo,
    otp_app: :media_centarr,
    adapter: Ecto.Adapters.SQLite3

  @doc """
  Unwrap an Ecto result tuple, raising on `{:error, _}`.

  Mirrors the bang convention of `Repo.insert!/1` for callers that hold
  an `{:ok, _} | {:error, _}` and want a struct-or-raise return.
  """
  def bang!({:ok, result}), do: result

  def bang!({:error, %Ecto.Changeset{} = changeset}) do
    raise Ecto.InvalidChangesetError, changeset: changeset, action: changeset.action
  end

  def bang!({:error, reason}), do: raise("operation failed: #{inspect(reason)}")
end
