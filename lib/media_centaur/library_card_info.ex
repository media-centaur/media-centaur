defmodule MediaCentaur.LibraryCardInfo do
  use Boundary, deps: [MediaCentaur.Settings]

  @moduledoc """
  Typed accessor for the `library_show_card_info` Settings entry.

  Controls whether the poster card footer (title + type/year) renders
  below each poster on the library page. The default is ON — the
  Settings entry is only written when the user opts out (for the
  pure wall-of-posters view).

  Reads route through `Settings.get_by_key/1`, which is itself
  `:persistent_term`-cached at the Settings layer (see
  `MediaCentaur.Settings`). No per-flag cache is needed here.
  """

  alias MediaCentaur.Settings

  @setting_key "library_show_card_info"

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc """
  Returns whether the poster card footer should render.

  Default-on: returns `true` whenever no Settings entry exists or the
  stored value is shaped unexpectedly. Only an explicit
  `%{"enabled" => false}` suppresses the footer.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    case Settings.get_by_key(@setting_key) do
      {:ok, %{value: value}} -> enabled?(value)
      _ -> true
    end
  end

  @doc """
  Parses a stored setting value into the flag. Default-on: only an explicit
  `%{"enabled" => false}` suppresses the footer. Lets the generic
  `SettingAware` on_mount trait apply the same polarity on live updates.
  """
  @spec enabled?(map()) :: boolean()
  def enabled?(%{"enabled" => false}), do: false
  def enabled?(_), do: true
end
