defmodule MediaCentaur.UIScale do
  use Boundary, deps: [MediaCentaur.Settings]

  @moduledoc """
  Typed accessor for the `ui_scale` Settings entry — a global zoom factor
  applied to the whole app shell (`#input-system { zoom: var(--ui-scale) }`).

  The Settings table is the single source of truth. First paint is flash-free
  because `root.html.heex` server-renders `--ui-scale` from `cached_scale/0`;
  live changes reach the open document through a `push_event` that sets the CSS
  custom property without a reload (see `SettingsLive`'s `set_ui_scale`). The
  custom property lives on `<html>`, which LiveView never tears down, so the
  scale persists across live navigation between pages.

  The root layout renders on *every* page, so its read must never touch the
  database (ADR-041, `NoDbOnRenderTest`). `cached_scale/0` is therefore
  cache-only via `Settings.get_cached/1`; production serves requests only after
  the settings cache is warm, so it returns the real value, while a cold cache
  (tests, boot window) harmlessly yields the default. The picker and `set/1`
  use `scale/0`, which keeps the normal `Settings.get_by_key/1` DB fallback for
  read-after-write correctness.

  ## Why this is not a `SettingAware` assign

  Every *content-affecting* setting (spoiler-free, card info) flows through the
  `MediaCentaurWeb.Live.SettingAware` on_mount trait, which subscribes each
  LiveView and seeds a socket assign that the server-rendered HTML reads. UI
  scale deliberately does **not**: it is purely presentational, so no page
  needs a `:ui_scale` assign to render correctly — a single CSS custom property
  on `<html>` does the whole job. Forcing it through the (boolean) trait would
  add a per-page assign that nothing reads. The one consequence is that a
  *second* open window won't pick up a scale change until it reloads; for a
  single-window desktop app that never happens.
  """

  alias MediaCentaur.Settings

  @setting_key "ui_scale"
  @default 1.0

  # Selectable steps shown in the Preferences picker, smallest → largest. The
  # clamp range is derived from this list, so the picker and `set/1` can never
  # disagree about the bounds.
  @options [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]
  @min Enum.min(@options)
  @max Enum.max(@options)

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc "The default scale (100%) used when the setting is unset."
  @spec default() :: float()
  def default, do: @default

  @doc "Selectable scale steps for the Preferences picker."
  @spec options() :: [float()]
  def options, do: @options

  @doc "Selectable `{factor, label}` pairs for the Preferences picker, e.g. `{1.25, \"125%\"}`."
  @spec choices() :: [{float(), String.t()}]
  def choices, do: Enum.map(@options, &{&1, percent(&1)})

  @doc "The current UI scale factor, clamped, defaulting to #{@default}."
  @spec scale() :: float()
  def scale do
    case Settings.get_by_key(@setting_key) do
      {:ok, %{value: value}} -> parse(value)
      _ -> @default
    end
  end

  @doc """
  Render-path scale factor — cache-only, never hits the database (see the
  moduledoc). Returns the default when the settings cache is cold.
  """
  @spec cached_scale() :: float()
  def cached_scale do
    case Settings.get_cached(@setting_key) do
      %{value: value} -> parse(value)
      _ -> @default
    end
  end

  @doc """
  Persists a new scale, normalizing and clamping the input first. Accepts a
  float, integer, or string (the picker submits `phx-value-scale` as a string).
  Returns the clamped float that was stored.
  """
  @spec set(term()) :: float()
  def set(value) do
    scale = normalize(value)
    Settings.find_or_create_entry!(%{key: @setting_key, value: %{"scale" => scale}})
    scale
  end

  @doc """
  Parses a stored setting value into a clamped scale factor. Any shape without
  a numeric `"scale"` falls back to the default, so a malformed entry can never
  blank the UI.
  """
  @spec parse(map()) :: float()
  def parse(%{"scale" => value}), do: normalize(value)
  def parse(_), do: @default

  @doc "Normalizes input to a clamped float; non-numbers fall back to the default."
  @spec normalize(term()) :: float()
  def normalize(value), do: value |> to_float() |> clamp()

  @doc ~S(Formats a factor as an integer percent string, e.g. `1.25` → `"125%"`.)
  @spec percent(float()) :: String.t()
  def percent(scale), do: "#{round(scale * 100)}%"

  defp clamp(value), do: value |> max(@min) |> min(@max)

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _rest} -> float
      :error -> @default
    end
  end

  defp to_float(_), do: @default
end
