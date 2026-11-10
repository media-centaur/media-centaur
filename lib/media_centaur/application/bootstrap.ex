defmodule MediaCentaur.Application.Bootstrap do
  @moduledoc """
  The work that must finish before any subsystem starts, run as a child of
  the application supervisor in tree order: after the Repo and PubSub,
  before Oban and every subsystem. A child spec whose start applies the
  work and returns `:ignore`, so the tree's start order is the sequencing
  and nothing runs beside the boot.

    1. The media-dir migration from the TOML seed and the refresh from the
       Settings database (`Settings.Config`), then the runtime overrides —
       database settings overlaid onto the `:persistent_term` config and
       broadcast as `{:config_updated, _, _}`. A failure here is logged
       and the TOML seed stands; the instance still serves.
    2. `MediaCentaur.Jobs.rescue_orphans/1` with an instant taken here,
       before Oban starts: a job attempted before it was left executing by
       the last run (ADR-077, rule 8) and is available again the moment
       Oban comes up.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Settings.Config

  @doc false
  def child_spec(_opts), do: %{id: __MODULE__, start: {__MODULE__, :run, []}, restart: :temporary}

  @doc "Runs the bootstrap and returns `:ignore` — there is no process to supervise."
  @spec run() :: :ignore
  def run do
    booted_at = DateTime.utc_now()
    apply_config()
    MediaCentaur.Jobs.rescue_orphans(booted_at)
    :ignore
  end

  defp apply_config do
    toml_entries = Application.get_env(:media_centaur, :__raw_toml_media_dirs, [])
    :ok = Config.migrate_media_dirs_from_toml(toml_entries)
    :ok = Config.refresh_media_dirs_from_settings()
    :ok = Config.load_runtime_overrides()
    Log.info(:system, "media_dirs: #{length(Config.media_dirs_entries())} entries active")
  rescue
    error ->
      Log.error(:system, "config migration failed: #{Exception.format(:error, error, __STACKTRACE__)}")
  end
end
