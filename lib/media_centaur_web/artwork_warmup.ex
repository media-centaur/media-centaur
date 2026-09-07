defmodule MediaCentaurWeb.ArtworkWarmup do
  @moduledoc """
  First-screen artwork URLs for the root layout's `<link rel="prefetch">`
  hints (instant-navigation campaign Phase 4).

  UIDR-012 mandates `loading="eager" decoding="sync"` — a page paints only
  once its artwork is decoded — which makes the first visit to a
  poster-heavy page pay fetch + decode on the click path (~250–550ms
  measured on /library). These hints let the browser pull the artwork
  into its HTTP cache at launch, at its lowest priority, so every later
  first visit behaves like a warm one (~50–70ms).

  Two rules keep this honest:

    * **URLs must be byte-identical to what the pages request.** Any
      mismatch is a cache miss and the hint is dead weight. This is
      structural, not a promise: posters go through
      `LiveHelpers.poster_src/1` — the same function every 2:3 poster
      surface renders — and the hero backdrop through
      `Logic.select_hero/2`, the same pick Home makes, through
      `LiveHelpers.hero_backdrop_src/1` — the cache key the
      `HeroBackdrop` hook paints from. **Never re-derive a URL here.** A new warmed surface exposes the function it renders with
      and this module calls it.
    * **Reads are projection-only** (`Library.Views` ETS) — the root
      layout renders on the initial HTTP request, and this must add
      nothing to that path.

  ## Adding a surface

  What this module covers is a judgment call — "first screen" is not
  something a compiler can infer — so adding a page here is deliberate:

    1. Give the surface a public function returning the `src` it renders
       (`poster_src/1` is the worked example) and render through it.
    2. Call that function here.
    3. Assert the two agree in `artwork_warmup_test.exs`.

  MC0028 guarantees every artwork `<img>` declares a display width; it
  cannot know which surfaces are worth warming. That part is on you.
  """

  alias MediaCentaur.Library
  alias MediaCentaurWeb.HomeLive.Logic
  alias MediaCentaurWeb.LiveHelpers

  @poster_limit 30

  @doc """
  Deduplicated first-screen artwork URLs: `poster_urls/0` plus
  `hero_backdrop_url/0`.
  """
  @spec urls() :: [String.t()]
  def urls do
    (poster_urls() ++ [hero_backdrop_url()])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc """
  Up to #{@poster_limit} library grid poster derivatives, through
  `LiveHelpers.poster_src/1` — the function the grid renders with.
  """
  @spec poster_urls() :: [String.t()]
  def poster_urls do
    Library.Views.browse()
    |> Enum.map(& &1.poster_url)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@poster_limit)
    |> Enum.map(&LiveHelpers.poster_src/1)
  end

  @doc """
  The backdrop Home's hero is showing right now, through
  `LiveHelpers.hero_backdrop_src/1` — the cache key `Components.HeroBackdrop`
  hands its hook. The root layout marks the hint with `data-hero-backdrop`
  and `app.js` pre-decodes it at idle, so a byte of difference here means
  the hero decodes on its first visit after all.

  Only the current pick: the rotation means the eligible pool is far larger
  than what Home will request before the next block, so warming the whole
  pool would prefetch and decode dozens of images nobody looks at. Home is
  the only surface that renders a backdrop.
  """
  @spec hero_backdrop_url() :: String.t() | nil
  def hero_backdrop_url do
    case Logic.select_hero(Library.Views.hero_candidates()) do
      %{backdrop_url: url} -> LiveHelpers.hero_backdrop_src(url)
      _ -> nil
    end
  end
end
