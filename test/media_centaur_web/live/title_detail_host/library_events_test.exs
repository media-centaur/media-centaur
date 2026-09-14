defmodule MediaCentaurWeb.Live.TitleDetailHost.LibraryEventsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.Detail.Library
  alias MediaCentaurWeb.Components.Title.ModalState
  alias MediaCentaurWeb.Live.TitleDetailHost.LibraryEvents
  alias MediaCentaurWeb.ViewModel.LeafDetail

  describe "refresh_artwork_flash/1" do
    test "ok → info" do
      assert {:info, message} = LibraryEvents.refresh_artwork_flash({:ok, %Oban.Job{}})
      assert message =~ "Refreshing artwork"
    end

    test "no tmdb id → error pointing at Rematch" do
      assert {:error, message} = LibraryEvents.refresh_artwork_flash({:error, :no_tmdb_id})
      assert message =~ "Rematch"
    end

    test "other error → generic error" do
      assert {:error, _message} = LibraryEvents.refresh_artwork_flash({:error, :boom})
    end
  end

  describe "apply_delete_result/3" do
    test "a result for a subject the person moved on from is dropped" do
      entity = %{id: "b", type: :movie, name: "Other Movie"}

      detail = %TitleDetail{
        ref: nil,
        title: nil,
        library: %Library{
          entry: %LeafDetail{entity: entity, progress: nil, progress_records: [], resume_target: nil},
          subject: entity
        }
      }

      state = %{ModalState.new() | deleting: :all}

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, title_detail: detail, modal_state: state}
      }

      assert LibraryEvents.apply_delete_result(socket, {:entity, "a"}, {:ok, []}) == socket
      assert LibraryEvents.apply_delete_result(socket, {:title, {777, :movie}}, {:ok, []}) == socket
    end
  end
end
