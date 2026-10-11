defmodule MediaCentaur.HueTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Hue

  test "a hue is an integer angle 0–359" do
    assert Hue.valid?(0)
    assert Hue.valid?(359)
    refute Hue.valid?(360)
    refute Hue.valid?(-1)
    refute Hue.valid?(250.0)
    refute Hue.valid?("250")
    refute Hue.valid?(nil)
  end

  test "the palette is eight named hues, Blue 250 among them; random picks one" do
    palette = Hue.palette()
    assert length(palette) == 8
    assert {"Blue", 250} in palette
    assert Enum.all?(palette, fn {name, hue} -> is_binary(name) and Hue.valid?(hue) end)
    assert Hue.random() in Enum.map(palette, &elem(&1, 1))
  end

  test "first_unused/1 is the first palette hue, in swatch order, that no one holds" do
    assert Hue.first_unused([]) == 12
    assert Hue.first_unused([250]) == 12
    assert Hue.first_unused([12, 45, 250]) == 80
    # An angle off the palette holds no swatch.
    assert Hue.first_unused([13]) == 12
    assert Hue.first_unused(Enum.map(Hue.palette(), &elem(&1, 1))) == nil
  end

  test "parse/1 reads a form value: an angle, empty for none, anything else refused" do
    assert Hue.parse("195") == {:ok, 195}
    assert Hue.parse("") == {:ok, nil}
    assert Hue.parse(nil) == {:ok, nil}
    assert Hue.parse("360") == :error
    assert Hue.parse("12.5") == :error
    assert Hue.parse("teal") == :error
  end
end
