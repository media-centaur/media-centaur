defmodule MediaCentaur.SpoilerFree do
  use Boundary, deps: [MediaCentaur.Settings]

  @moduledoc """
  Typed accessor for the `spoiler_free_mode` Settings entry.

  Reads route through `Settings.get_by_key/1`, which is itself
  `:persistent_term`-cached at the Settings layer (see
  `MediaCentaur.Settings`). No per-flag cache is needed here.
  """

  alias MediaCentaur.Settings

  @setting_key "spoiler_free_mode"

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc "Returns the current spoiler-free mode flag."
  @spec enabled?() :: boolean()
  def enabled? do
    case Settings.get_by_key(@setting_key) do
      %{value: value} -> enabled?(value)
      _ -> false
    end
  end

  @doc """
  Parses a stored setting value into the flag. Default-off: only an explicit
  `%{"enabled" => true}` enables spoiler-free mode. Lets the generic
  `SettingAware` on_mount trait apply the same polarity on live updates.
  """
  @spec enabled?(map()) :: boolean()
  def enabled?(%{"enabled" => true}), do: true
  def enabled?(_), do: false
end
