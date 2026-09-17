defmodule MediaCentaurWeb.Components.Acquisition.NeedsAttentionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaurWeb.Components.Acquisition.NeedsAttention

  @unreachable {:fault, :download_client_unreachable, :warning, %{}}
  @auth_failed {:fault, :download_client_auth_failed, :error, %{}}
  @handoff_failed {:fault, :download_client_handoff_failed, :warning, %{}}

  describe "client_card/1 — the download-client conditions the glyph can name" do
    test "healthy → no card" do
      assert NeedsAttention.client_card(:ok) == nil
    end

    test "the app cannot reach the client → warning, the one fix is to check it is running" do
      card = NeedsAttention.client_card(@unreachable)

      assert card.severity == :warning
      assert card.title == "Can't reach the download client"
      assert card.detail =~ "Check that it's running"
    end

    test "the client rejected the credentials → error, points at Settings → Acquisition" do
      card = NeedsAttention.client_card(@auth_failed)

      assert card.severity == :error
      assert card.title == "Download client rejected the credentials"
      assert card.detail =~ "Settings → Acquisition"
    end

    test "Prowlarr cannot hand releases over → warning, points at Prowlarr's own client entry" do
      card = NeedsAttention.client_card(@handoff_failed)

      assert card.severity == :warning
      assert card.title == "Prowlarr can't hand releases to the download client"
      assert card.detail =~ "retried every 15 minutes"
      assert card.detail =~ "Settings → Download Clients"
    end
  end

  describe "visible?/3" do
    test "a client fault alone shows the glyph" do
      healthy_search = %IndexerHealth{state: :ok, checked_at: DateTime.utc_now(:second)}

      assert NeedsAttention.visible?(:calm, healthy_search, @handoff_failed)
      refute NeedsAttention.visible?(:calm, healthy_search, :ok)
    end
  end
end
