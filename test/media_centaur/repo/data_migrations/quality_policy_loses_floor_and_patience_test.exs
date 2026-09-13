defmodule MediaCentaur.Repo.DataMigrations.QualityPolicyLosesFloorAndPatienceTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.TitleDownloadParams
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.QualityPolicyLosesFloorAndPatience
  alias MediaCentaur.Settings

  @retired_keys ["auto_grab.default_min_quality", "auto_grab.4k_patience_hours"]

  # The embedded schema no longer admits the retired keys, so the legacy
  # state is written the way the old app left it: straight into the JSON.
  defp stamp_legacy_keys!(tmdb_id, media_type) do
    Repo.query!(
      "UPDATE title_download_params SET params = json_set(params, '$.max_quality', 'uhd_4k', '$.quality_4k_patience_hours', 24) WHERE tmdb_id = ? AND media_type = ?",
      [tmdb_id, Atom.to_string(media_type)]
    )

    :ok
  end

  defp raw_params(tmdb_id) do
    %{rows: [[json]]} =
      Repo.query!("SELECT params FROM title_download_params WHERE tmdb_id = ?", [tmdb_id])

    Jason.decode!(json)
  end

  describe "sweep/1" do
    test "deletes the two retired settings rows and keeps the rest" do
      for key <- @retired_keys ++ ["auto_grab.max_attempts"] do
        Settings.find_or_create_entry!(%{key: key, value: %{"value" => 12}})
      end

      assert :ok = QualityPolicyLosesFloorAndPatience.sweep(Repo)

      remaining = Settings.get_by_keys(@retired_keys ++ ["auto_grab.max_attempts"])
      assert Map.keys(remaining) == ["auto_grab.max_attempts"]
    end

    test "strips the retired per-title keys and drops a row left with nothing to say" do
      {:ok, _} = TitleDownloadParams.put(1, :movie, %{min_quality: "any"})
      stamp_legacy_keys!(1, :movie)

      {:ok, _} = TitleDownloadParams.put(2, :movie, %{min_quality: "any"})
      stamp_legacy_keys!(2, :movie)

      Repo.query!(
        "UPDATE title_download_params SET params = json_remove(params, '$.min_quality') WHERE tmdb_id = 2"
      )

      assert :ok = QualityPolicyLosesFloorAndPatience.sweep(Repo)

      assert raw_params(1) == %{"min_quality" => "any"}
      assert TitleDownloadParams.get(1, :movie).min_quality == "any"
      refute TitleDownloadParams.stored?(2, :movie)
    end

    test "is idempotent and a no-op on a clean database" do
      assert :ok = QualityPolicyLosesFloorAndPatience.sweep(Repo)
      assert :ok = QualityPolicyLosesFloorAndPatience.sweep(Repo)
      assert Settings.get_by_keys(@retired_keys) == %{}
    end
  end
end
