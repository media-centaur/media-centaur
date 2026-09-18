defmodule MediaCentaurWeb.Components.StatusWidgets.HttpTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.StatusWidgets.Http

  @down ~U[2026-09-18 14:32:00Z]

  defp row(id), do: %{id: id, label: to_string(id), last_success_at: nil}

  describe "panel_rows/2" do
    test "an upstream whose integration is down carries when it went down" do
      rows = Http.panel_rows([row(:tmdb), row(:prowlarr)], %{tmdb: @down, prowlarr: nil})

      assert %{id: :tmdb, down_since: @down} = Enum.find(rows, &(&1.id == :tmdb))
      assert %{id: :prowlarr, down_since: nil} = Enum.find(rows, &(&1.id == :prowlarr))
    end

    test "an upstream with no availability value of its own is never down" do
      rows = Http.panel_rows([row(:tmdb_images), row(:github)], %{tmdb: @down})

      assert Enum.all?(rows, &(&1.down_since == nil))
    end

    test "rows outside the panel set are dropped, as before" do
      assert Http.panel_rows([row(:not_an_upstream)], %{}) == []
    end
  end
end
