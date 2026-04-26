defmodule MediaCentarr.Acquisition.AutoGrabSettings do
  @moduledoc """
  Resolves auto-grab preferences from per-item overrides + global defaults.

  Global defaults live in `Settings.Entry` rows under the `auto_grab.*`
  key namespace. Per-item overrides live as columns on
  `release_tracking_items`. This module is the single source of truth for
  "what does the policy actually use for this item right now?"

  Built-in fallback values match the project defaults documented in
  `decisions/architecture/...` (Phase 2 plan):
  - mode: `"all_releases"`
  - min quality: `"hd_1080p"` (final acceptable floor)
  - max quality: `"uhd_4k"`
  - 4K patience: 48 hours (insist on 4K for ~2 days before falling back)
  - max attempts: 12 (about a week at the snooze cap)

  Pure resolution functions take primitive item-side values, not the
  full `ReleaseTracking.Item` struct, to keep the inter-context surface
  to nothing more than the column types.
  """

  alias MediaCentarr.Settings

  @keys [
    "auto_grab.default_mode",
    "auto_grab.default_min_quality",
    "auto_grab.default_max_quality",
    "auto_grab.4k_patience_hours",
    "auto_grab.max_attempts"
  ]

  @builtin_defaults %{
    default_mode: "all_releases",
    default_min_quality: "hd_1080p",
    default_max_quality: "uhd_4k",
    patience_hours: 48,
    max_attempts: 12
  }

  defstruct Map.to_list(@builtin_defaults)

  @type mode :: String.t()
  @type quality :: String.t()
  @type t :: %__MODULE__{
          default_mode: mode(),
          default_min_quality: quality(),
          default_max_quality: quality(),
          patience_hours: non_neg_integer(),
          max_attempts: pos_integer()
        }

  @doc "Loads global defaults from Settings, applying built-in fallbacks for missing keys."
  @spec load() :: t()
  def load do
    entries = Settings.get_by_keys(@keys)

    %__MODULE__{
      default_mode: read(entries, "auto_grab.default_mode", @builtin_defaults.default_mode),
      default_min_quality:
        read(entries, "auto_grab.default_min_quality", @builtin_defaults.default_min_quality),
      default_max_quality:
        read(entries, "auto_grab.default_max_quality", @builtin_defaults.default_max_quality),
      patience_hours: read(entries, "auto_grab.4k_patience_hours", @builtin_defaults.patience_hours),
      max_attempts: read(entries, "auto_grab.max_attempts", @builtin_defaults.max_attempts)
    }
  end

  @doc "Resolves an item's effective auto-grab mode."
  @spec effective_mode(String.t() | nil, t()) :: mode()
  def effective_mode(item_mode, %__MODULE__{} = settings) when item_mode in ["global", nil],
    do: settings.default_mode

  def effective_mode(item_mode, %__MODULE__{}) when is_binary(item_mode), do: item_mode

  @doc "Resolves an item's effective minimum quality bound."
  @spec effective_min_quality(String.t() | nil, t()) :: quality()
  def effective_min_quality(nil, %__MODULE__{} = settings), do: settings.default_min_quality
  def effective_min_quality(value, %__MODULE__{}) when is_binary(value), do: value

  @doc "Resolves an item's effective maximum quality bound."
  @spec effective_max_quality(String.t() | nil, t()) :: quality()
  def effective_max_quality(nil, %__MODULE__{} = settings), do: settings.default_max_quality
  def effective_max_quality(value, %__MODULE__{}) when is_binary(value), do: value

  @doc """
  Resolves an item's effective 4K-patience window.

  `0` is a meaningful per-item override (\"no patience — take whatever's
  available immediately, ranking still prefers 4K\"). It is NOT treated
  as falling back to the global default.
  """
  @spec effective_patience_hours(non_neg_integer() | nil, t()) :: non_neg_integer()
  def effective_patience_hours(nil, %__MODULE__{} = settings), do: settings.patience_hours
  def effective_patience_hours(hours, %__MODULE__{}) when is_integer(hours), do: hours

  defp read(entries, key, default) do
    case Map.get(entries, key) do
      %{value: %{"value" => value}} -> value
      _ -> default
    end
  end
end
