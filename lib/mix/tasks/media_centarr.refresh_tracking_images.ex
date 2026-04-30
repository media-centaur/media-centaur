defmodule Mix.Tasks.MediaCentarr.RefreshTrackingImages do
  @shortdoc "Re-download undersized release-tracking backdrops/posters"
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Backfills release-tracking images that were fetched at the legacy
  `w300`/`w185` thumbnail sizes before the codebase switched to TMDB
  `original`. For each `release_tracking_items` row whose on-disk
  backdrop or poster is undersized, calls TMDB to retrieve the current
  `backdrop_path`/`poster_path` and re-downloads from `original`.

  Idempotent — re-runs are cheap because already-current files are
  skipped before any TMDB call is made.

      mix media_centarr.refresh_tracking_images
  """
  use Mix.Task

  import Ecto.Query

  alias MediaCentarr.Repo
  alias MediaCentarr.ReleaseTracking.{ImageStore, Item}
  alias MediaCentarr.TMDB.Client

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    items =
      Repo.all(
        from i in Item,
          select: %{
            tmdb_id: i.tmdb_id,
            media_type: i.media_type,
            name: i.name
          }
      )

    Mix.shell().info("Inspecting #{length(items)} tracked items...")

    counts = %{
      refreshed_backdrop: 0,
      refreshed_poster: 0,
      current: 0,
      tmdb_failed: 0,
      download_failed: 0
    }

    counts = Enum.reduce(items, counts, &process_item/2)

    Mix.shell().info("""

    Done.
      Backdrops refreshed: #{counts.refreshed_backdrop}
      Posters refreshed:   #{counts.refreshed_poster}
      Already current:     #{counts.current}
      TMDB lookup failed:  #{counts.tmdb_failed}
      Download failed:     #{counts.download_failed}
    """)
  end

  defp process_item(item, acc) do
    backdrop_stale = ImageStore.stale_image?(ImageStore.on_disk_path(:backdrop, item.tmdb_id))
    poster_stale = ImageStore.stale_image?(ImageStore.on_disk_path(:poster, item.tmdb_id))

    if not backdrop_stale and not poster_stale do
      Map.update!(acc, :current, &(&1 + 1))
    else
      case fetch_tmdb_image_paths(item) do
        {:ok, %{backdrop_path: bp, poster_path: pp}} ->
          backdrop_outcome =
            if backdrop_stale,
              do: ImageStore.refresh_if_stale(:backdrop, item.tmdb_id, bp),
              else: :current

          poster_outcome =
            if poster_stale,
              do: ImageStore.refresh_if_stale(:poster, item.tmdb_id, pp),
              else: :current

          Mix.shell().info(
            "  #{item.name} (tmdb_id=#{item.tmdb_id}): " <>
              "backdrop=#{backdrop_outcome}, poster=#{poster_outcome}"
          )

          acc
          |> bump(:refreshed_backdrop, backdrop_outcome == :refreshed)
          |> bump(:refreshed_poster, poster_outcome == :refreshed)
          |> bump(:download_failed, backdrop_outcome == :failed or poster_outcome == :failed)

        {:error, reason} ->
          Mix.shell().error(
            "  #{item.name} (tmdb_id=#{item.tmdb_id}): TMDB lookup failed (#{inspect(reason)})"
          )

          Map.update!(acc, :tmdb_failed, &(&1 + 1))
      end
    end
  end

  defp fetch_tmdb_image_paths(%{media_type: :tv_series, tmdb_id: tmdb_id}) do
    with {:ok, response} <- Client.get_tv(tmdb_id) do
      {:ok, %{backdrop_path: response["backdrop_path"], poster_path: response["poster_path"]}}
    end
  end

  defp fetch_tmdb_image_paths(%{media_type: :movie, tmdb_id: tmdb_id}) do
    # Mirror Refresher.fetch_for_item/1's fallback: try /collection/{id}
    # first (series-style trackers), then /movie/{id} (solo movies). The
    # schema enum can't tell the two apart.
    case Client.get_collection(tmdb_id) do
      {:ok, response} ->
        {:ok, %{backdrop_path: response["backdrop_path"], poster_path: response["poster_path"]}}

      {:error, {:http_error, 404, _}} ->
        with {:ok, response} <- Client.get_movie(tmdb_id) do
          {:ok, %{backdrop_path: response["backdrop_path"], poster_path: response["poster_path"]}}
        end

      error ->
        error
    end
  end

  defp bump(acc, _key, false), do: acc
  defp bump(acc, key, true), do: Map.update!(acc, key, &(&1 + 1))
end
