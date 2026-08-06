defmodule MediaCentaur.LibraryBackdrop do
  use Boundary, deps: [MediaCentaur.Settings]

  @moduledoc """
  Typed accessor for the `library_backdrop` Settings entry — whether the
  Library page renders its ambient artwork band (`.page-atmosphere`).
  The dark scrim underneath is unconditional; this flag only controls the
  image.

  Default-off: a fresh install renders no backdrop until the user turns
  it on. Installs that predate the flip keep their backdrop via the
  `SeedBackdropDefaultsForExistingInstalls` migration, which seeds an
  explicit `enabled: true` row on non-empty databases.

  Reads route through `Settings.get_by_key/1`, which is itself
  `:persistent_term`-cached at the Settings layer (see
  `MediaCentaur.Settings`). No per-flag cache is needed here.
  """

  alias MediaCentaur.Settings

  @setting_key "library_backdrop"

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc "Returns the current Library-backdrop flag."
  @spec enabled?() :: boolean()
  def enabled? do
    case Settings.get_by_key(@setting_key) do
      %{value: value} -> enabled?(value)
      _ -> false
    end
  end

  @doc """
  Parses a stored setting value into the flag. Default-off: only an explicit
  `%{"enabled" => true}` shows the backdrop. Lets the generic `SettingAware`
  on_mount trait apply the same polarity on live updates.
  """
  @spec enabled?(map()) :: boolean()
  def enabled?(%{"enabled" => true}), do: true
  def enabled?(_), do: false
end
