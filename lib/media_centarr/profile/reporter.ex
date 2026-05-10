defmodule MediaCentarr.Profile.Reporter do
  @moduledoc """
  Writes a profile run to disk in both markdown (human) and JSON
  (machine) formats. Both formats render from the same
  `MediaCentarr.Profile.RunData` struct so they cannot drift —
  the JSON is the canonical machine-readable contract; the
  markdown is the rendered view.

  Produces:

    * `<runs_dir>/<run_id>.md`        — human-readable report
    * `<runs_dir>/<run_id>.json`      — canonical machine-readable
    * `<runs_dir>/latest.md`          — symlink to most recent .md
    * `<runs_dir>/latest.json`        — symlink to most recent .json

  Section ordering and field schema are stable contracts —
  changing them in a way that breaks downstream consumers requires
  bumping `RunData.schema_version/0`.
  """

  alias MediaCentarr.Profile.{JSONFormatter, MarkdownFormatter, RunData}

  @runs_dir "priv/profiling/runs"

  @doc """
  Writes a run report (markdown + JSON) and updates the `latest.*`
  symlinks. Returns `%{markdown: path, json: path}` with absolute
  paths.

  ## Options

    * `:runs_dir` — output directory. Defaults to
      `priv/profiling/runs`. Tests pass an absolute tmp dir so
      they don't write into the repo or rely on cwd (which would
      break async tests).
  """
  @spec write(%RunData{}, keyword()) :: %{markdown: Path.t(), json: Path.t()}
  def write(%RunData{} = run, opts \\ []) do
    runs_dir = Keyword.get(opts, :runs_dir, @runs_dir)
    File.mkdir_p!(runs_dir)

    md_path = Path.join(runs_dir, "#{run.metadata.run_id}.md")
    json_path = Path.join(runs_dir, "#{run.metadata.run_id}.json")

    File.write!(md_path, MarkdownFormatter.render(run))
    File.write!(json_path, JSONFormatter.encode(run))

    update_latest_symlink(md_path, runs_dir, "latest.md")
    update_latest_symlink(json_path, runs_dir, "latest.json")

    %{markdown: Path.expand(md_path), json: Path.expand(json_path)}
  end

  @doc """
  Resolves the path to the committed baseline JSON for a given
  scale, returning `{:ok, path}` if it exists or `:none` if not.
  """
  @spec baseline_json_path(atom() | String.t()) :: {:ok, Path.t()} | :none
  def baseline_json_path(scale) do
    path = Path.join("priv/profiling", "baseline-#{scale}.json")
    if File.exists?(path), do: {:ok, path}, else: :none
  end

  @doc """
  Loads a baseline JSON file and decodes it into a `%RunData{}`.
  Returns `{:error, reason}` on missing file, malformed JSON, or
  schema mismatch — the Mix task surfaces these as warnings, not
  hard failures, so a missing baseline doesn't break the run.
  """
  @spec load_baseline(Path.t()) :: {:ok, %RunData{}} | {:error, term()}
  def load_baseline(path) do
    with {:ok, json} <- File.read(path) do
      JSONFormatter.decode(json)
    end
  end

  @doc false
  def runs_dir, do: @runs_dir

  defp update_latest_symlink(path, runs_dir, link_name) do
    latest = Path.join(runs_dir, link_name)
    _ = File.rm(latest)
    target = Path.basename(path)
    File.ln_s(target, latest)
  end
end
