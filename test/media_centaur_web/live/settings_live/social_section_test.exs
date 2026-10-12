defmodule MediaCentaurWeb.SettingsLive.SocialSectionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.SettingsLive.SocialSection

  test "parse_follow/1 reads the control's value; anything else is added" do
    assert SocialSection.parse_follow("members") == :members
    assert SocialSection.parse_follow("added") == :added
    assert SocialSection.parse_follow(nil) == :added
    assert SocialSection.parse_follow("x") == :added
  end

  test "follow_options/0 lists added first, each under its label" do
    assert SocialSection.follow_options() == [
             {"added", "Only people I add"},
             {"members", "Everyone on this relay"}
           ]
  end
end
