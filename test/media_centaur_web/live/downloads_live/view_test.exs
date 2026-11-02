defmodule MediaCentaurWeb.DownloadsLive.ViewTest do
  @moduledoc """
  Pure unit tests for the Downloads page's one composition point. The
  builder takes already-read facts and returns the operational sections;
  the honest-degradation rule (no indexer ⇒ no operational sections) is
  enforced HERE, not scattered across templates.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaurWeb.DownloadsLive.View

  defp pursuit_row(overrides) do
    Map.merge(
      %PursuitRow{id: Ecto.UUID.generate(), title: "Sample Show", state: :active, status: "Grabbing"},
      overrides
    )
  end

  defp inputs(overrides) do
    Map.merge(%{pursuit_rows: [], drafts: [], prowlarr_ready?: true}, overrides)
  end

  describe "build/1 — operational sections" do
    test "in-flight rows and drafts pass through when an indexer is configured" do
      active = pursuit_row(%{})
      view = View.build(inputs(%{pursuit_rows: [active], drafts: [%{id: "draft-1"}]}))

      assert view.in_flight == [active]
      assert view.drafts == [%{id: "draft-1"}]
    end
  end

  describe "build/1 — honest degradation" do
    test "no indexer: the operational sections are empty, whatever the caller passes" do
      view =
        View.build(
          inputs(%{
            prowlarr_ready?: false,
            pursuit_rows: [pursuit_row(%{})],
            drafts: [%{id: "draft-1"}]
          })
        )

      assert view.in_flight == []
      assert view.drafts == []
    end
  end
end
