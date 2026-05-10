defmodule MediaCentarr.SpoilerFree do
  use Boundary, deps: [MediaCentarr.Settings]

  @moduledoc """
  Typed accessor for the `spoiler_free_mode` Settings entry.

  Reads route through `Settings.get_by_key/1`, which is itself
  `:persistent_term`-cached at the Settings layer (see
  `MediaCentarr.Settings`). No per-flag cache is needed here.
  """

  alias MediaCentarr.Settings

  @setting_key "spoiler_free_mode"

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc "Returns the current spoiler-free mode flag."
  @spec enabled?() :: boolean()
  def enabled? do
    case Settings.get_by_key(@setting_key) do
      {:ok, %{value: %{"enabled" => enabled}}} -> enabled == true
      _ -> false
    end
  end
end
