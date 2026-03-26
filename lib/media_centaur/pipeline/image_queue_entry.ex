defmodule MediaCentaur.Pipeline.ImageQueueEntry do
  @moduledoc """
  An image download queued by the pipeline.

  Tracks source URL, owner metadata, and retry state. Once the download
  succeeds, `Library.Inbound` creates the corresponding `Library.Image`
  record with `content_url` already set.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "pipeline_image_queue" do
    field :owner_id, :string
    field :owner_type, :string
    field :role, :string
    field :source_url, :string
    field :entity_id, :string
    field :watch_dir, :string
    field :status, :string, default: "pending"
    field :retry_count, :integer, default: 0

    timestamps()
  end

  @required ~w(owner_id owner_type role source_url entity_id watch_dir)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @required ++ [:status, :retry_count])
    |> validate_required(@required)
    |> validate_inclusion(:owner_type, ~w(entity movie episode))
    |> validate_inclusion(:status, ~w(pending failed complete permanent))
    |> unique_constraint([:owner_id, :role])
  end

  def status_changeset(entry, status) do
    entry
    |> change(status: status)
  end

  def fail_changeset(entry) do
    entry
    |> change(status: "failed", retry_count: entry.retry_count + 1)
  end

  def reset_changeset(entry) do
    entry
    |> change(status: "pending")
  end
end
