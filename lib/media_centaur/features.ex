defmodule MediaCentaur.Features do
  use Boundary, deps: [MediaCentaur.Settings], exports: [Feature, Runtime]

  @moduledoc """
  The features of the product an install can run with or without, and the
  one flag that says whether each is on (ADR-081).

  A **feature** is a named, optional capability with its own surface: a
  page, a Settings section, affordances on other surfaces, runtime work.
  Its **flag** is the one fact about it; everything that exists for the
  feature derives from that fact. Off means: no sidebar entry, no Settings
  section, no affordances, and none of the feature's processes or jobs
  running. The flag is a user preference stored in `MediaCentaur.Settings`
  under `feature:<id>`, read through the cached Settings layer.

  This module is the **registry**: `@features` is the one place a feature
  is declared. The readers:

    * `MediaCentaur.Features.Runtime` starts and stops a feature's
      supervision children as the flag changes; `MediaCentaur.Application`
      hands it each feature's children.
    * `MediaCentaurWeb.Live.FeaturesAware` assigns the enabled set to every
      LiveView and owns the turn-on action; the layout, the sidebar, the
      Settings shell, the Status board and the gated pages read the set.
    * Settings → Feature Flags lists the registry, one row per feature.

  A feature's **stage** says why a row exists: `:development` (unfinished;
  the row says so) or `:optional` (finished; a user may still not want it).
  The stage is about the feature; the input system's WIP notice is about a
  page's navigation, a different fact.

  Not a feature: a **capability** (`MediaCentaur.Capabilities`: an
  integration configured and tested), a **service start flag**
  (`Settings.Services`: pausing core background work), a **preference**
  (how a feature behaves, not whether it exists).
  """

  alias MediaCentaur.Features.Feature
  alias MediaCentaur.Settings

  @features [
    %Feature{
      id: :social,
      name: "Social",
      description:
        "Friends' reviews, watched titles and listings over Nostr relays, and the Social page.",
      default: true,
      stage: :optional
    },
    %Feature{
      id: :players,
      name: "Remote players",
      description:
        "TVs and other devices on your network paired with this install, and the pages they play from.",
      default: true,
      stage: :optional
    },
    %Feature{
      id: :apps,
      name: "Apps",
      description: "A launcher for Steam games and other programs outside your library.",
      default: false,
      stage: :optional
    }
  ]

  @ids Enum.map(@features, & &1.id)

  @doc "Every feature, in the order the Feature flags section lists them."
  @spec all() :: [Feature.t()]
  def all, do: @features

  @doc "The feature with this id, or nil."
  @spec get(atom()) :: Feature.t() | nil
  def get(id) when is_atom(id), do: Enum.find(@features, &(&1.id == id))

  @doc "The feature whose id spells `string`, or nil — for an id arriving from the DOM."
  @spec find(String.t()) :: Feature.t() | nil
  def find(string) when is_binary(string), do: Enum.find(@features, &(Atom.to_string(&1.id) == string))

  @doc "The Settings key holding the feature's flag."
  @spec key(atom()) :: String.t()
  def key(id) when id in @ids, do: "feature:#{id}"

  @doc "Whether a Settings key is a feature's flag."
  @spec feature_key?(String.t()) :: boolean()
  def feature_key?("feature:" <> rest), do: Enum.any?(@ids, &(Atom.to_string(&1) == rest))
  def feature_key?(_key), do: false

  @doc "Whether the feature is on: the stored flag, else its default."
  @spec enabled?(atom()) :: boolean()
  def enabled?(id) when id in @ids do
    feature = get(id)
    key(id) |> Settings.get_by_key() |> flag(feature.default)
  end

  @doc "The set of features that are on, in one read."
  @spec enabled() :: MapSet.t(atom())
  def enabled do
    stored = @ids |> Enum.map(&key/1) |> Settings.get_by_keys()

    for feature <- @features, flag(stored[key(feature.id)], feature.default), into: MapSet.new() do
      feature.id
    end
  end

  @doc """
  Persists the flag. Readers learn of it through
  `{:setting_changed, "feature:<id>", value}` on `Topics.settings_updates/0`.
  """
  @spec set(atom(), boolean()) :: Settings.Entry.t()
  def set(id, enabled?) when id in @ids and is_boolean(enabled?) do
    Settings.find_or_create_entry!(%{key: key(id), value: %{"enabled" => enabled?}})
  end

  def set(id, _enabled?), do: raise(ArgumentError, "#{inspect(id)} is not a registered feature")

  # Only an explicit boolean under "enabled" decides the flag; no entry, or
  # a value of another shape, is the default. The same rule as
  # `Settings.Preferences.BooleanSetting`, for the same reason: a wrong
  # read must fall back, never invert.
  defp flag(%{value: %{"enabled" => enabled?}}, _default) when is_boolean(enabled?), do: enabled?
  defp flag(_entry, default), do: default
end
