defmodule MediaCentaurWeb.Components.ProfileTile do
  @moduledoc """
  A place in the "Who's watching?" picker's row (UIDR-053), one column
  of two kinds. `profile_tile/1` is a person: the 128px identity tile —
  the largest this tile draws anywhere, since the picker is the one
  couch-distance moment it owns — filled as a person of this install,
  over the name, truncated to the column; `current?` marks the
  session's active profile on a switch with the chosen outline a hue
  swatch wears. `add_tile/1` is the place that becomes a person: a
  dashed circle the same size, with a plus, over "Add profile".
  Drawing only — the picker wraps each in its button: the form that
  activates the profile, or the press that opens the name field in the
  add tile's place. `.profile-tile*` and `.profile-add-mark` in
  `app.css`.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaurWeb.Components.Social.IdentityTile

  attr :name, :string, required: true
  attr :picture_url, :string, default: nil
  attr :hue, :integer, default: nil
  attr :current?, :boolean, default: false, doc: "the session's active profile, on a switch"

  def profile_tile(assigns) do
    ~H"""
    <span class={[
      "profile-tile flex w-40 flex-col items-center gap-3",
      @current? && "profile-tile-current"
    ]}>
      <IdentityTile.identity_tile name={@name} picture_url={@picture_url} hue={@hue} own? size={128} />
      <span class="max-w-full truncate text-base leading-tight">{@name}</span>
    </span>
    """
  end

  def add_tile(assigns) do
    ~H"""
    <span class="profile-tile flex w-40 flex-col items-center gap-3">
      <span class="profile-add-mark grid size-32 place-items-center rounded-full" aria-hidden="true">
        <.icon name="hero-plus" class="size-14" />
      </span>
      <span class="text-base leading-tight text-base-content/60">Add profile</span>
    </span>
    """
  end
end
