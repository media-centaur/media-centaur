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
      assert state.deleting == nil
      assert state.open_menu == nil
      assert state.download_scope == :first_missing_season
      refute state.grab_rest
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

  describe "the scope select's value" do
    test "offers the download scopes and the person's own choice, in menu order" do
      assert ModalState.scope_choices() ==
               [:first_missing_season, :everything, :latest_season, :choose_episodes]
    end

    test "parses its wire form as a closed set" do
      assert ModalState.parse_scope_choice("first_missing_season") == {:ok, :first_missing_season}
      assert ModalState.parse_scope_choice("latest_season") == {:ok, :latest_season}
      assert ModalState.parse_scope_choice("choose_episodes") == {:ok, :choose_episodes}
      assert ModalState.parse_scope_choice("first_season") == :error
      assert ModalState.parse_scope_choice(nil) == :error
    end
  end

  describe "choose_scope/2 — the choice carries the grab switch's default and closes the menu" do
    test "Latest season turns the switch on; every other choice turns it off" do
      opened = %{ModalState.new() | open_menu: :scope}

      latest = ModalState.choose_scope(opened, :latest_season)
      assert latest.download_scope == :latest_season
      assert latest.grab_rest
      assert latest.open_menu == nil

      refute ModalState.choose_scope(latest, :everything).grab_rest
      refute ModalState.choose_scope(latest, :first_missing_season).grab_rest
    end

    test "the person's flip of the switch holds until the next choice" do
      flipped = ModalState.toggle_grab_rest(ModalState.new())
      assert flipped.grab_rest
      refute ModalState.toggle_grab_rest(flipped).grab_rest
    end
  end
end
