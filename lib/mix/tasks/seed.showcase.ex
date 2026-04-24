defmodule Mix.Tasks.Seed.Showcase do
  @shortdoc "Seed the showcase database with public-domain media for demos"
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Populates the showcase database with curated public-domain and
  Creative Commons media so the UI can be exercised and screenshotted
  without copyrighted material from your personal library.

  Refuses to run unless `MEDIA_CENTARR_CONFIG_OVERRIDE` is set. That env
  var points at a self-contained TOML (see
  `defaults/media-centarr-showcase.toml`) which carries its own
  `database_path` and `watch_dirs` — so the seeder cannot land on the
  default dev/prod DB by accident.

      MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.create
      MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.migrate
      MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix seed.showcase

  See `MediaCentarr.Showcase` for what gets created.
  """
  use Mix.Task

  alias MediaCentarr.Showcase

  @impl true
  def run(_args) do
    case System.get_env("MEDIA_CENTARR_CONFIG_OVERRIDE") do
      override when is_binary(override) and override != "" ->
        Mix.Task.run("app.start")
        summary = Showcase.seed!()
        print_summary(summary)

      _ ->
        Mix.raise("""
        mix seed.showcase refuses to run without MEDIA_CENTARR_CONFIG_OVERRIDE.

        Run with the shipped showcase override:

            MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix seed.showcase

        This prevents seeding the default dev/prod DB by accident.
        """)
    end
  end

  defp print_summary(summary) do
    Mix.shell().info("""
    Seeded showcase:
      Movies:         #{summary.movies}
      TV series:      #{summary.tv_series}
      Seasons:        #{summary.seasons}
      Episodes:       #{summary.episodes}
      Video objects:  #{summary.video_objects}
      Watch progress: #{summary.watch_progress}
      Tracked items:  #{summary.tracked_items}
      Pending files:  #{summary.pending_files}
      Watch events:   #{summary.watch_events}
      Acquisitions:   #{summary.acquisitions}
    """)
  end
end
