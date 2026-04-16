defmodule MediaCentarr.Review.Rematch do
  @moduledoc """
  Requests a rematch for an entity — broadcasts to Library, which handles
  the teardown and sends files back to Review for re-matching.

  The rematch is async: this module broadcasts the request and returns
  immediately. Library.Inbound handles the entity destruction and
  Review.Intake receives the files for re-review.
  """

  alias MediaCentarr.Topics

  @spec rematch_entity(String.t()) :: :ok
  def rematch_entity(entity_id) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_commands(),
      {:rematch_requested, entity_id}
    )
  end
end
