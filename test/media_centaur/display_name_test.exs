defmodule MediaCentaur.DisplayNameTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.DisplayName

  test "a name is trimmed, present and at most the cap" do
    assert DisplayName.check("  Sample Name ") == {:ok, "Sample Name"}
    assert DisplayName.check("   ") == {:error, :name_required}
    assert DisplayName.check("") == {:error, :name_required}
    assert DisplayName.check(String.duplicate("x", 50)) == {:ok, String.duplicate("x", 50)}
    assert DisplayName.check(String.duplicate("x", 51)) == {:error, :name_too_long}
  end

  test "the cap is the social wire's cap" do
    assert DisplayName.max_length() == 50
    assert MediaCentaur.Social.Profile.Translation.max_name_length() == DisplayName.max_length()
  end
end
