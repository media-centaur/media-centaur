defmodule MediaCentaur.ShowcaseTest do
  @moduledoc """
  Pins the showcase seeder's safety rail: it refuses to run against an
  instance that has not declared itself a disposable, seeded one.

  The declaration is `showcase_mode`, bootstrap state read from the override
  TOML that no Settings screen can set. It is what already gates the fixture
  stubs, the showcase supervisor, and the stubbed download/search clients — so
  the seeder asks the same question the rest of the app asks, rather than
  guessing from the shape of the database path.

  The seeder's output shape is demo tooling, exercised for real by
  `scripts/screenshot-tour` and `scripts/e2e-server` before every capture or
  E2E run, and is not tested here.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Showcase

  defp put_config(overrides) do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      Map.merge(config, overrides)
    )
  end

  test "raises against a real install's database" do
    put_config(%{
      database_path: "/home/user/.local/share/media-centaur/media-centaur.db",
      showcase_mode: false
    })

    assert_raise RuntimeError, ~r/refusing to seed/i, fn -> Showcase.seed!() end
  end

  test "raises when the instance has not declared showcase mode" do
    # A path that reads like a demo database is not a declaration. Only the
    # override TOML's showcase_mode is.
    put_config(%{
      database_path: "/home/user/showcase/media-centaur.db",
      showcase_mode: false
    })

    assert_raise RuntimeError, ~r/refusing to seed/i, fn -> Showcase.seed!() end
  end
end
