defmodule MediaCentaurWeb.Storybook.Detail.ViewControls do
  @moduledoc """
  The controls sharing the action row with the primary — the one view
  control, the Letterboxd link, the bookmark, Review and the Manage cog,
  each present by what the detail's facts say (UIDR-043).

  Pure presentation over the `Title.Detail`: `Detail.Logic.secondary_view/2`
  decides where the view control leads from the subject's type and
  extras alone, so the variations below are flat literal structs.

  Contract pinned by the variations:

    * **The control is named for its destination, never "Back".**
      `:root_view` offers Cast; `:cast_open` and `:manage_open`
      both read "Episodes" with a list glyph.
    * **The destination is not always the body.** `:manage_open_on_a_movie`
      reads "Cast", because a movie with no extras opens on Cast
      and that is what Manage returns to.
    * **Manage never changes its label.** Compare `:root_view` with
      `:manage_open`: the cog takes `aria-pressed` and brightens.
    * **The slot empties when there is nowhere else to go.** A collection
      has no Cast view (`:collection`); a movie with no extras opens *on*
      Cast, so that is its root (`:movie_without_extras`).
    * **A movie with a TMDB identity gets the Letterboxd link** before
      the cog (`:movie_letterboxd_link`), gated by the `letterboxd_links`
      setting (`:movie_letterboxd_off`).
    * **A title with a TMDB identity gets the bookmark** between the
      Letterboxd link and the cog — a quiet outline off the list, solid
      with `aria-pressed` on it (`:movie_on_watchlist`). The residue
      (`:root_view`'s series carries no identity) renders neither.
    * **Review rides on the Discovery preview** (`:movie_review`).
    * **An unowned title has no views and no files** — only the
      Letterboxd link, the bookmark and Review (`:unowned_movie`).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.EntityView
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.ViewModel.LeafDetail

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

  # An owned title: the entity is the subject; a TMDB id gives it a ref.
  defp owned(type, opts \\ []) do
    tmdb_id = Keyword.get(opts, :tmdb_id)

    entity = %EntityView{
      id: "00000000-0000-0000-0000-0000000000d1",
      type: type,
      name: "Sample",
      tmdb_id: tmdb_id,
      extras: Keyword.get(opts, :extras, [])
    }

    media_type = if type == :tv_series, do: :tv_series, else: :movie

    %TitleDetail{
      ref: tmdb_id && {String.to_integer(tmdb_id), media_type},
      title:
        tmdb_id &&
          Title.new!(%{tmdb_id: String.to_integer(tmdb_id), media_type: media_type, name: "Sample"}),
      rung: Keyword.get(opts, :rung),
      library: %TitleDetail.Library{
        entry: %LeafDetail{entity: entity, progress: nil, progress_records: [], resume_target: nil},
        subject: entity
      }
    }
  end

  defp unowned_movie do
    title = Title.new!(%{tmdb_id: 1001, media_type: :movie, name: "Sample", year: "2010"})
    %TitleDetail{ref: Title.ref(title), title: title, rung: nil}
  end

  defp series, do: owned(:tv_series)

  defp movie_with_id(opts \\ []),
    do: owned(:movie, [tmdb_id: "1001", extras: [%{owner_type: :movie}]] ++ opts)

  def variations do
    [
      %Variation{
        id: :root_view,
        description:
          "A series on its episode list — the default opening. The control " <>
            "offers the other place worth going; the cog is unpressed. No TMDB " <>
            "identity here, so no bookmark.",
        attributes: %{detail: series(), view: :main}
      },
      %Variation{
        id: :cast_open,
        description:
          "Cast showing. The same slot now reads \"Episodes\" with a " <>
            "list glyph — the same one the episode-details toggle uses.",
        attributes: %{detail: series(), view: :cast}
      },
      %Variation{
        id: :manage_open,
        description:
          "Manage showing. \"Episodes\" is in the identical slot it occupies " <>
            "for Cast, and the cog brightens via `aria-pressed` rather " <>
            "than relabelling.",
        attributes: %{detail: series(), view: :info}
      },
      %Variation{
        id: :manage_open_on_a_movie,
        description:
          "Manage showing on a movie with no extras. Its root view *is* Cast, " <>
            "so that is where the control leads and what it is named for.",
        attributes: %{detail: owned(:movie), view: :info}
      },
      %Variation{
        id: :collection,
        description:
          "A collection (`:movie_series`) on its movie list has no " <>
            "collection-level cast, so there is no Cast view to offer — " <>
            "the row carries only the cog.",
        attributes: %{detail: owned(:movie_series), view: :main}
      },
      %Variation{
        id: :movie_with_extras,
        description:
          "A movie carrying entity-level extras has a body of its own, so " <>
            "Cast is a real second destination.",
        attributes: %{detail: owned(:movie, extras: [%{owner_type: :movie}]), view: :main}
      },
      %Variation{
        id: :movie_letterboxd_link,
        description:
          "A movie with a TMDB identity carries the Letterboxd icon button " <>
            "before the cog and the bookmark in its quiet off-list state " <>
            "between the two.",
        attributes: %{detail: movie_with_id(), view: :main}
      },
      %Variation{
        id: :movie_letterboxd_off,
        description:
          "The same movie with the `letterboxd_links` setting off — the " <>
            "Letterboxd button drops out; the bookmark stays.",
        attributes: %{detail: movie_with_id(), view: :main, letterboxd_links: false}
      },
      %Variation{
        id: :movie_on_watchlist,
        description:
          "The same movie on the list — the bookmark flips solid with a " <>
            "primary tint and `aria-pressed`, and offers removal.",
        attributes: %{detail: movie_with_id(rung: :list), view: :main}
      },
      %Variation{
        id: :movie_review,
        description:
          "The same movie with the Discovery preview on (`review?`) — the " <>
            "pencil joins the row between the bookmark and the cog.",
        attributes: %{detail: movie_with_id(), view: :main, review?: true}
      },
      %Variation{
        id: :movie_without_extras,
        description:
          "A movie with nothing of its own to list opens on Cast — that " <>
            "*is* its root view, so the slot is empty.",
        attributes: %{detail: owned(:movie), view: :cast}
      },
      %Variation{
        id: :unowned_movie,
        description:
          "A title the library does not own: no view to switch to and no " <>
            "files to manage — the Letterboxd link, the bookmark and Review.",
        attributes: %{detail: unowned_movie(), view: :main, review?: true}
      }
    ]
  end
end
