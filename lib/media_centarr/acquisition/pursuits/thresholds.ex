defmodule MediaCentarr.Acquisition.Pursuits.Thresholds do
  @moduledoc """
  Threshold values consumed by `Pursuits.Policy`.

  Loaded from `Settings` rows under the `pursuits.*` namespace; missing or
  non-positive values fall back to the built-in defaults below. The
  resulting struct is carried on `Snapshot` so `Policy` stays pure.
  """

  alias MediaCentarr.Settings

  @keys [
    "pursuits.max_attempts",
    "pursuits.min_age_days",
    "pursuits.stall_window_hours",
    "pursuits.zero_seeders_window_hours"
  ]

  @builtin_defaults %{
    max_attempts: 4,
    min_age_days: 6,
    stall_window_hours: 24,
    zero_seeders_window_hours: 6
  }

  defstruct Map.to_list(@builtin_defaults)

  @type t :: %__MODULE__{
          max_attempts: pos_integer(),
          min_age_days: pos_integer(),
          stall_window_hours: pos_integer(),
          zero_seeders_window_hours: pos_integer()
        }

  @doc "Loads thresholds from Settings, applying built-in fallbacks for missing or invalid keys."
  @spec load() :: t()
  def load do
    entries = Settings.get_by_keys(@keys)

    %__MODULE__{
      max_attempts: read(entries, "pursuits.max_attempts", @builtin_defaults.max_attempts),
      min_age_days: read(entries, "pursuits.min_age_days", @builtin_defaults.min_age_days),
      stall_window_hours:
        read(entries, "pursuits.stall_window_hours", @builtin_defaults.stall_window_hours),
      zero_seeders_window_hours:
        read(
          entries,
          "pursuits.zero_seeders_window_hours",
          @builtin_defaults.zero_seeders_window_hours
        )
    }
  end

  @doc "Returns the built-in default thresholds (ignoring Settings)."
  @spec defaults() :: t()
  def defaults, do: %__MODULE__{}

  defp read(entries, key, default) do
    case Map.get(entries, key) do
      %{value: %{"value" => value}} when is_integer(value) and value > 0 -> value
      _ -> default
    end
  end
end
