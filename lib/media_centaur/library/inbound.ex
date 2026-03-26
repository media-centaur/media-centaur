defmodule MediaCentaur.Library.Inbound do
  @moduledoc """
  Subscribes to `"pipeline:publish"` and creates Library.Image records
  when images are successfully downloaded.

  On `{:image_ready, attrs}`:
  1. Creates a Library.Image with `content_url` already set
  2. Broadcasts `{:entities_changed, [entity_id]}` to `"library:updates"`

  Follows the same GenServer + PubSub subscriber pattern as
  `Library.FileEventHandler`.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Helpers

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_publish())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:image_ready, attrs}, state) do
    %{
      owner_id: owner_id,
      owner_type: owner_type,
      role: role,
      content_url: content_url,
      extension: extension,
      entity_id: entity_id
    } = attrs

    image_attrs =
      %{role: role, content_url: content_url, extension: extension}
      |> put_owner_fk(owner_type, owner_id)

    conflict_target = conflict_target_for(owner_type)

    case Library.upsert_image(image_attrs, conflict_target) do
      {:ok, _image} ->
        Log.info(:library, "image ready — #{role} for #{owner_id}")

      {:error, reason} ->
        Log.warning(
          :library,
          "failed to create image — #{role} for #{owner_id}: #{inspect(reason)}"
        )
    end

    Helpers.broadcast_entities_changed([entity_id])

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp put_owner_fk(attrs, "entity", owner_id), do: Map.put(attrs, :entity_id, owner_id)
  defp put_owner_fk(attrs, "movie", owner_id), do: Map.put(attrs, :movie_id, owner_id)
  defp put_owner_fk(attrs, "episode", owner_id), do: Map.put(attrs, :episode_id, owner_id)

  defp conflict_target_for("entity"), do: [:entity_id, :role]
  defp conflict_target_for("movie"), do: [:movie_id, :role]
  defp conflict_target_for("episode"), do: [:episode_id, :role]
end
