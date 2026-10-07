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

  @doc """
  The page a picker visit returns to: the URI's path, with its query when
  it has one, form-encoded for a `return_to` query value.
  """
  @spec return_to(String.t()) :: String.t()
  def return_to(uri) do
    %URI{path: path, query: query} = URI.parse(uri)
    URI.encode_www_form(if query, do: path <> "?" <> query, else: path)
  end
end
