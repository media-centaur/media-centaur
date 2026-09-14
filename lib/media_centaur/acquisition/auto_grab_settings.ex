defmodule MediaCentaur.Acquisition.AutoGrabSettings do
  @moduledoc """
  The global auto-grab defaults, and the one place they are written.

  Global defaults live in `Settings.Entry` rows under the `auto_grab.*`
  key namespace; `put/2` is their only writer and refuses a field it does
  not own, an enum value it does not list, or an integer off its ladder.
  A title's own lower-quality acceptance lives in
  `Acquisition.TitleDownloadParams`, resolved here by
  `effective_min_quality/1`.

  There is no grab mode here. Whether a title auto-grabs is its rung
  (`Discovery.TitleIntent.grabs?/1`); whether the plan commits alone is
  the person's planning mode (`Settings.Preferences.PlanningMode`).

  Built-in fallback values:
  - max quality: `"uhd_4k"`
  - max attempts: 12 (about a week at the snooze cap)
  - pack fit: 75 %
  - size preference: `"fidelity"` (ADR-061)

  The floor is fixed at 1080p (`floor/0`); there is no patience window
  (UIDR-041 §6). Below the floor a release is taken only under a title's
  acceptance (ADR-063 §2).
  """

  alias MediaCentaur.Settings

  @keys [
    "auto_grab.default_max_quality",
    "auto_grab.max_attempts",
    "auto_grab.pack_min_fit",
    "auto_grab.size_preference"
  ]

  @floor "hd_1080p"
  @pack_fit_ladder Enum.to_list(5..100//5)
  @attempts_ladder Enum.to_list(1..50)

  @builtin_defaults %{
    default_max_quality: "uhd_4k",
    max_attempts: 12,
    # Grab a season/series pack only when you want at least this % of the
    # episodes it lands (`wanted-in-span / span-total`). Below it, the
    # pack is a one-click offer, not an auto-grab — so picking one episode
    # never pulls the whole series. "Most of the span" default.
    pack_min_fit: 75,
    # Which within-tier source ladder ranks releases (ADR-061):
    # "fidelity" (remux first) or "space" (compact encodes first).
    size_preference: "fidelity"
  }

  @allowed %{
    default_max_quality: ~w(uhd_4k hd_1080p),
    size_preference: ~w(fidelity space),
    pack_min_fit: @pack_fit_ladder,
    max_attempts: @attempts_ladder
  }

  @storage_key %{
    default_max_quality: "auto_grab.default_max_quality",
    size_preference: "auto_grab.size_preference",
    pack_min_fit: "auto_grab.pack_min_fit",
    max_attempts: "auto_grab.max_attempts"
  }

  defstruct Map.to_list(@builtin_defaults)

  @type quality :: String.t()
  @type field :: :default_max_quality | :size_preference | :pack_min_fit | :max_attempts
  @type t :: %__MODULE__{
          default_max_quality: quality(),
          max_attempts: pos_integer(),
          pack_min_fit: non_neg_integer(),
          size_preference: String.t()
        }

  @doc "Loads global defaults from Settings, applying built-in fallbacks for missing keys."
  @spec load() :: t()
  def load do
    entries = Settings.get_by_keys(@keys)

    %__MODULE__{
      default_max_quality:
        read(entries, "auto_grab.default_max_quality", @builtin_defaults.default_max_quality),
      max_attempts: read(entries, "auto_grab.max_attempts", @builtin_defaults.max_attempts),
      pack_min_fit: read(entries, "auto_grab.pack_min_fit", @builtin_defaults.pack_min_fit),
      size_preference: read(entries, "auto_grab.size_preference", @builtin_defaults.size_preference)
    }
  end

  @doc """
  The automatic floor. Below it a release is taken only under a title's
  own lower-quality acceptance (ADR-063 §2). Fixed, not a setting: the
  policy is "the best available now, then down the ladder" (UIDR-041 §6).
  """
  @spec floor() :: quality()
  def floor, do: @floor

  @doc "A title's effective floor: its lower-quality acceptance when it has one, else `floor/0`."
  @spec effective_min_quality(String.t() | nil) :: quality()
  def effective_min_quality(nil), do: @floor
  def effective_min_quality(value) when is_binary(value), do: value

  @doc "The stepper ladder for `pack_min_fit`: 5–100 in steps of 5."
  @spec pack_fit_ladder() :: [pos_integer()]
  def pack_fit_ladder, do: @pack_fit_ladder

  @doc "The stepper ladder for `max_attempts`: 1–50."
  @spec attempts_ladder() :: [pos_integer()]
  def attempts_ladder, do: @attempts_ladder

  @doc """
  The one write for a global auto-grab default. Refuses a field it does
  not own, an enum value it does not list, or an integer off the ladder.
  """
  @spec put(atom(), term()) :: :ok | {:error, :invalid}
  def put(field, value) when is_map_key(@allowed, field) do
    if value in Map.fetch!(@allowed, field) do
      Settings.find_or_create_entry!(%{key: Map.fetch!(@storage_key, field), value: %{"value" => value}})
      :ok
    else
      {:error, :invalid}
    end
  end

  def put(_field, _value), do: {:error, :invalid}

  defp read(entries, key, default) do
    case Map.get(entries, key) do
      %{value: %{"value" => value}} -> value
      _ -> default
    end
  end
end
