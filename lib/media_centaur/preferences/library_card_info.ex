defmodule MediaCentaur.Preferences.LibraryCardInfo do
  @moduledoc """
  Typed accessor for the `library_show_card_info` Settings entry.

  Controls whether the poster card footer (title + type/year) renders
  below each poster on the library page.

  Default-**on**, unlike the other boolean settings: the entry is only
  written when the user opts out, for the pure wall-of-posters view.
  """

  use MediaCentaur.Preferences.BooleanSetting, key: "library_show_card_info", default: true
end
