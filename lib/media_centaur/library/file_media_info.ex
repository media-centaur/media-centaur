defmodule MediaCentaur.Library.FileMediaInfo do
  @moduledoc """
  Technical metadata probed out of one media file (`Library.MediaProbe`),
  keyed by its `FilePresence` row (cascade-deleted with it).

  **Display-only by design.** These values inform the More-info pane —
  they are never inputs to matching, import gating, or any automated
  judgement. The one deliberate consequence: a file whose *container
  title* contradicts its filename (a renamed fake release) becomes
  visible at a glance instead of only at playback.

  Derived data per ADR-057: recomputable from the file at any time.
  Written at link time and backfilled by the boot sweep
  (`Library.probe_missing_media_info/0`); a probe failure simply leaves
  no row.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.Library.FilePresence

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "library_file_media_infos" do
    field :container_title, :string
    field :duration_seconds, :integer
    field :video_codec, :string
    field :width, :integer
    field :height, :integer
    field :audio_summary, :string

    belongs_to :file_presence, FilePresence

    timestamps(type: :utc_datetime)
  end

  @fields [
    :file_presence_id,
    :container_title,
    :duration_seconds,
    :video_codec,
    :width,
    :height,
    :audio_summary
  ]

  def changeset(info, attrs) do
    info
    |> cast(attrs, @fields)
    |> validate_required([:file_presence_id])
    |> unique_constraint(:file_presence_id)
  end
end
