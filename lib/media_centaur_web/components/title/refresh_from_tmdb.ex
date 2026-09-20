defmodule MediaCentaurWeb.Components.Title.RefreshFromTmdb do
  @moduledoc """
  *Refresh from TMDB* — the one control that asks TMDB about a title
  again, regardless of when the app would next ask on its own
  (UIDR-044; ADR-071). It sits on the Manage toolbar for an owned title
  and under the tracking switches for a tracked title the library does
  not own, and fires the same event on both: `refresh_from_tmdb` with
  the title's ref. The host runs `TMDB.Store.check/1` off the view and
  flashes one of three outcomes — unchanged, updated, or TMDB did not
  answer. No confirm step: a check costs one request and changes nothing
  a person would want to undo.

  `checking?` is the in-flight state: the label reads *Checking…* and the
  control is disabled until the answer lands.
  """
  use MediaCentaurWeb, :html

  attr :id, :string, required: true
  attr :ref, :string, required: true, doc: "the title's ref, `TitleRef.param/1`."

  attr :surface, :atom,
    default: :toolbar,
    values: [:toolbar, :tracking],
    doc: "the Manage toolbar (neutral, small, with an icon) or the tracking card (quiet, extra small)."

  attr :checking?, :boolean, default: false
  attr :class, :string, default: nil

  def refresh_from_tmdb(assigns) do
    ~H"""
    <.button
      id={@id}
      variant={if @surface == :toolbar, do: "neutral", else: "dismiss"}
      size={if @surface == :toolbar, do: "sm", else: "xs"}
      class={@class}
      phx-click="refresh_from_tmdb"
      phx-value-ref={@ref}
      disabled={@checking?}
      data-role="refresh-from-tmdb"
      data-nav-item
      tabindex="0"
    >
      <.icon :if={@surface == :toolbar} name="hero-cloud-arrow-down-mini" class="size-4" />
      {if @checking?, do: "Checking…", else: "Refresh from TMDB"}
    </.button>
    """
  end
end
