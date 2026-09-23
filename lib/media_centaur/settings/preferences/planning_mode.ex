defmodule MediaCentaur.Settings.Preferences.PlanningMode do
  @moduledoc """
  Typed accessor for the `default_planning_mode` Settings entry — what
  the Download button on a title the library does not own does when
  pressed (spec 2026-09-12 §9): `:manually_select_release` creates the
  plan for review and opens its board on Incoming; `:auto_select_best_release`
  creates it `automatic`, so a clean plan commits with nobody looking.
  The other mode is always one click away in the button's menu; this
  entry only names the default. It is also the approval policy every
  tracking plan is stamped with (`approval_policy/1`).

  Default `:manually_select_release`: an absent, malformed or unknown
  value all read as it, so a bad row can never turn on unattended
  commits.

  The mode also travels on the wire — a Download event's `mode` value, a
  plan link's `mode` param — as the same two strings; `parse_mode/1` is
  their one parser.

  Read where the title detail is built (`TitleDetailHost`), like the
  auto-grab default mode — not through `SettingAware`: the setting
  changes only on the Settings page, never underneath an open modal.
  """

  alias MediaCentaur.Settings

  @setting_key "default_planning_mode"
  @modes [:manually_select_release, :auto_select_best_release]
  @default :manually_select_release

  @type mode :: :manually_select_release | :auto_select_best_release

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc "Every mode, the default first."
  @spec modes() :: [mode()]
  def modes, do: @modes

  @doc "The current default mode; `:manually_select_release` when the entry is absent."
  @spec value() :: mode()
  def value do
    case Settings.get_by_key(@setting_key) do
      %{value: value} -> parse(value)
      _ -> @default
    end
  end

  @doc """
  Parses the mode's wire form — the string a Download event's `mode`
  value or a plan link's `mode` param carries. `:error` for anything
  else; each caller decides what an absent or unknown value means (the
  Download button: the title's default; a plan link: the person's
  default, or a malformed link).
  """
  @spec parse_mode(term()) :: {:ok, mode()} | :error
  def parse_mode("auto_select_best_release"), do: {:ok, :auto_select_best_release}
  def parse_mode("manually_select_release"), do: {:ok, :manually_select_release}
  def parse_mode(_other), do: :error

  @doc "Parses a stored value; anything but a known mode string is the default."
  @spec parse(term()) :: mode()
  def parse(%{"mode" => mode}) do
    case parse_mode(mode) do
      {:ok, mode} -> mode
      :error -> @default
    end
  end

  def parse(_value), do: @default

  @doc "The mode the button's menu offers beside the default."
  @spec other(mode()) :: mode()
  def other(:manually_select_release), do: :auto_select_best_release
  def other(:auto_select_best_release), do: :manually_select_release

  @doc """
  The approval policy a plan made under `mode` carries: auto-select
  commits a clean plan with nobody looking; manual select parks it for a
  person. The one mapping, read by the Download button and by the drop
  planner alike (spec 2026-09-14) — a tracking plan asks first exactly
  when a manual download would.
  """
  @spec approval_policy(mode()) :: String.t()
  def approval_policy(:auto_select_best_release), do: "automatic"
  def approval_policy(:manually_select_release), do: "review"

  @doc "Persists the default mode. Subscribers learn of it through `{:setting_changed, key, value}`."
  @spec set(mode()) :: Settings.Entry.t()
  def set(mode) when mode in @modes do
    Settings.find_or_create_entry!(%{key: @setting_key, value: %{"mode" => Atom.to_string(mode)}})
  end
end
