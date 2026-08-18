defmodule MediaCentaurWeb.Storybook.Detail.ViewControls do
  @moduledoc """
  The modal's view controls — the soft button and Manage cog that share
  Play's line.

  Pure presentation over the entity map: `Detail.Logic.secondary_view/2`
  decides where the control leads from `:type` and `:extras` alone, so the
  variations below are flat literal maps with no fakes or stubs.

  Contract pinned by the variations:

    * **The control is named for its destination, never "Back".**
      `:root_view` offers Cast; `:cast_open` and `:manage_open`
      both read "Episodes" with a list glyph. "Episodes" says where you are
      going; "Back" only says it is not here.
    * **The destination is not always the body.** `:manage_open_on_a_movie`
      reads "Cast", because a movie with no extras opens on Cast
      and that is what Manage returns to.
    * **One control, one slot.** The two buttons this replaced each
      relabelled themselves, so "Back" landed in the second or third slot
      depending on which sub-view was open.
    * **Manage never changes its label.** Compare `:root_view` with
      `:manage_open`: the cog takes `aria-pressed` and brightens, and the
      text beside it is unaffected.
    * **The slot empties when there is nowhere else to go.** A collection
      has no Cast view (`:collection`); a movie with no extras opens *on*
      Cast, so that is its root (`:movie_without_extras`). Both render
      Play's line with just the cog.
    * **A movie with a TMDB id gets the Letterboxd link** before the cog
      (`:movie_letterboxd_link`) — the tri-circle icon button linking to
      `letterboxd.com/tmdb/<id>`. Gated by the `letterboxd_links` setting
      (`:movie_letterboxd_off`); never shown without a `:tmdb_id`.
    * **A movie or TV subject with a TMDB id gets the watchlist bookmark**
      between the Letterboxd link and the cog. Off-list it is a quiet
      outline (`:movie_letterboxd_link`); on-list it flips solid with a
      primary tint and `aria-pressed` (`:movie_on_watchlist`). Never shown
      without a `:tmdb_id`, which is why the tmdb-id-less variations
      render without either icon button.

  Rendered here bare. In the app these sit inside `PlayCard`'s row via its
  `controls` slot, to the right of the Play button.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.ViewControls.view_controls/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="flex items-center gap-2">
      <.psb-variation/>
    </div>
    """
  end

  defp series, do: %{type: :tv_series, extras: []}

  def variations do
    [
      %Variation{
        id: :root_view,
        description:
          "A series on its episode list — the default opening. The control " <>
            "offers the other place worth going; the cog is unpressed.",
        attributes: %{entity: series(), detail_view: :main}
      },
      %Variation{
        id: :cast_open,
        description:
          "Cast showing. The same slot now reads \"Episodes\" with a " <>
            "list glyph — the same one the episode-details toggle uses.",
        attributes: %{entity: series(), detail_view: :cast}
      },
      %Variation{
        id: :manage_open,
        description:
          "Manage showing. \"Episodes\" is in the identical slot it occupies " <>
            "for Cast, and the cog brightens via `aria-pressed` rather " <>
            "than relabelling. Nothing in the row shifts between these states.",
        attributes: %{entity: series(), detail_view: :info}
      },
      %Variation{
        id: :manage_open_on_a_movie,
        description:
          "Manage showing on a movie with no extras. Its root view *is* More " <>
            "info, so that is where the control leads and what it is named " <>
            "for — there is no episode list here to label it after.",
        attributes: %{entity: %{type: :movie, extras: []}, detail_view: :info}
      },
      %Variation{
        id: :collection,
        description:
          "A collection (`:movie_series`) on its movie list has no " <>
            "collection-level cast, so there is no Cast view to " <>
            "offer — Play's line carries only the cog.",
        attributes: %{entity: %{type: :movie_series, extras: []}, detail_view: :main}
      },
      %Variation{
        id: :movie_with_extras,
        description:
          "A movie carrying entity-level extras has a body of its own, so " <>
            "Cast is a real second destination.",
        attributes: %{
          entity: %{type: :movie, extras: [%{owner_type: :movie}]},
          detail_view: :main
        }
      },
      %Variation{
        id: :movie_letterboxd_link,
        description:
          "A movie with a TMDB id carries the Letterboxd icon button " <>
            "before the cog — the film's Letterboxd page via the " <>
            "`/tmdb/<id>` redirect — and the watchlist bookmark in its " <>
            "quiet off-list state between the two.",
        attributes: %{
          entity: %{type: :movie, extras: [%{owner_type: :movie}], tmdb_id: "1001"},
          detail_view: :main
        }
      },
      %Variation{
        id: :movie_letterboxd_off,
        description:
          "The same movie with the `letterboxd_links` setting off — the " <>
            "Letterboxd button drops out; the watchlist bookmark is a " <>
            "library affordance and stays.",
        attributes: %{
          entity: %{type: :movie, extras: [%{owner_type: :movie}], tmdb_id: "1001"},
          detail_view: :main,
          letterboxd_links: false
        }
      },
      %Variation{
        id: :movie_on_watchlist,
        description:
          "The same movie already on the watchlist — the bookmark flips " <>
            "solid with a primary tint and `aria-pressed`, and its title " <>
            "offers removal.",
        attributes: %{
          entity: %{type: :movie, extras: [%{owner_type: :movie}], tmdb_id: "1001"},
          detail_view: :main,
          watchlisted?: true
        }
      },
      %Variation{
        id: :movie_without_extras,
        description:
          "A movie with nothing of its own to list opens on Cast — that " <>
            "*is* its root view, so the slot is empty rather than offering a " <>
            "control that goes where you already are.",
        attributes: %{entity: %{type: :movie, extras: []}, detail_view: :cast}
      }
    ]
  end
end
