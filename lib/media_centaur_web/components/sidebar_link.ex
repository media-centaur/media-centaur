defmodule MediaCentaurWeb.Components.SidebarLink do
  @moduledoc """
  One entry of the main navigation rail: an icon-only link named by its
  label, which is also its tip beside the rail (the Tooltip hook), and a
  nav item of the `sidebar` zone.

  The rail says three independent things about an entry, each with one
  owner and one drawing:

    * **where you are** — `active`, the current page: a wash and the icon
      in the entry's accent, `aria-current="page"`;
    * **what waits** — `count`, the follow-up pill (UIDR-030) at the box's
      top-right corner, and `condition`, the dot at the icon's
      bottom-right meaning something is wrong right now;
    * **where the cursor is** — the keyboard/gamepad ring, drawn by the
      input system's CSS in the same accent.

  The accent is `--rail-accent`: primary for every page, the person's hue
  for the profile switcher (`hue`, UIDR-053 rule 3), so the wash, the icon
  and the ring of one entry always tell one colour story. `system` marks
  an entry of the System group, drawn dimmer at rest. `remember` keeps the
  target page's last URL across navigation (`data-nav-remember`).
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaurWeb.Components.FollowUpPill
  alias MediaCentaurWeb.Components.Social.IdentityTile

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :label, :string, required: true, doc: "the entry's name: its aria-label and its tip"
  attr :icon, :string, required: true, doc: "a heroicon name"
  attr :active, :boolean, default: false, doc: "the current page"
  attr :system, :boolean, default: false, doc: "an entry of the System group"
  attr :count, :integer, default: 0, doc: "items waiting on a decision; 0 draws no pill"
  attr :condition, :boolean, default: false, doc: "something is wrong right now"
  attr :remember, :boolean, default: false, doc: "keep the page's URL across navigation"
  attr :hue, :integer, default: nil, doc: "a person's hue as the accent — the profile switcher"
  attr :rest, :global, doc: "the shell's per-entry nav attributes, passed through to the link"

  def sidebar_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class={[
        "sidebar-link",
        @system && "sidebar-link-system",
        @active && "sidebar-link-active",
        @hue && "sidebar-link-profile"
      ]}
      aria-label={@label}
      aria-current={@active && "page"}
      data-tip={@label}
      data-hue={@hue}
      data-nav-item
      data-nav-remember={@remember}
      tabindex="0"
      {IdentityTile.hue_style(@hue)}
      {@rest}
    >
      <span class="relative inline-flex flex-shrink-0">
        <.icon name={@icon} class="size-5" />
        <span
          :if={@condition}
          id={"#{@id}-condition-dot"}
          class="sidebar-condition-dot"
          aria-hidden="true"
        />
      </span>
      <FollowUpPill.follow_up_pill id={"#{@id}-follow-up"} count={@count} />
    </.link>
    """
  end
end
