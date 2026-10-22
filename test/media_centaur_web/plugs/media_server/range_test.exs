defmodule MediaCentaurWeb.Plugs.MediaServer.RangeTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Plugs.MediaServer.Range

  @size 1000

  test "no header is the whole file" do
    assert Range.parse(nil, @size) == :whole
  end

  test "a closed range, clamped to the file's end" do
    assert Range.parse("bytes=0-99", @size) == {:partial, 0, 100}
    assert Range.parse("bytes=500-1999", @size) == {:partial, 500, 500}
    assert Range.parse("bytes=999-999", @size) == {:partial, 999, 1}
  end

  test "an open-ended range runs to the end" do
    assert Range.parse("bytes=200-", @size) == {:partial, 200, 800}
    assert Range.parse("bytes=0-", @size) == {:partial, 0, 1000}
  end

  test "a suffix range is the last bytes" do
    assert Range.parse("bytes=-100", @size) == {:partial, 900, 100}
    assert Range.parse("bytes=-5000", @size) == {:partial, 0, 1000}
  end

  test "a start past the end, an inverted range, several ranges, another unit or garbage are unsatisfiable" do
    assert Range.parse("bytes=1000-", @size) == :unsatisfiable
    assert Range.parse("bytes=600-500", @size) == :unsatisfiable
    assert Range.parse("bytes=0-1,5-9", @size) == :unsatisfiable
    assert Range.parse("items=0-1", @size) == :unsatisfiable
    assert Range.parse("bytes=abc", @size) == :unsatisfiable
    assert Range.parse("bytes=-0", @size) == :unsatisfiable
  end

  test "any range of an empty file is unsatisfiable; no header still serves it whole" do
    assert Range.parse("bytes=0-", 0) == :unsatisfiable
    assert Range.parse(nil, 0) == :whole
  end
end
