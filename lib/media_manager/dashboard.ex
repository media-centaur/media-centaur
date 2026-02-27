defmodule MediaManager.Dashboard do
  @moduledoc """
  Data-fetching module for the admin dashboard.
  Keeps the LiveView thin by centralizing all dashboard queries.
  """

  alias MediaManager.Library.{Entity, WatchedFile, Image}
  alias MediaManager.Library.Types.EntityType
  alias MediaManager.Review.PendingFile

  def fetch_stats do
    %{
      library: fetch_library_stats(),
      pending_review: fetch_pending_review(),
      recent_errors: fetch_recent_errors()
    }
  end

  def fetch_library_stats do
    entity_count = count(Entity)
    file_count = count(WatchedFile)
    image_count = count(Image)

    type_counts =
      for type <- EntityType.values(), into: %{} do
        query = Entity |> Ash.Query.do_filter(%{type: type})
        {type, count(query)}
      end

    %{
      entities: entity_count,
      files: file_count,
      images: image_count,
      by_type: type_counts
    }
  end

  def fetch_pending_review do
    Ash.read!(PendingFile, action: :pending)
    |> Enum.take(20)
  end

  def fetch_recent_errors do
    []
  end

  defp count(queryable) do
    case Ash.count(queryable) do
      {:ok, n} -> n
      _ -> 0
    end
  end
end
