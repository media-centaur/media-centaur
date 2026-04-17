defmodule MediaCentarrWeb.Live.SettingsLive.SystemSectionTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Live.SettingsLive.SystemSection

  describe "built_label/1" do
    test "returns a formatted UTC date for a real build" do
      info = %{
        version: "0.4.0",
        built_at: ~U[2026-04-17 12:34:56Z],
        git_sha: "abc1234"
      }

      label = SystemSection.built_label({:ok, info})
      assert label =~ "2026-04-17"
      assert label =~ "abc1234"
    end

    test "returns 'dev build' for a dev environment" do
      assert SystemSection.built_label(:dev_build) == "dev build"
    end
  end

  describe "update_status_label/2" do
    test "idle shows a neutral prompt" do
      assert SystemSection.update_status_label(:idle, nil) =~ "Check for updates"
    end

    test "checking shows a progress message" do
      assert SystemSection.update_status_label(:checking, nil) =~ "Checking"
    end

    test "up_to_date shows an affirmative message" do
      assert SystemSection.update_status_label(:up_to_date, nil) =~ "latest"
    end

    test "update_available shows the new tag" do
      release = %{version: "0.5.0", tag: "v0.5.0", published_at: DateTime.utc_now(), html_url: "x"}
      assert SystemSection.update_status_label(:update_available, release) =~ "v0.5.0"
    end

    test "ahead_of_release acknowledges a newer local build" do
      release = %{version: "0.3.0", tag: "v0.3.0", published_at: DateTime.utc_now(), html_url: "x"}
      assert SystemSection.update_status_label(:ahead_of_release, release) =~ "ahead"
    end

    test "error produces a terse failure message" do
      assert SystemSection.update_status_label({:error, :not_found}, nil) =~ "error"
    end
  end

  describe "update_status_tone/1" do
    test "classifies statuses into tailwind tone keywords" do
      assert SystemSection.update_status_tone(:idle) == :neutral
      assert SystemSection.update_status_tone(:checking) == :neutral
      assert SystemSection.update_status_tone(:up_to_date) == :success
      assert SystemSection.update_status_tone(:update_available) == :info
      assert SystemSection.update_status_tone(:ahead_of_release) == :warning
      assert SystemSection.update_status_tone({:error, :any}) == :error
    end
  end
end
