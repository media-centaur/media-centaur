defmodule MediaCentaur.Repo.DataMigrations.ServiceFlagsLoseEnvironmentTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.ServiceFlagsLoseEnvironment
  alias MediaCentaur.Settings

  defp put_flag(key, enabled?) do
    {:ok, _} = Settings.find_or_create_entry(%{key: key, value: %{"enabled" => enabled?}})
  end

  defp flag(key) do
    case Settings.get_by_key(key) do
      %{value: %{"enabled" => enabled?}} -> enabled?
      _ -> nil
    end
  end

  describe "drop_environment/2" do
    test "the running environment's flags keep their values under the unscoped key" do
      put_flag("services:dev:start_pipeline", true)
      put_flag("services:dev:start_image_pipeline", false)

      assert :ok = ServiceFlagsLoseEnvironment.drop_environment(Repo, "dev")

      assert flag("services:start_pipeline") == true
      assert flag("services:start_image_pipeline") == false
      assert flag("services:dev:start_pipeline") == nil
      assert flag("services:dev:start_image_pipeline") == nil
    end

    test "another environment's flags are dropped, not carried over" do
      put_flag("services:prod:start_watchers", false)
      put_flag("services:dev:start_pipeline", true)

      assert :ok = ServiceFlagsLoseEnvironment.drop_environment(Repo, "dev")

      assert flag("services:start_watchers") == nil
      assert flag("services:prod:start_watchers") == nil
      assert flag("services:start_pipeline") == true
    end

    test "a second run changes nothing" do
      put_flag("services:prod:start_acquisition", false)

      assert :ok = ServiceFlagsLoseEnvironment.drop_environment(Repo, "prod")
      assert :ok = ServiceFlagsLoseEnvironment.drop_environment(Repo, "prod")

      assert flag("services:start_acquisition") == false
    end
  end
end
