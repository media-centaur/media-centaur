defmodule MediaCentarr.Acquisition.Jobs.SearchAndGrabTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.{Grab, Jobs.SearchAndGrab, Prowlarr}
  alias MediaCentarr.Repo

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)
    on_exit(fn -> :persistent_term.erase({Prowlarr, :client}) end)
    :ok
  end

  defp job_for(grab) do
    %Oban.Job{args: %{"grab_id" => grab.id}}
  end

  describe "perform/1 — 4K result found" do
    test "grabs the result and marks grab as grabbed with 4K quality" do
      grab = create_grab()

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample Movie Thirteen.Part.Two.2024.2160p.UHD.BluRay.REMUX-FGT",
            "guid" => "uhd-guid",
            "indexerId" => 1,
            "seeders" => 10
          }
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
      assert updated.quality == "4K"
      assert updated.grabbed_at != nil
    end
  end

  describe "perform/1 — only 1080p found" do
    test "grabs the 1080p result and marks grab as grabbed" do
      grab = create_grab()

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample Movie Thirteen.Part.Two.2024.1080p.WEB-DL.H264-NTG",
            "guid" => "hd-guid",
            "indexerId" => 1,
            "seeders" => 25
          }
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
      assert updated.quality == "1080p"
    end
  end

  describe "perform/1 — 4K preferred over 1080p when both available" do
    test "grabs the 4K result, not the 1080p" do
      grab = create_grab()

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{"title" => "Sample Movie Thirteen.Part.Two.2024.1080p.WEB-DL", "guid" => "hd-guid", "indexerId" => 1},
          %{
            "title" => "Sample Movie Thirteen.Part.Two.2024.2160p.UHD.BluRay",
            "guid" => "uhd-guid",
            "indexerId" => 1
          }
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.quality == "4K"
    end
  end

  describe "perform/1 — nothing acceptable found" do
    test "increments attempt_count and returns snooze" do
      grab = create_grab()

      assert {:snooze, snooze_seconds} = SearchAndGrab.perform(job_for(grab))

      assert snooze_seconds == 4 * 60 * 60

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "searching"
      assert updated.attempt_count == 1
    end

    test "only 720p available — does not grab, increments attempt" do
      grab = create_grab()

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample Movie Thirteen.Part.Two.2024.720p.BluRay.x264",
            "guid" => "sd-guid",
            "indexerId" => 1
          }
        ])
      end)

      assert {:snooze, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.attempt_count == 1
    end
  end

  describe "perform/1 — already grabbed" do
    test "returns ok immediately without searching" do
      grab = create_grab()
      {:ok, grabbed} = Repo.update(Grab.grabbed_changeset(grab, "2160p"))

      assert {:ok, :already_grabbed} = SearchAndGrab.perform(job_for(grabbed))

      # attempt_count unchanged
      updated = Repo.get!(Grab, grab.id)
      assert updated.attempt_count == 0
    end
  end

  describe "perform/1 — grab record not found" do
    test "returns ok gracefully for unknown grab_id" do
      job = %Oban.Job{args: %{"grab_id" => Ecto.UUID.generate()}}
      assert {:ok, :not_found} = SearchAndGrab.perform(job)
    end
  end
end
