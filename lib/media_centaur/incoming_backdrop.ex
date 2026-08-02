defmodule MediaCentaur.IncomingBackdrop do
  use Boundary, deps: [MediaCentaur.Settings]

  @moduledoc """
  Typed accessor for the `incoming_backdrop` Settings entry — whether the
  Incoming page renders its ambient artwork band (`.page-atmosphere`).
  The dark scrim underneath is unconditional; this flag only controls the
  image.

  Reads route through `Settings.get_by_key/1`, which is itself
  `:persistent_term`-cached at the Settings layer (see
  `MediaCentaur.Settings`). No per-flag cache is needed here.
  """

  alias MediaCentaur.Settings

  @setting_key "incoming_backdrop"

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc "Returns the current Incoming-backdrop flag."
  @spec enabled?() :: boolean()
  def enabled? do
    case Settings.get_by_key(@setting_key) do
      {:ok, %{value: value}} -> enabled?(value)
      _ -> true
    end
  end

  @doc """
  Parses a stored setting value into the flag. Default-on: only an explicit
  `%{"enabled" => false}` hides the backdrop. Lets the generic `SettingAware`
  on_mount trait apply the same polarity on live updates.
  """
  @spec enabled?(map()) :: boolean()
  def enabled?(%{"enabled" => false}), do: false
  def enabled?(_), do: true
end
