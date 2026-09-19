defmodule MediaCentaur.TimeSeries.ResolutionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TimeSeries.Resolution

  test "four resolutions in ascending width" do
    assert Resolution.all() == [:"10s", :"1m", :"10m", :"1h"]
    assert Enum.map(Resolution.all(), &Resolution.width/1) == [10, 60, 600, 3_600]
  end

  test "retention per resolution" do
    assert Resolution.retention(:"10s") == 3_600
    assert Resolution.retention(:"1m") == 6 * 3_600
    assert Resolution.retention(:"10m") == 2 * 86_400
    assert Resolution.retention(:"1h") == 31 * 86_400
  end

  test "bucket_start aligns down to the width" do
    assert Resolution.bucket_start(:"10s", 1_789_800_017) == 1_789_800_010
    assert Resolution.bucket_start(:"1m", 1_789_800_059) == 1_789_800_000
    assert Resolution.bucket_start(:"1h", 1_789_804_799) == 1_789_801_200
  end
end
