defmodule MediaCentaurWeb.DiscoveryLive.GradeTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.DiscoveryLive.Grade

  test "the grade rises with the people who did the act: one is plain, two silver, three or more gold" do
    assert Grade.grade(1) == :plain
    assert Grade.grade(2) == :silver
    assert Grade.grade(3) == :gold
    assert Grade.grade(12) == :gold
  end
end
