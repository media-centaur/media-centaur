defmodule MediaCentaur.Acquisition.DownloadParams do
  @moduledoc """
  One title's lower-quality acceptance ([ADR-063] §2): what a person has
  said about *how* to acquire one title, as opposed to *whether* to
  follow it. `min_quality` is `"any"` when the title takes the best
  release that exists, `nil` when it holds to the automatic floor
  (`AutoGrabSettings.floor/0`).

  A `nil` means "inherit the global default", so an absent record and an
  all-`nil` record mean the same thing. That is why this is an embedded
  value type rather than a row: a new param is a field here, not a
  migration, and `defaults/0` is a real value the whole app can pass
  around before anything has been stored.

  Stored by `MediaCentaur.Acquisition.TitleDownloadParams`, keyed by TMDB
  identity — never by tracked title. Storing them on
  `ReleaseTracking.Item` is what forced "Accept lower quality" to start
  tracking a title in order to have somewhere to write.

  The per-title maximum and the 4K patience window this type once
  carried are gone (UIDR-041 §6): the highest resolution is a global
  choice and there is no window to be patient for.

  [ADR-063]: `decisions/architecture/2026-08-31-063-plan-diagnosis-model.md`
  """
  use Ecto.Schema

  import Ecto.Changeset

  @quality_values ~w(hd_1080p uhd_4k)

  @type quality :: String.t()

  @type t :: %__MODULE__{min_quality: quality() | nil}

  @primary_key false
  embedded_schema do
    field :min_quality, :string
  end

  @fields [:min_quality]

  @doc "The params a title has before anyone has said anything about it."
  @spec defaults() :: t()
  def defaults, do: %__MODULE__{}

  @doc """
  Merges `attrs` into `params`. An explicit `nil` clears the param back
  to the global default — which is how "Reset" on a title's quality
  acceptance is expressed.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = params, attrs) do
    params
    |> cast(attrs, @fields)
    |> validate_inclusion(:min_quality, ["any" | @quality_values])
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
