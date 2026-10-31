defmodule MediaCentaurWeb.SettingsLive.SectionsLogic do
  @moduledoc """
  Which Settings sections a reader sees (ADR-081). A section may name a
  `feature:`; it is listed, and its content drawn, only while that feature
  is on. Pure over the section list and the enabled set (ADR-030).
  """

  alias MediaCentaur.Features
  alias MediaCentaur.Features.Feature

  @type section :: %{
          required(:id) => String.t(),
          optional(:feature) => atom(),
          optional(atom()) => term()
        }

  @doc "The sections to list: every one whose feature, if it names one, is on."
  @spec visible([section()], MapSet.t(atom())) :: [section()]
  def visible(sections, features) do
    Enum.reject(sections, &hidden?(&1, features))
  end

  @doc """
  The feature that hides the section with this id, or nil when the section
  is visible (or unknown — the shell's "does not exist" copy handles that).
  """
  @spec hidden_feature([section()], String.t(), MapSet.t(atom())) :: Feature.t() | nil
  def hidden_feature(sections, id, features) do
    case Enum.find(sections, &(&1.id == id)) do
      %{feature: feature_id} = section when is_atom(feature_id) ->
        if hidden?(section, features), do: Features.get(feature_id)

      _visible_or_unknown ->
        nil
    end
  end

  defp hidden?(%{feature: feature_id}, features) when is_atom(feature_id), do: feature_id not in features
  defp hidden?(_section, _features), do: false
end
