defmodule MediaCentaurWeb.Api.QueueController do
  @moduledoc "`/api/v1/queue`: reads the download clients' queue and removes items from it."

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Acquisition

  action_fallback MediaCentaurWeb.Api.FallbackController

  def index(conn, _params) do
    json(conn, %{items: Enum.map(Acquisition.queue_state().items, &item/1)})
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- Acquisition.cancel_download(id), do: send_resp(conn, :no_content, "")
  end

  defp item(item) do
    Map.take(item, [
      :id,
      :title,
      :state,
      :status,
      :protocol,
      :progress,
      :size,
      :size_left,
      :timeleft,
      :health,
      :failure_message
    ])
  end
end
