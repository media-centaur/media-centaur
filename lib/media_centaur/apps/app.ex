defmodule MediaCentaur.Apps.App do
  @moduledoc """
  A launchable entry in the Apps launcher — name, one-line shell command,
  and provenance.

  Every app has the same shape regardless of how it was added; add-methods
  (the Steam picker, the manual form) resolve to these fields at add time.
  `origin` records provenance for dedup and artwork refresh:

    * `%{"source" => "steam", "app_id" => 413150}` — added via the Steam picker
    * `%{"source" => "manual"}` — typed into the manual form

  Artwork is not stored here — disk is the ledger (see
  `MediaCentaur.Apps.Artwork`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @type t :: %__MODULE__{}

  schema "apps" do
    field :name, :string
    field :command, :string
    field :origin, :map, default: %{}

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :command, :origin])
    |> validate_required([:name, :command])
  end

  def update_changeset(app, attrs) do
    app
    |> cast(attrs, [:name, :command])
    |> validate_required([:name, :command])
  end
end
