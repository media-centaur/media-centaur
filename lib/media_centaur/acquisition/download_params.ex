defmodule MediaCentaur.Acquisition.DownloadParams do
  @moduledoc """
  The per-title download params: what a person has said about *how* to
  acquire one title, as opposed to *whether* to follow it.

  Every field is nullable and a `nil` means "inherit the global default"
  (`AutoGrabSettings.effective_*`), so an absent record and an all-`nil`
  record mean the same thing. That is why this is an embedded value type
  rather than a row: a new param is a field here, not a migration, and
  `defaults/0` is a real value the whole app can pass around before
  anything has been stored.

  Stored by `MediaCentaur.Acquisition.TitleDownloadParams`, keyed by TMDB
  identity — never by tracked title. Storing them on
  `ReleaseTracking.Item` is what forced "Accept lower quality" to start
  tracking a title in order to have somewhere to write.

  `min_quality` additionally admits `"any"` — the per-title "best
  available" acceptance ([ADR-063] §2). It is a floor value only, never a
  ceiling, which is why `max_quality` does not admit it.

  [ADR-063]: `decisions/architecture/2026-06-27-063-plan-board-quality-acceptance.md`
  """
  use Ecto.Schema

  import Ecto.Changeset

  @quality_values ~w(hd_1080p uhd_4k)
  @max_patience_hours 24 * 30

  @type quality :: String.t()

  @type t :: %__MODULE__{
          min_quality: quality() | nil,
          max_quality: quality() | nil,
          quality_4k_patience_hours: non_neg_integer() | nil
        }

  @primary_key false
  embedded_schema do
    field :min_quality, :string
    field :max_quality, :string
    field :quality_4k_patience_hours, :integer
  end

  @fields [:min_quality, :max_quality, :quality_4k_patience_hours]

  @doc "The params a title has before anyone has said anything about it."
  @spec defaults() :: t()
  def defaults, do: %__MODULE__{}

  @doc """
  Merges `attrs` into `params`. An explicit `nil` clears that one param
  back to the global default and leaves the others alone — which is how
  "Reset" on a title's quality acceptance is expressed.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = params, attrs) do
    params
    |> cast(attrs, @fields)
    |> validate_inclusion(:min_quality, ["any" | @quality_values])
    |> validate_inclusion(:max_quality, @quality_values)
    |> validate_number(:quality_4k_patience_hours,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @max_patience_hours
    )
  end

  @doc """
  Whether the title carries the per-title acceptance ([ADR-063] §2): its
  searches take the best release that exists instead of holding to the
  quality preference. Set by "Take lower quality" on a plan board, reset
  from the title's own controls.
  """
  @spec lower_quality_accepted?(t()) :: boolean()
  def lower_quality_accepted?(%__MODULE__{min_quality: min_quality}), do: min_quality == "any"

  @doc "Whether anything has actually been said — an all-`nil` record says nothing."
  @spec any?(t()) :: boolean()
  def any?(%__MODULE__{} = params) do
    Enum.any?(@fields, &(not is_nil(Map.fetch!(params, &1))))
  end
end
