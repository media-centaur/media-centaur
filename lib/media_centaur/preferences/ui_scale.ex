defmodule MediaCentaur.Preferences.UIScale do
  @moduledoc """
  Typed accessor for the `ui_scale` Settings entry — the user's **preference
  factor** in the two-factor UI scale, where 1.0 means "as designed".

  The effective shell zoom is composed in CSS (`html { zoom: --ui-scale }`,
  see `assets/css/app.css`) as the product of two factors with different
  owners:

    * `--auto-scale` — owned by the design: screen width over the 1920 CSS px
      reference width the app is composed at, computed pre-paint by the inline
      head script in `root.html.heex`. Density correction is automatic; no
      user setup.
    * `--ui-scale-pref` — owned by the user: this setting, an accessibility /
      taste multiplier on top of the intended size.

  The preference is a bounded continuous multiplier, not an enum: any value on
  a 5% grid between `min/0` and `max/0`, adjusted through the Settings stepper
  in 5% steps. This module owns all of the arithmetic — `increment/1`,
  `decrement/1`, and `normalize/1` (snap-to-grid + clamp) — so the stepper
  component stays a dumb renderer of precomputed target values and no float
  math leaks into the view layer. The grid keeps stored values canonical and
  repeated stepping drift-free; the clamp guarantees no stored preference can
  make the shell unusable (the composed product carries a second, last-resort
  floor in `app.css`).

  The Settings table is the single source of truth for the preference. First
  paint is flash-free because `root.html.heex` server-renders
  `--ui-scale-pref` from `cached_scale/0`; live changes reach the open
  document through a `push_event` that sets the CSS custom property without a
  reload (see `SettingsLive`'s `set_ui_scale`). The custom property lives on
  `<html>`, which LiveView never tears down, so the scale persists across live
  navigation between pages.

  The root layout renders on *every* page, so its read must never touch the
  database (ADR-041, `NoDbOnRenderTest`). `cached_scale/0` is therefore
  cache-only via `Settings.get_cached/1`; production serves requests only after
  the settings cache is warm, so it returns the real value, while a cold cache
  (tests, boot window) harmlessly yields the default. The stepper and `set/1`
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

  # Adjustable range and step of the preference factor. 70% is the floor —
  # the automatic factor already handles density, so anything below that is
  # unreadably small on every surface we ship for. 200% is the ceiling for
  # the same reason in the other direction. Stored out-of-range values clamp
  # into the range; off-grid values snap to the 5% grid.
  @min 0.7
  @max 2.0
  @step 0.05
  # Grid steps per 1.0 — snapping computes `round(value × grid) / grid` so the
  # only float operation is a single division, which IEEE rounds to the same
  # double as the equivalent literal (0.7 == 14/20). Multiplying by @step
  # instead would reintroduce drift (14 × 0.05 ≠ 0.7 exactly).
  @grid round(1 / @step)

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc "The default scale (100%) used when the setting is unset."
  @spec default() :: float()
  def default, do: @default

  @doc "The smallest selectable preference factor."
  @spec min() :: float()
  def min, do: @min

  @doc "The largest selectable preference factor."
  @spec max() :: float()
  def max, do: @max

  @doc "The stepper increment (5%)."
  @spec step() :: float()
  def step, do: @step

  @doc "The next step up from `value`, clamped to `max/0`."
  @spec increment(term()) :: float()
  def increment(value), do: normalize(normalize(value) + @step)

  @doc "The next step down from `value`, clamped to `min/0`."
  @spec decrement(term()) :: float()
  def decrement(value), do: normalize(normalize(value) - @step)

  @doc "The current UI scale factor, clamped, defaulting to #{@default}."
  @spec scale() :: float()
  def scale do
    case Settings.get_by_key(@setting_key) do
      %{value: value} -> parse(value)
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
  float, integer, or string (the stepper submits `phx-value-choice` as a
  string). Returns the normalized float that was stored.
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

  @doc """
  Normalizes input to a float on the 5% grid within `min/0`..`max/0`;
  non-numbers fall back to the default. Snapping before clamping keeps every
  produced value canonical, so equality checks against the bounds are exact.
  """
  @spec normalize(term()) :: float()
  def normalize(value), do: value |> to_float() |> snap() |> clamp()

  @doc ~S(Formats a factor as an integer percent string, e.g. `1.25` → `"125%"`.)
  @spec percent(float()) :: String.t()
  def percent(scale), do: "#{round(scale * 100)}%"

  # Snap to the 5% grid via integer arithmetic so repeated stepping can't
  # accumulate binary-float drift (see @grid).
  defp snap(value), do: round(value * @grid) / @grid

  defp clamp(value), do: value |> Kernel.max(@min) |> Kernel.min(@max)

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
