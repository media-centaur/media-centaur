defmodule MediaCentaurWeb.Live.EntityModalTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Live.EntityModal

  describe "detail files load status" do
    defp socket_with(assigns) do
      %Phoenix.LiveView.Socket{assigns: Map.put(assigns, :__changed__, %{})}
    end

    test "a result for the selected entity lands the files as loaded" do
      socket = socket_with(%{selected_entity_id: "a", detail_files: [], detail_files_status: :loading})

      socket = EntityModal.apply_detail_files(socket, "a", [%{file: :one}])

      assert socket.assigns.detail_files == [%{file: :one}]
      assert socket.assigns.detail_files_status == :loaded
    end

    test "a crashed load for the selected entity marks the files failed, never 'no files'" do
      socket = socket_with(%{selected_entity_id: "a", detail_files: [], detail_files_status: :loading})

      socket = EntityModal.apply_detail_files_failure(socket, "a", :boom)

      assert socket.assigns.detail_files == []
      assert socket.assigns.detail_files_status == :failed
    end

    test "a result or crash for a no-longer-selected entity is dropped" do
      socket = socket_with(%{selected_entity_id: "b", detail_files: [], detail_files_status: :loading})

      assert EntityModal.apply_detail_files(socket, "a", [%{}]).assigns.detail_files_status == :loading

      assert EntityModal.apply_detail_files_failure(socket, "a", :boom).assigns.detail_files_status ==
               :loading
    end
  end

  describe "refresh_artwork_flash/1" do
    test "ok → info" do
      assert {:info, message} = EntityModal.refresh_artwork_flash({:ok, %Oban.Job{}})
      assert message =~ "Refreshing artwork"
    end

    test "no tmdb id → error pointing at Rematch" do
      assert {:error, message} = EntityModal.refresh_artwork_flash({:error, :no_tmdb_id})
      assert message =~ "Rematch"
    end

    test "other error → generic error" do
      assert {:error, _message} = EntityModal.refresh_artwork_flash({:error, :boom})
    end
  end
end
