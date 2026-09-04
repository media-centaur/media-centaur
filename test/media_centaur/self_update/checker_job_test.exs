defmodule MediaCentaur.SelfUpdate.CheckerJobTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.SelfUpdate
  alias MediaCentaur.SelfUpdate.{CheckerJob, Storage, UpdateChecker}

  setup do
    Req.Test.stub(:github, fn conn ->
      Plug.Conn.send_resp(conn, 404, "not found")
    end)

    Req.Test.set_req_test_from_context(%{async: false})

    UpdateChecker.clear_cache()

    # CheckerJob.perform/1 short-circuits when SelfUpdate.enabled?() is false.
    # Override to :prod so the job body runs; restore on exit.
    Application.put_env(:media_centaur, :environment, :prod)

    on_exit(fn ->
      Application.put_env(:media_centaur, :environment, :test)
      UpdateChecker.clear_cache()
    end)

    :ok
  end

  describe "perform/1 happy path" do
    test "persists latest_known + last_check_at and broadcasts" do
      Req.Test.stub(:github, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "v99.0.0",
            "published_at" => "2099-01-01T00:00:00Z",
            "html_url" => "https://github.com/media-centaur/media-centaur/releases/tag/v99.0.0",
            "body" => "Shiny new release"
          })
        )
      end)

      Req.Test.allow(:github, self(), self())
      :ok = SelfUpdate.subscribe()

      assert {:ok, _} = perform_job(CheckerJob, %{})

      assert {:ok, %{release: release, classification: classification}} =
               Storage.get_latest_known()

      assert release.version == "99.0.0"
      assert release.body == "Shiny new release"
      assert classification in [:update_available, :up_to_date, :ahead_of_release]

      assert {:ok, %DateTime{}} = Storage.get_last_check_at()

      assert_receive {:check_complete, {^classification, %{version: "99.0.0"}}, :scheduled}
    end

    test "refreshes the :persistent_term cache" do
      Req.Test.stub(:github, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "v99.0.0",
            "published_at" => "2099-01-01T00:00:00Z",
            "html_url" => "https://github.com/media-centaur/media-centaur/releases/tag/v99.0.0"
          })
        )
      end)

      Req.Test.allow(:github, self(), self())
      assert {:ok, _} = perform_job(CheckerJob, %{})

      assert {:fresh, {:ok, %{version: "99.0.0"}}} = UpdateChecker.cached_latest_release()
    end
  end

  describe "perform/1 error paths" do
    test "does not write last_check_at when the check fails" do
      # Default stub returns 404, which UpdateChecker maps to :not_found.
      Req.Test.allow(:github, self(), self())
      :ok = SelfUpdate.subscribe()

      assert {:ok, _} = perform_job(CheckerJob, %{})

      assert Storage.get_last_check_at() == :none
      assert_receive {:check_complete, {:error, :not_found}, :scheduled}
    end

    test "does not write latest_known when the API returns a bogus tag" do
      Req.Test.stub(:github, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "v1.0; rm -rf",
            "published_at" => "2099-01-01T00:00:00Z"
          })
        )
      end)

      Req.Test.allow(:github, self(), self())
      assert {:ok, _} = perform_job(CheckerJob, %{})

      assert Storage.get_latest_known() == :none
    end
  end

  describe "due_for_check?/5" do
    setup do
      now = ~U[2026-06-07 12:00:00Z]
      %{now: now}
    end

    test "force always wins, even when checking is disabled", %{now: now} do
      assert CheckerJob.due_for_check?(true, false, 360, now, now)
    end

    test "disabled and not forced never checks", %{now: now} do
      last = DateTime.add(now, -100, :hour)
      refute CheckerJob.due_for_check?(false, false, 360, last, now)
    end

    test "enabled with no prior check is due", %{now: now} do
      assert CheckerJob.due_for_check?(false, true, 360, nil, now)
    end

    test "enabled and interval elapsed is due", %{now: now} do
      last = DateTime.add(now, -361, :minute)
      assert CheckerJob.due_for_check?(false, true, 360, last, now)
    end

    test "enabled but checked too recently is not due", %{now: now} do
      last = DateTime.add(now, -10, :minute)
      refute CheckerJob.due_for_check?(false, true, 360, last, now)
    end
  end

  describe "perform/1 gating" do
    test "a scheduled tick does not check when checking is disabled" do
      set_config(:update_check_enabled, false)
      Req.Test.allow(:github, self(), self())

      assert {:ok, _} = perform_job(CheckerJob, %{})

      assert Storage.get_last_check_at() == :none
    end

    test "a forced check runs even when checking is disabled" do
      set_config(:update_check_enabled, false)

      Req.Test.stub(:github, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{"tag_name" => "v99.0.0", "published_at" => "2099-01-01T00:00:00Z"})
        )
      end)

      Req.Test.allow(:github, self(), self())

      assert {:ok, _} = perform_job(CheckerJob, %{"force" => true})
      assert {:ok, %DateTime{}} = Storage.get_last_check_at()
    end

    test "a scheduled tick skips when the last check is more recent than the interval" do
      Storage.put_last_check_at(DateTime.utc_now())
      set_config(:update_check_interval_minutes, 360)
      Req.Test.allow(:github, self(), self())

      assert {:ok, _} = perform_job(CheckerJob, %{})

      # last_check_at stays at the seeded value; no fresh write means the
      # stub (which would 404) was never hit.
      assert {:ok, %DateTime{}} = Storage.get_last_check_at()
    end
  end

  describe "enqueue_now/0" do
    test "marks the job forced so a manual check ignores the interval gate" do
      # A manual "Check for updates" must always contact GitHub *and* run
      # through the broadcasting job path (so AutoApply and any open LiveView
      # react uniformly). The interval gate would otherwise swallow a manual
      # check that lands inside the last scheduled check's window.
      Req.Test.allow(:github, self(), self())

      assert {:ok, %Oban.Job{} = job} = CheckerJob.enqueue_now()
      assert job.args == %{"force" => true}
    end
  end

  defp set_config(key, value) do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
    original = Map.get(config, key)
    :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, key, value))
    on_exit(fn -> set_config_raw(key, original) end)
  end

  defp set_config_raw(key, value) do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
    :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, key, value))
  end

  defp perform_job(worker, args) do
    case Oban.Testing.perform_job(worker, args, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite) do
      :ok -> {:ok, :ok}
      {:ok, value} -> {:ok, value}
      other -> other
    end
  end
end
