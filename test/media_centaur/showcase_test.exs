defmodule MediaCentaur.ShowcaseTest do
  @moduledoc """
  Pins the showcase seeder's safety rail: it refuses to run against a
  database that does not look like a showcase database.

  The seeder's output shape is demo tooling, exercised for real by
  `scripts/screenshot-tour` before every capture, and is not tested here.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Showcase

  test "raises when database_path does not look like a showcase path" do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      Map.put(config, :database_path, "/home/user/.local/share/media-centaur/media-centaur.db")
    )

    assert_raise RuntimeError, ~r/refusing to seed/i, fn -> Showcase.seed!() end
  end
end
