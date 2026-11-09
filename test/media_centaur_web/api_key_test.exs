defmodule MediaCentaurWeb.ApiKeyTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings
  alias MediaCentaurWeb.ApiKey

  test "with no key generated, nothing is valid" do
    refute ApiKey.exists?()
    refute ApiKey.valid?("anything")
  end

  test "a generated key is valid and another string is not" do
    key = ApiKey.generate()

    assert ApiKey.exists?()
    assert ApiKey.valid?(key)
    refute ApiKey.valid?(key <> "x")
  end

  test "generating again replaces the key" do
    old = ApiKey.generate()
    new = ApiKey.generate()

    refute ApiKey.valid?(old)
    assert ApiKey.valid?(new)
  end

  test "the key itself is never stored" do
    key = ApiKey.generate()

    refute Enum.any?(Settings.list_entries(), &(inspect(&1.value) =~ key))
  end
end
