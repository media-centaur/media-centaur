defmodule MediaCentaur.Credo.Checks.ApiOnlyConsumesTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.ApiOnlyConsumes

  defp check(source, filename) do
    source |> to_source_file(filename) |> run_check(ApiOnlyConsumes)
  end

  @outside "lib/media_centaur/acquisition.ex"
  @api "lib/media_centaur_web/controllers/api/status_controller.ex"

  describe "nothing references the API" do
    test "a module outside the API may not name one inside it" do
      source = """
      defmodule MediaCentaur.Acquisition do
        def status, do: MediaCentaurWeb.Api.StatusController.show(nil, nil)
      end
      """

      assert_issue(check(source, @outside))
    end

    test "nor through an alias group" do
      source = """
      defmodule MediaCentaurWeb.SettingsLive do
        alias MediaCentaurWeb.{Endpoint, Api.StatusController}
      end
      """

      assert_issue(check(source, "lib/media_centaur_web/live/settings_live.ex"))
    end

    test "the router mounts it" do
      source = """
      defmodule MediaCentaurWeb.Router do
        scope "/api", MediaCentaurWeb.Api do
          plug MediaCentaurWeb.Api.Admission
        end
      end
      """

      refute_issues(check(source, "lib/media_centaur_web/router.ex"))
    end

    test "a module whose name only starts the same way is not the API" do
      source = """
      defmodule MediaCentaurWeb.SettingsLive do
        alias MediaCentaurWeb.ApiKey
      end
      """

      refute_issues(check(source, "lib/media_centaur_web/live/settings_live.ex"))
    end

    test "a test may reference it" do
      source = """
      defmodule MediaCentaurWeb.SomeTest do
        alias MediaCentaurWeb.Api.Admission
      end
      """

      refute_issues(check(source, "test/media_centaur_web/some_test.exs"))
    end
  end

  describe "the API only consumes" do
    for {label, line} <- [
          {"the Repo", "alias MediaCentaur.Repo"},
          {"the Repo through a group", "alias MediaCentaur.{Library, Repo}"},
          {"Ecto", "import Ecto.Query"},
          {"PubSub", "Phoenix.PubSub.broadcast(MediaCentaur.PubSub, \"topic\", :message)"},
          {"Topics", "MediaCentaur.Topics.publish(:topic, :message)"},
          {"a job", "use Oban.Worker"},
          {"a process", "use GenServer"},
          {"a task", "Task.start(fn -> :ok end)"},
          {"ETS", ":ets.new(:table, [])"}
        ] do
      test "an API module may not use #{label}" do
        source = """
        defmodule MediaCentaurWeb.Api.StatusController do
          #{unquote(line)}
        end
        """

        assert_issue(check(source, @api))
      end
    end

    test "an API module may call context modules" do
      source = """
      defmodule MediaCentaurWeb.Api.StatusController do
        use MediaCentaurWeb, :controller
        alias MediaCentaur.Capabilities
        alias MediaCentaurWeb.ApiKey

        def show(conn, _params), do: json(conn, %{ready: Capabilities.tmdb_ready?(), key: ApiKey.exists?()})
      end
      """

      refute_issues(check(source, @api))
    end

    test "the rule is about API modules: another module may use the Repo" do
      source = """
      defmodule MediaCentaur.Library do
        alias MediaCentaur.Repo
      end
      """

      refute_issues(check(source, "lib/media_centaur/library.ex"))
    end
  end
end
