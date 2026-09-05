defmodule MediaCentaur.Profile do
  use Boundary,
    deps: [
      MediaCentaur.Library,
      MediaCentaur.ReleaseTracking,
      MediaCentaur.Settings,
      MediaCentaur.WatchHistory
    ],
    exports: [Suite]

  @moduledoc """
  Local performance profiling for Media Centaur (ADR-041).

  This context exists only to validate the in-memory projection
  perf claims (microsecond ETS reads vs millisecond DB queries) and
  catch regressions as we project more views. It is not run in
  production and not started by the application supervisor — every
  entry point is via `mix profile` (orchestrator: `Mix.Tasks.Profile`)
  or `scripts/profile`.

  ## Components

    * `MediaCentaur.Profile.Suite` — behaviour every benchmark suite
      implements. Suites live under `MediaCentaur.Profile.Suites.*`
      and are auto-discovered by `Profile.Bench` at runtime.
    * `MediaCentaur.Profile.Loader` — parameterised, deterministic
      fixture seeder. Reads only the public Library API; does not
      depend on `test/support/factory.ex`.
    * `MediaCentaur.Profile.Bench` — Benchee runner. Wraps each
      suite with the standard warmup/sample-count config so reports
      are comparable across runs.
    * `MediaCentaur.Profile.Mounts` — `Phoenix.LiveViewTest`-based
      page-mount harness. Times every top-level LiveView route.
    * `MediaCentaur.Profile.Reporter` — markdown writer. Produces
      `priv/profiling/runs/<ISO8601>.md` plus a `latest.md` symlink.

  ## Run metadata

  Every report header includes the metadata returned by `metadata/1`
  so two reports for the same scale on the same git sha are directly
  comparable, and an unexpected diff points at code or platform —
  not RNG drift.
  """

  @scales [:small, :medium, :large]

  @doc "Returns the list of valid scale identifiers."
  @spec scales() :: [atom()]
  def scales, do: @scales

  @doc "True when the argument is a recognised profiling scale."
  @spec valid_scale?(term()) :: boolean()
  def valid_scale?(scale), do: scale in @scales

  @doc """
  Builds the metadata block recorded in every report header. The
  shape is intentionally stable so `diff baseline.md latest.md`
  highlights real changes, not header noise.
  """
  @spec metadata(atom()) :: map()
  def metadata(scale) when scale in @scales do
    %{
      run_id: run_id(),
      timestamp: DateTime.utc_now(),
      scale: scale,
      git_sha: git_sha(),
      git_branch: git_branch(),
      dirty?: git_dirty?(),
      otp_release: System.otp_release(),
      elixir_version: System.version(),
      schedulers: System.schedulers_online(),
      cpu_count: System.schedulers(),
      database_path: database_path()
    }
  end

  defp run_id, do: DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")

  # Each git wrapper passes `env: []` so secrets in the parent process
  # (TMDB_API_KEY, etc.) cannot leak into the child via the inherited
  # env. Credo's `EnvVar.System.Cmd` check requires `env:` as a
  # literal keyword in the call AST — module attribute substitution
  # would evade detection — so the option is inlined per call.

  defp git_sha do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true, env: []) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  defp git_branch do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"], stderr_to_stdout: true, env: []) do
      {branch, 0} -> String.trim(branch)
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  defp git_dirty? do
    case System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true, env: []) do
      {output, 0} -> output |> String.trim() |> String.length() > 0
      _ -> false
    end
  rescue
    _ -> false
  end

  defp database_path do
    case MediaCentaur.Settings.Config.get(:database_path) do
      nil -> "unknown"
      path -> path
    end
  end
end
