defmodule MediaCentaur.Acquisition.Jobs.PlanTitle do
  @moduledoc """
  Plans a TMDB title for the auto-select Download door
  (`Plans.plan_title/2`): the click inserts this job, and the job runs the
  targeting fetch and creates the plan (`Plans.create_title_plan/2`), whose
  own solve follows in `RunPlan`. The click used to do this on a
  fire-and-forget task, which a crash or restart lost (campaign
  durable-work, F3d).

  Args carry the title snapshot `create_title_plan/2` reads — `tmdb_id`,
  `media_type`, `name`, `year` — and the door's `approval_policy` and
  `scope`. A TMDB failure returns an error, so Oban asks again; nothing to
  plan (no aired episode in scope) is logged and ends the job.
  """

  # One owed plan per title among jobs not yet started (ADR-077, rule 6):
  # a double click collapses; a later click plans again.
  use Oban.Worker,
    queue: :acquisition,
    unique: [
      period: :infinity,
      keys: [:tmdb_id, :media_type],
      states: [:available, :scheduled, :retryable]
    ]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.TMDB.Title

  @doc "The job for `title` with `Plans.create_title_plan/2`'s options."
  @spec for_title(Title.t(), keyword()) :: Oban.Job.changeset()
  def for_title(%Title{} = title, opts) do
    new(%{
      "tmdb_id" => title.tmdb_id,
      "media_type" => Atom.to_string(title.media_type),
      "name" => title.name,
      "year" => title.year,
      "approval_policy" => Keyword.get(opts, :approval_policy, "review"),
      "scope" => opts |> Keyword.get(:scope, :first_season) |> Atom.to_string()
    })
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    title =
      Title.new!(%{
        tmdb_id: args["tmdb_id"],
        media_type: media_type(args["media_type"]),
        name: args["name"],
        year: args["year"]
      })

    case Plans.create_title_plan(title,
           approval_policy: args["approval_policy"],
           scope: scope(args["scope"])
         ) do
      {:ok, _plan} ->
        :ok

      {:error, :nothing_to_plan} ->
        Log.warning(:acquisition, "nothing to plan — #{title.name} tmdb:#{title.tmdb_id}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp media_type("movie"), do: :movie
  defp media_type("tv_series"), do: :tv_series

  defp scope("first_season"), do: :first_season
  defp scope("everything"), do: :everything
end
