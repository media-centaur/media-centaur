defmodule MediaCentaur.ApplicationTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ServiceFlags
  alias MediaCentaur.Settings.Services

  setup do
    ServiceFlags.enable_background_services()
  end

  # The child list is built while `Application.start/2` runs, before any
  # child — the Repo included — exists. A spec that reads a setting as it is
  # listed takes the whole application down at boot; v2.16.0 shipped that.
  test "listing the Oban child reads nothing from the database" do
    :telemetry_test.attach_event_handlers(self(), [[:media_centaur, :repo, :query]])

    assert %{id: Oban} = MediaCentaur.Application.oban_child_spec()

    refute_received {[:media_centaur, :repo, :query], _ref, _measurements, _metadata}
  end

  describe "oban_options/1" do
    test "the acquisition queue starts paused while auto-grab is off" do
      Services.set(:start_acquisition, false)
      assert Keyword.fetch!(acquisition_queue(), :paused)
    end

    test "the acquisition queue starts running while auto-grab is on" do
      Services.set(:start_acquisition, true)
      refute Keyword.fetch!(acquisition_queue(), :paused)
    end

    test "an instance without queues has nothing to pause" do
      assert MediaCentaur.Application.oban_options(queues: false) == [queues: false]
    end

    defp acquisition_queue do
      [queues: [acquisition: 3, maintenance: 1]]
      |> MediaCentaur.Application.oban_options()
      |> get_in([:queues, :acquisition])
    end
  end
end
