defmodule MediaCentaur.Settings.Preferences.PreferenceSetTest do
  @moduledoc """
  `set/1` is the one write a boolean preference exposes; the web layer
  must never spell the Settings row shape itself.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings.Preferences.{LetterboxdLinks, SpoilerFree}

  test "set/1 flips a default-on flag off and back" do
    assert LetterboxdLinks.enabled?()
    LetterboxdLinks.set(false)
    refute LetterboxdLinks.enabled?()
    LetterboxdLinks.set(true)
    assert LetterboxdLinks.enabled?()
  end

  test "set/1 flips a default-off flag on" do
    refute SpoilerFree.enabled?()
    SpoilerFree.set(true)
    assert SpoilerFree.enabled?()
  end
end
