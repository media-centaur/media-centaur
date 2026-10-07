defmodule MediaCentaurWeb.Live.ProfileAware.LogicTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Profiles.Profile
  alias MediaCentaurWeb.Live.ProfileAware.Logic

  @me %Profile{id: "11111111-1111-4111-8111-111111111111", name: "Me"}
  @ana %Profile{id: "22222222-2222-4222-8222-222222222222", name: "Ana"}

  test "one profile is active whatever the cookie says" do
    assert Logic.resolve(nil, [@me]) == {:active, @me}
    assert Logic.resolve("stale", [@me]) == {:active, @me}
  end

  test "with more than one, the cookie names the active profile; none or a stale one asks" do
    assert Logic.resolve(@ana.id, [@me, @ana]) == {:active, @ana}
    assert Logic.resolve(nil, [@me, @ana]) == :pick
    assert Logic.resolve("gone", [@me, @ana]) == :pick
  end

  test "no profiles at all asks" do
    assert Logic.resolve(nil, []) == :pick
  end
end
