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
      assert %DownloadParams{
               min_quality: nil,
               max_quality: nil,
               quality_4k_patience_hours: nil
             } = TitleDownloadParams.get(1234, :tv_series)

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

    test "merges into an existing row rather than replacing it" do
      {:ok, _} = TitleDownloadParams.put(1234, :tv_series, %{quality_4k_patience_hours: 24})
      {:ok, _} = TitleDownloadParams.put(1234, :tv_series, %{min_quality: "any"})

      params = TitleDownloadParams.get(1234, :tv_series)
      assert params.min_quality == "any"
      assert params.quality_4k_patience_hours == 24
    end

    test "an explicit nil clears one param and leaves the others" do
      {:ok, _} =
        TitleDownloadParams.put(1234, :tv_series, %{
          min_quality: "any",
          quality_4k_patience_hours: 24
        })

      {:ok, _} = TitleDownloadParams.put(1234, :tv_series, %{min_quality: nil})

      params = TitleDownloadParams.get(1234, :tv_series)
      assert params.min_quality == nil
      assert params.quality_4k_patience_hours == 24
    end

    test "rejects a quality outside the vocabulary" do
      assert {:error, changeset} = TitleDownloadParams.put(1234, :tv_series, %{min_quality: "8k"})
      assert %{min_quality: [_ | _]} = errors_on(changeset)
    end

    test "rejects a negative patience window" do
      assert {:error, changeset} =
               TitleDownloadParams.put(1234, :tv_series, %{quality_4k_patience_hours: -1})

      assert %{quality_4k_patience_hours: [_ | _]} = errors_on(changeset)
    end

    test "\"any\" is a floor value only, never a ceiling" do
      assert {:ok, _} = TitleDownloadParams.put(1234, :tv_series, %{min_quality: "any"})
      assert {:error, _} = TitleDownloadParams.put(1234, :tv_series, %{max_quality: "any"})
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
