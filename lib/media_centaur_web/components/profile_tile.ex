defmodule MediaCentaurWeb.Components.ProfileTile do
  @moduledoc """
  A profile on the "Who's watching?" picker (UIDR-053): the 96px identity
  tile, filled as a person of this install, over the name, truncated to
  the tile's column. Drawing only — the picker wraps it in the submit
  button of the form that activates the profile.
  """

  use Phoenix.Component

  alias MediaCentaurWeb.Components.Social.IdentityTile

  attr :name, :string, required: true
  attr :picture_url, :string, default: nil
  attr :hue, :integer, default: nil

  def profile_tile(assigns) do
    ~H"""
    <span class="flex w-36 flex-col items-center gap-3">
      <IdentityTile.identity_tile name={@name} picture_url={@picture_url} hue={@hue} own? size={96} />
      <span class="max-w-full truncate text-base">{@name}</span>
    </span>
    """
  end
end
