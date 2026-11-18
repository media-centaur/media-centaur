defmodule MediaCentaur.Features do
  use Boundary, deps: [MediaCentaur.FlagSupervisor, MediaCentaur.Settings], exports: [Feature, Runtime]

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

  A feature may **require** another (`Feature.requires`): the Local API
  is part of downloads, since every route of it searches for or fetches a
  release. Such a feature is on
  only while the one it requires is on — `enabled?/1` and `enabled/0`
  answer that, so no reader asks two flags — and its Feature flags row is
  listed only then (`available/1`).

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
      id: :acquisition,
      name: "Downloads",
      description:
        "The Downloads page, the Download button on a title, and automatic downloads of the titles you follow. Needs Prowlarr.",
      default: true,
      stage: :optional
    },
    %Feature{
      id: :new_releases,
      name: "New releases on Search",
      description:
        "Fetches the films newly out to stream, rent or buy once a day, for the Search page's New Releases shelf.",
      default: true,
      stage: :optional
    },
    %Feature{
      id: :apps,
      name: "Apps",
      description: "A launcher for Steam games and other programs outside your library.",
      default: false,
      stage: :optional
    },
    %Feature{
      id: :local_api,
      name: "Local API",
      description:
        "A JSON API for scripts and agents on your network to find, download and follow films and series.",
      default: false,
      stage: :optional,
      requires: :acquisition
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

  @doc """
  Whether the feature is on: the stored flag, else its default — and, for
  a feature that requires another, only while that one is on.
  """
  @spec enabled?(atom()) :: boolean()
  def enabled?(id) when id in @ids do
    feature = get(id)

    key(id) |> Settings.get_by_key() |> flag(feature.default) and
      (feature.requires == nil or enabled?(feature.requires))
  end

  @doc "The set of features that are on, in one read."
  @spec enabled() :: MapSet.t(atom())
  def enabled do
    stored = @ids |> Enum.map(&key/1) |> Settings.get_by_keys()
    flagged = for feature <- @features, flag(stored[key(feature.id)], feature.default), do: feature.id

    for feature <- @features, on?(feature, flagged), into: MapSet.new(), do: feature.id
  end

  defp on?(nil, _flagged), do: false
  defp on?(%Feature{id: id, requires: nil}, flagged), do: id in flagged

  defp on?(%Feature{id: id, requires: requires}, flagged),
    do: id in flagged and on?(get(requires), flagged)

  @doc """
  The features a reader can switch, given the enabled set: every feature
  that requires nothing, and one that requires another while that one is
  on. The Feature flags section lists these.
  """
  @spec available(MapSet.t(atom())) :: [Feature.t()]
  def available(enabled) do
    Enum.filter(@features, &(&1.requires == nil or MapSet.member?(enabled, &1.requires)))
  end

  @doc "Turns the feature on, and before it whatever it requires."
  @spec turn_on(atom()) :: :ok
  def turn_on(id) when id in @ids do
    case get(id).requires do
      nil -> :ok
      requires -> turn_on(requires)
    end

    set(id, true)
    :ok
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
