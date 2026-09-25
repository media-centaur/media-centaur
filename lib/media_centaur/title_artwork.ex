defmodule MediaCentaur.TitleArtwork do
  @moduledoc """
  The artwork ladder for a title named by TMDB identity, per role — the
  one rule behind every `src` a surface paints for such a title, best
  tier first:

    1. the **library** tier — the owning entity's own image, when this
       install owns the identity. The caller reads it and passes it in,
       because only the caller knows how it read the library: one
       loaded entity (the title detail), or a batch over many refs
       (`Library.Artwork.urls_by_refs/2` for the Feed and the release
       rows). It is the same artwork every other surface paints for
       that title.
    2. the **referenced** tier — `TmdbArtwork`'s cache, for an identity
       nothing in the library owns.
    3. the TMDB **hotlink** — when the title snapshot carries a path:
       the poster at the width the surface paints (`poster_width`, one
       of TMDB's size classes, the way `sized_image_url/2` makes local
       artwork width-declared), the backdrop at `:w1280`. A logo has no
       hotlink; the snapshot carries no logo path.

  Each role falls independently: an owned entity without a backdrop
  takes its backdrop from the next tier. Nothing on any tier is `nil`
  for that role — an activity snapshot carries no paths at all
  (`Activities.Publisher` leaves artwork to the reading install), so
  its hotlink rung is empty in practice and the referenced tier is what
  a host warms.
  """

  use Boundary, deps: [MediaCentaur.TMDB, MediaCentaur.TmdbArtwork]

  alias MediaCentaur.TMDB.Mapper
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbArtwork

  @typedoc ~s{This title's library-tier URL by role (`"poster"`, `"backdrop"`, `"logo"`); absent or nil when the library has none.}
  @type library :: %{optional(String.t()) => String.t() | nil}

  @type urls :: %{
          poster_url: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil
        }

  @spec urls(Title.t(), library(), atom()) :: urls()
  def urls(%Title{} = title, library, poster_width) do
    referenced = TmdbArtwork.urls(title.media_type, title.tmdb_id)

    %{
      poster_url:
        library["poster"] || referenced.poster_url || Mapper.image_url(title.poster_path, poster_width),
      backdrop_url:
        library["backdrop"] || referenced.backdrop_url || Mapper.image_url(title.backdrop_path, :w1280),
      logo_url: library["logo"] || referenced.logo_url
    }
  end
end
