defmodule MediaCentarr.Showcase.Catalog do
  @moduledoc """
  Curated catalog of public-domain and Creative Commons media used by the
  showcase profile. Titles are chosen to be legally safe for marketing
  screenshots and to span a wide range of eras, genres, and library shapes
  (standalone films, TV series with seasons, short-form video objects).

  Each movie/tv entry is looked up on TMDB by title+year at seed time —
  TMDB IDs are not hard-coded so the catalog is resilient to TMDB data
  shuffling. Video objects are seeded without TMDB.
  """

  @type movie_entry :: %{
          title: String.t(),
          year: integer() | nil,
          content_url: String.t() | nil
        }

  @type tv_entry :: %{
          title: String.t(),
          year: integer() | nil,
          seasons: [integer()]
        }

  @type video_entry :: %{
          title: String.t(),
          year: integer() | nil,
          description: String.t() | nil,
          content_url: String.t() | nil,
          url: String.t() | nil
        }

  @spec movies() :: [movie_entry()]
  def movies do
    [
      # Blender Open Movies — all CC-0 / open-source, modern aesthetic.
      %{title: "Big Buck Bunny", year: 2008, content_url: "/showcase/movies/Big Buck Bunny (2008).mkv"},
      %{title: "Sintel", year: 2010, content_url: "/showcase/movies/Sintel (2010).mkv"},
      %{title: "Tears of Steel", year: 2012, content_url: "/showcase/movies/Tears of Steel (2012).mkv"},
      %{
        title: "Cosmos Laundromat",
        year: 2015,
        content_url: "/showcase/movies/Cosmos Laundromat (2015).mkv"
      },
      %{title: "Spring", year: 2019, content_url: "/showcase/movies/Spring (2019).mkv"},

      # Classic silent-era public domain.
      %{title: "Metropolis", year: 1927, content_url: "/showcase/movies/Metropolis (1927).mkv"},
      %{title: "Nosferatu", year: 1922, content_url: "/showcase/movies/Nosferatu (1922).mkv"},
      %{
        title: "The Cabinet of Dr. Caligari",
        year: 1920,
        content_url: "/showcase/movies/The Cabinet of Dr. Caligari (1920).mkv"
      },
      %{
        title: "The Phantom of the Opera",
        year: 1925,
        content_url: "/showcase/movies/The Phantom of the Opera (1925).mkv"
      },

      # Classic public domain horror / sci-fi.
      %{
        title: "Night of the Living Dead",
        year: 1968,
        content_url: "/showcase/movies/Night of the Living Dead (1968).mkv"
      },
      %{
        title: "Plan 9 from Outer Space",
        year: 1959,
        content_url: "/showcase/movies/Plan 9 from Outer Space (1959).mkv"
      },
      %{
        title: "Carnival of Souls",
        year: 1962,
        content_url: "/showcase/movies/Carnival of Souls (1962).mkv"
      },
      %{
        title: "The Last Man on Earth",
        year: 1964,
        content_url: "/showcase/movies/The Last Man on Earth (1964).mkv"
      },

      # CC-licensed feature.
      %{
        title: "Sita Sings the Blues",
        year: 2008,
        content_url: "/showcase/movies/Sita Sings the Blues (2008).mkv"
      }
    ]
  end

  @spec tv_series() :: [tv_entry()]
  def tv_series do
    [
      # The Beverly Hillbillies Season 1 (1962) — all 36 S1 episodes lapsed
      # into US public domain when Orion Television (successor to Filmways)
      # neglected to renew the copyrights. TMDB has both series metadata
      # and episodic still_path coverage, so the TV detail modal renders
      # real stills instead of fallback placeholders. Theme song "Ballad
      # of Jed Clampett" is still under copyright — irrelevant since we
      # don't use audio.
      %{title: "The Beverly Hillbillies", year: 1962, seasons: [1]},

      # CC-BY-NC-SA modern web series. No TMDB stills — exercises the
      # bundled-fixture fallback (priv/showcase/fixtures/thumbs/).
      %{title: "Pioneer One", year: 2010, seasons: [1]}
    ]
  end

  @spec video_objects() :: [video_entry()]
  def video_objects do
    # Intentionally empty. VideoObjects (shorts without a TMDB identity)
    # cluttered the showcase library grid with low-metadata cards that
    # looked unfinished next to the TMDB-backed movies and series. The
    # catalog still supports the shape — re-populate this list to bring
    # shorts back.
    []
  end
end
