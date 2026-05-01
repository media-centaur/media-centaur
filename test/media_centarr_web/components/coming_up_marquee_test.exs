defmodule MediaCentarrWeb.Components.ComingUpMarqueeTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Components.ComingUpMarquee.{Item, Marquee}

  test "Item struct enforces all keys" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{id: 1, name: "X"})
    end
  end

  test "Marquee struct enforces hero and secondaries keys" do
    assert_raise ArgumentError, fn ->
      struct!(Marquee, %{hero: nil})
    end
  end
end
