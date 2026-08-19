defmodule MediaCentaur.Preferences.CardPlayButton do
  @moduledoc """
  Typed accessor for the `card_play_button` Settings entry.

  Controls whether browse cards (library grid, Recently Added, Continue
  Watching) reveal the hover play button (UIDR-027). Default-**on**; the
  entry is only written when the user opts out. Turning it off restores
  the modal as the only route to Play from a card — the hero's Play
  button is a standing control, not the hover overlay, and is unaffected.
  """

  use MediaCentaur.Preferences.BooleanSetting, key: "card_play_button", default: true
end
