defmodule MediaCentaurWeb.Live.ProfileAware.Logic do
  @moduledoc "The pure rule behind `ProfileAware`: which profile a session is using, or that it must pick (UIDR-053)."

  alias MediaCentaur.Profiles.Profile

  @doc "The one profile; else the one the cookie names; else `:pick`."
  @spec resolve(String.t() | nil, [Profile.t()]) :: {:active, Profile.t()} | :pick
  def resolve(_cookie, [profile]), do: {:active, profile}

  def resolve(cookie, profiles) when is_binary(cookie) do
    case Enum.find(profiles, &(&1.id == cookie)) do
      nil -> :pick
      profile -> {:active, profile}
    end
  end

  def resolve(_cookie, _profiles), do: :pick
end
