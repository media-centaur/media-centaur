defmodule MediaCentarrWeb.Storybook.Detail.CastStrip do
  @moduledoc """
  Horizontal cast strip rendered at the bottom of the movie detail
  modal. Each card is a TMDB profile photo + actor name + character
  name; click opens TMDB's person page in a new tab.

  ## Variations

    * `:default` — eight cast members with photos. The most common
      shape — exercises horizontal overflow scrolling.
    * `:mixed` — three with photos, two without (silhouette
      fallback). Pins the no-photo branch.
    * `:empty` — empty cast list; the component renders nothing.

  Profile photos use placeholder paths that won't resolve on the TMDB
  CDN — that's accurate to the no-artwork-yet state and keeps the
  storybook honest about the silhouette fallback. Names use the
  `Sample Actor N` placeholder pattern per the no-real-titles policy.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.CastStrip.cast_strip/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-full max-w-3xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :default,
        description: "Eight cast members with profile photos.",
        attributes: %{cast: sample_cast_with_photos()}
      },
      %Variation{
        id: :mixed,
        description: "Some cast members lack profile photos — silhouette fallback.",
        attributes: %{cast: sample_cast_mixed()}
      },
      %Variation{
        id: :empty,
        description: "Empty cast — component renders nothing.",
        attributes: %{cast: []}
      }
    ]
  end

  defp sample_cast_with_photos do
    for n <- 0..7 do
      %{
        "name" => "Sample Actor #{n + 1}",
        "character" => "Sample Role #{n + 1}",
        "tmdb_person_id" => 1000 + n,
        "profile_path" => "/example#{n}.jpg",
        "order" => n
      }
    end
  end

  defp sample_cast_mixed do
    [
      %{
        "name" => "Sample Actor One",
        "character" => "Sample Role One",
        "tmdb_person_id" => 2001,
        "profile_path" => "/a.jpg",
        "order" => 0
      },
      %{
        "name" => "Sample Actor Two",
        "character" => "Sample Role Two",
        "tmdb_person_id" => 2002,
        "profile_path" => nil,
        "order" => 1
      },
      %{
        "name" => "Sample Actor Three",
        "character" => "Sample Role Three",
        "tmdb_person_id" => 2003,
        "profile_path" => "/c.jpg",
        "order" => 2
      },
      %{
        "name" => "Sample Actor Four",
        "character" => "Sample Role Four",
        "tmdb_person_id" => 2004,
        "profile_path" => nil,
        "order" => 3
      },
      %{
        "name" => "Sample Actor Five",
        "character" => "Sample Role Five",
        "tmdb_person_id" => 2005,
        "profile_path" => "/e.jpg",
        "order" => 4
      }
    ]
  end
end
