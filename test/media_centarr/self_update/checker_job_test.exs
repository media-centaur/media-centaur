defmodule MediaCentarr.SelfUpdate.CheckerJobTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.SelfUpdate
  alias MediaCentarr.SelfUpdate.{CheckerJob, Storage, UpdateChecker}

  setup do
    Req.Test.stub(:github_releases_job, fn conn ->
      Plug.Conn.send_resp(conn, 404, "not found")
    end)

    Req.Test.set_req_test_from_context(%{async: false})

    client = Req.new(plug: {Req.Test, :github_releases_job}, retry: false)
    :persistent_term.put({UpdateChecker, :client}, client)

    UpdateChecker.clear_cache()

    # CheckerJob.perform/1 short-circuits when SelfUpdate.enabled?() is false.
    # Override to :prod so the job body runs; restore on exit.
    Application.put_env(:media_centarr, :environment, :prod)

    on_exit(fn ->
      Application.put_env(:media_centarr, :environment, :test)
      :persistent_term.erase({UpdateChecker, :client})
      UpdateChecker.clear_cache()
    end)

    :ok
  end

  describe "perform/1 happy path" do
    test "persists latest_known + last_check_at and broadcasts" do
      Req.Test.stub(:github_releases_job, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "v99.0.0",
            "published_at" => "2099-01-01T00:00:00Z",
            "html_url" => "https://github.com/media-centarr/media-centarr/releases/tag/v99.0.0",
            "body" => "Shiny new release"
          })
        )
      end)

      Req.Test.allow(:github_releases_job, self(), self())
      :ok = SelfUpdate.subscribe()

      assert {:ok, _} = perform_job(CheckerJob, %{})

      assert {:ok, %{release: release, classification: classification}} =
               Storage.get_latest_known()

      assert release.version == "99.0.0"
      assert release.body == "Shiny new release"
      assert classification in [:update_available, :up_to_date, :ahead_of_release]

      assert {:ok, %DateTime{}} = Storage.get_last_check_at()

      assert_receive {:check_complete, {^classification, %{version: "99.0.0"}}}
    end

    test "refreshes the :persistent_term cache" do
      Req.Test.stub(:github_releases_job, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "v99.0.0",
            "published_at" => "2099-01-01T00:00:00Z",
            "html_url" => "https://github.com/media-centarr/media-centarr/releases/tag/v99.0.0"
          })
        )
      end)

      Req.Test.allow(:github_releases_job, self(), self())
      assert {:ok, _} = perform_job(CheckerJob, %{})

      assert {:fresh, {:ok, %{version: "99.0.0"}}} = UpdateChecker.cached_latest_release()
    end
  end

  describe "perform/1 error paths" do
    test "does not write last_check_at when the check fails" do
      # Default stub returns 404, which UpdateChecker maps to :not_found.
      Req.Test.allow(:github_releases_job, self(), self())
      :ok = SelfUpdate.subscribe()

      assert {:ok, _} = perform_job(CheckerJob, %{})

      assert Storage.get_last_check_at() == :none
      assert_receive {:check_complete, {:error, :not_found}}
    end

    test "does not write latest_known when the API returns a bogus tag" do
      Req.Test.stub(:github_releases_job, fn conn ->
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

      Req.Test.allow(:github_releases_job, self(), self())
      assert {:ok, _} = perform_job(CheckerJob, %{})

      assert Storage.get_latest_known() == :none
    end
  end

  defp perform_job(worker, args) do
    case Oban.Testing.perform_job(worker, args, repo: MediaCentarr.Repo) do
      :ok -> {:ok, :ok}
      {:ok, value} -> {:ok, value}
      other -> other
    end
  end
end
