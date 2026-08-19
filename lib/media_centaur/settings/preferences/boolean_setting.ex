defmodule MediaCentaur.Settings.Preferences.BooleanSetting do
  @moduledoc """
  Generates a typed accessor for a boolean Settings entry.

      use MediaCentaur.Settings.Preferences.BooleanSetting, key: "library_backdrop", default: false

  Defines `setting_key/0`, `enabled?/0` and `enabled?/1` on the calling
  module. Four flags shared this shape, differing only in the key and the
  default; the module keeps its own `@moduledoc` explaining what the flag
  means, which is the part that was never duplicated.

  `default:` is required and load-bearing. Three of the four flags are
  default-off, but `library_show_card_info` is default-**on** — its entry is
  only written when the user opts out. A wrong default silently inverts a
  user's setting rather than failing, so there is no default default and a
  non-boolean raises at compile time.

  Reads route through `Settings.get_by_key/1`, which is itself
  `:persistent_term`-cached at the Settings layer (see `MediaCentaur.Settings`).
  No per-flag cache is needed here.

  Both polarities come out of one clause pair: a stored value decides the
  flag only when it carries a boolean under `"enabled"`, and everything else
  — no entry, no key, a string `"true"` — falls back to `default:`. That is
  also what lets the generic `MediaCentaurWeb.Live.SettingAware` on_mount
  trait apply the right polarity on live updates without knowing which flag
  it is holding.
  """

  @doc false
  defmacro __using__(opts) do
    key = Keyword.fetch!(opts, :key)
    default = Keyword.fetch!(opts, :default)

    if !is_boolean(default) do
      raise ArgumentError,
            "use MediaCentaur.Settings.Preferences.BooleanSetting expects a literal boolean `default:`, got: " <>
              inspect(default)
    end

    enabled_doc = """
    Returns the current flag. Defaults to `#{inspect(default)}` when the
    Settings entry is absent.
    """

    parse_doc = """
    Parses a stored setting value into the flag. Only an explicit boolean
    under `"enabled"` decides it; anything else falls back to
    `#{inspect(default)}`.
    """

    quote do
      alias MediaCentaur.Settings

      @setting_key unquote(key)
      @setting_default unquote(default)

      @doc "The setting key in the Settings table."
      @spec setting_key() :: String.t()
      def setting_key, do: @setting_key

      @doc unquote(enabled_doc)
      @spec enabled?() :: boolean()
      def enabled? do
        case Settings.get_by_key(@setting_key) do
          %{value: value} -> enabled?(value)
          _ -> @setting_default
        end
      end

      @doc unquote(parse_doc)
      @spec enabled?(map()) :: boolean()
      def enabled?(%{"enabled" => enabled}) when is_boolean(enabled), do: enabled
      def enabled?(_value), do: @setting_default
    end
  end
end
