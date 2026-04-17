defmodule Mix.Tasks.Seed.Showcase do
  @shortdoc "Seed the showcase profile with public-domain media for demos"
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Populates the showcase profile's database with curated public-domain and
  Creative Commons media so the UI can be exercised and screenshotted without
  copyrighted material from your personal library.

  Refuses to run unless `MEDIA_CENTARR_PROFILE=showcase` is set — this is the
  single safety rail that keeps the seeder from clobbering your real DB.

      MEDIA_CENTARR_PROFILE=showcase mix ecto.create
      MEDIA_CENTARR_PROFILE=showcase mix ecto.migrate
      MEDIA_CENTARR_PROFILE=showcase mix seed.showcase

  See `MediaCentarr.Showcase` for what gets created.
  """
  use Mix.Task

  alias MediaCentarr.Showcase

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    case MediaCentarr.Config.profile() do
      "showcase" ->
        summary = Showcase.seed!()
        print_summary(summary)

      nil ->
        Mix.raise("""
        mix seed.showcase refuses to run against the default profile.

        Re-run with the showcase profile active:

            MEDIA_CENTARR_PROFILE=showcase mix seed.showcase

        This protects your real database from being seeded with demo data.
        """)

      other ->
        Mix.raise("""
        mix seed.showcase requires MEDIA_CENTARR_PROFILE=showcase, got #{inspect(other)}.

        If you meant to use the showcase profile:

            MEDIA_CENTARR_PROFILE=showcase mix seed.showcase
        """)
    end
  end

  defp print_summary(summary) do
    Mix.shell().info("""
    Seeded showcase profile:
      Movies:         #{summary.movies}
      TV series:      #{summary.tv_series}
      Seasons:        #{summary.seasons}
      Episodes:       #{summary.episodes}
      Video objects:  #{summary.video_objects}
      Watch progress: #{summary.watch_progress}
      Tracked items:  #{summary.tracked_items}
      Pending files:  #{summary.pending_files}
      Watch events:   #{summary.watch_events}
    """)
  end
end
