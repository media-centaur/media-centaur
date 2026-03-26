defmodule MediaCentaur.Review.RematchTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Review.Rematch

  setup do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_commands())
    :ok
  end

  describe "rematch_entity/1" do
    test "broadcasts {:rematch_requested, entity_id} to library:commands" do
      entity_id = Ecto.UUID.generate()

      assert :ok = Rematch.rematch_entity(entity_id)

      assert_received {:rematch_requested, ^entity_id}
    end
  end
end
