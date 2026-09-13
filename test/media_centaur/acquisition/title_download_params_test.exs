defmodule MediaCentaur.Acquisition.TitleDownloadParamsTest do
  @moduledoc """
  Per-title download params are Acquisition's, keyed by TMDB identity and
  independent of whether the title is tracked. That independence is the
  point: storing them on `ReleaseTracking.Item` is what forced "Accept
  lower quality" to start tracking a title nobody asked to track.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.DownloadParams
  alias MediaCentaur.Acquisition.TitleDownloadParams

  describe "get/2" do
    test "an untouched title has the default params, with no row written" do
      assert %DownloadParams{min_quality: nil} = TitleDownloadParams.get(1234, :tv_series)
      assert TitleDownloadParams.stored?(1234, :tv_series) == false
    end

    test "identity is the TMDB id and the media type together" do
      {:ok, _} = TitleDownloadParams.put(1234, :tv_series, %{min_quality: "any"})

      assert TitleDownloadParams.get(1234, :tv_series).min_quality == "any"
      assert TitleDownloadParams.get(1234, :movie).min_quality == nil
      assert TitleDownloadParams.get(9999, :tv_series).min_quality == nil
    end
  end

  describe "put/3" do
    test "writes params for a title that is not tracked" do
      {:ok, params} = TitleDownloadParams.put(1234, :movie, %{min_quality: "any"})

      assert params.min_quality == "any"
      assert TitleDownloadParams.get(1234, :movie).min_quality == "any"
    end

    test "an explicit nil clears the acceptance and removes the emptied row" do
      {:ok, _} = TitleDownloadParams.put(1234, :tv_series, %{min_quality: "any"})
      {:ok, _} = TitleDownloadParams.put(1234, :tv_series, %{min_quality: nil})

      assert TitleDownloadParams.get(1234, :tv_series).min_quality == nil
      assert TitleDownloadParams.stored?(1234, :tv_series) == false
    end

    test "rejects a quality outside the vocabulary" do
      assert {:error, changeset} = TitleDownloadParams.put(1234, :tv_series, %{min_quality: "8k"})
      assert %{min_quality: [_ | _]} = errors_on(changeset)
    end

    test "the embedded params carry only the acceptance" do
      assert DownloadParams.__schema__(:fields) == [:min_quality]
    end
  end

  describe "lower_quality_accepted?/1" do
    test "only a floor of \"any\" counts as the acceptance" do
      assert DownloadParams.lower_quality_accepted?(%DownloadParams{min_quality: "any"})
      refute DownloadParams.lower_quality_accepted?(%DownloadParams{min_quality: "hd_1080p"})
      refute DownloadParams.lower_quality_accepted?(%DownloadParams{min_quality: nil})
    end
  end
end
