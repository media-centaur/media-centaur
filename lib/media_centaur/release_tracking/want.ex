defmodule MediaCentaur.ReleaseTracking.Want do
  @moduledoc """
  One unit of durable acquisition intent on a tracked item — the want
  ledger of ADR-056.

  Distinct from `Release` (the wholesale-replaced TMDB calendar
  projection): a want is created when a unit becomes *acquirable*
  (aired and not in the library) and closes only by satisfaction or
  dismissal. Claim state ("a plan/pursuit is working on this") is
  deliberately NOT stored here — Acquisition derives it from active
  plan/pursuit units, so there is exactly one enforcement point and no
  dual-write drift.

  ## Unit identity

  TV wants carry `season_number`/`episode_number`; movie wants carry
  `part_tmdb_id` (the movie's own TMDB id — for solo tracking this
  equals the item's `tmdb_id`; for collection tracking it is the part's
  id). `unit_key` ("s1e2" / "m603") is the canonical dedup key because
  SQLite treats NULLs as distinct in unique indexes.

  ## Fields with non-obvious semantics

  * `wanted_since` — the patience/back-off anchor. The air date for
    units that aired before today (no patience restart for old units),
    the sync time for units airing today. Re-syncs never reset it.
  * `last_searched_at` — stamped when a plan run actually searches this
    unit's term; drives the stepped back-off schedule. Nil = never
    searched (due immediately).
  * `provenance` — `:calendar` for wants derived from the TMDB
    schedule; `:gap` for wants handed off from media-search plan
    approval (units planning could not find).
  * `satisfied_quality` — quality label of the file that satisfied the
    want, when classifiable from its path. The hook for the future
    quality-upgrades campaign.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "release_tracking_wants" do
    field :unit_key, :string
    field :season_number, :integer
    field :episode_number, :integer
    field :part_tmdb_id, :integer
    field :title, :string
    field :air_date, :date

    field :status, Ecto.Enum, values: [:open, :satisfied, :dismissed], default: :open
    field :provenance, Ecto.Enum, values: [:calendar, :gap], default: :calendar

    field :wanted_since, :utc_datetime
    field :last_searched_at, :utc_datetime
    field :satisfied_at, :utc_datetime
    field :satisfied_quality, :string
    field :dismissed_at, :utc_datetime

    belongs_to :item, MediaCentaur.ReleaseTracking.Item

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :item_id,
      :season_number,
      :episode_number,
      :part_tmdb_id,
      :title,
      :air_date,
      :provenance,
      :wanted_since
    ])
    |> validate_required([:item_id, :wanted_since])
    |> put_unit_key()
    |> validate_required([:unit_key])
    |> unique_constraint([:item_id, :unit_key],
      name: "release_tracking_wants_item_id_unit_key_index"
    )
  end

  @doc """
  Computes the canonical unit key for a TV unit or movie part. Returns
  `nil` when neither identity is complete — callers treat that as "this
  row cannot carry a want".
  """
  @spec unit_key(integer() | nil, integer() | nil, integer() | nil) :: String.t() | nil
  def unit_key(season_number, episode_number, _part_tmdb_id)
      when is_integer(season_number) and is_integer(episode_number) do
    "s#{season_number}e#{episode_number}"
  end

  def unit_key(_season, _episode, part_tmdb_id) when is_integer(part_tmdb_id) do
    "m#{part_tmdb_id}"
  end

  def unit_key(_season, _episode, _part), do: nil

  defp put_unit_key(changeset) do
    key =
      unit_key(
        get_field(changeset, :season_number),
        get_field(changeset, :episode_number),
        get_field(changeset, :part_tmdb_id)
      )

    put_change(changeset, :unit_key, key)
  end
end
