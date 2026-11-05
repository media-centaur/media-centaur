defmodule Mix.Tasks.Seed.Showcase do
  @shortdoc "Seed the showcase database with public-domain media for demos"
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Populates the showcase database with curated public-domain and
  Creative Commons media so the UI can be exercised and screenshotted
  without copyrighted material from your personal library.

  Refuses to run unless `MEDIA_CENTAUR_CONFIG_OVERRIDE` is set. That env
  var points at a self-contained TOML (see
  `defaults/media-centaur-showcase.toml`) which carries its own
  `database_path` and `media_dirs` — so the seeder cannot land on the
  default dev/prod DB by accident.

      MEDIA_CENTAUR_CONFIG_OVERRIDE=defaults/media-centaur-showcase.toml mix ecto.create
      MEDIA_CENTAUR_CONFIG_OVERRIDE=defaults/media-centaur-showcase.toml mix ecto.migrate
      MEDIA_CENTAUR_CONFIG_OVERRIDE=defaults/media-centaur-showcase.toml mix seed.showcase

  See `MediaCentaur.Showcase` for what gets created.
  """
  use Mix.Task

  alias MediaCentaur.Showcase

  @impl true
  def run(args) do
    case System.get_env("MEDIA_CENTAUR_CONFIG_OVERRIDE") do
      override when is_binary(override) and override != "" ->
        if "--record-tmdb" in args, do: enable_tmdb_recording!()
        Mix.Task.run("app.start")
        summary = Showcase.seed!()
        print_summary(summary)

      _ ->
        Mix.raise("""
        mix seed.showcase refuses to run without MEDIA_CENTAUR_CONFIG_OVERRIDE.

        Run with the shipped showcase override:

            MEDIA_CENTAUR_CONFIG_OVERRIDE=defaults/media-centaur-showcase.toml mix seed.showcase

        This prevents seeding the default dev/prod DB by accident.
        """)
    end
  end

  # Recording reaches the live TMDB API for every request the committed
  # recording lacks (`Showcase.Stubs.TmdbFixtures`), so it needs a real key.
  defp enable_tmdb_recording! do
    if System.get_env("TMDB_API_KEY") in [nil, ""] do
      Mix.raise(
        "mix seed.showcase --record-tmdb needs TMDB_API_KEY: recording fetches from the live TMDB API."
      )
    end

    Application.put_env(:media_centaur, :showcase_tmdb_record, true)
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
      Review files:   #{summary.review_files}
      Watch events:   #{summary.watch_events}
      Acquisitions:   #{summary.acquisitions}
    """)
  end
end
