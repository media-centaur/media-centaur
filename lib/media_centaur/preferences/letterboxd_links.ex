defmodule MediaCentaur.Preferences.LetterboxdLinks do
  @moduledoc """
  Typed accessor for the `letterboxd_links` Settings entry.

  Controls whether the movie detail hero shows a link to the film's
  Letterboxd page (via the stable `letterboxd.com/tmdb/<id>` redirect,
  so no Letterboxd API or scraping is involved). Default-**on**; the
  entry is only written when the user opts out. Movies only —
  Letterboxd does not cover TV.
  """

  use MediaCentaur.Preferences.BooleanSetting, key: "letterboxd_links", default: true
end
