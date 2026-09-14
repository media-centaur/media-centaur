defmodule MediaCentaurWeb.Components.Title.ModalStateTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Title.ModalState

  describe "new/1 — the per-opening state, fresh for every subject" do
    test "opens on the requested view with nothing armed, expanded, typed or pending" do
      state = ModalState.new(:cast)

      assert state.view == :cast
      assert state.expanded_seasons == MapSet.new()
      assert state.expanded_item_details == MapSet.new()
      refute state.all_episode_details_open
      assert state.expanded_file_groups == nil
      assert state.cast_filter == ""
      assert state.cast_limit == nil
      assert state.delete_confirm == nil
      assert state.deleting == nil
      refute state.rematch_confirm
      assert state.open_menu == nil
      assert state.download_scope == :first_season
      assert state.pending == nil
    end

    test "defaults to the main view" do
      assert ModalState.new().view == :main
    end
  end

  describe "new/2 — a series opens with its oriented season expanded" do
    test "seeds the expanded seasons" do
      assert ModalState.new(:main, MapSet.new([3])).expanded_seasons == MapSet.new([3])
    end
  end
end
