defmodule MediaCentaur.ContextMap.Rules.ReinterpretationTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Rules.Reinterpretation
  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Sources

  @intent %Schema{
    module: MediaCentaur.Discovery.TitleIntent,
    file: "lib/media_centaur/discovery/title_intent.ex",
    context: MediaCentaur.Discovery,
    table: "title_intents",
    fields: [
      %{name: :rung, type: "Ecto.Enum", values: [:ignored, :list, :follow, :grab]},
      %{name: :media_type, type: "Ecto.Enum", values: [:movie, :tv_series]}
    ],
    associations: []
  }
  @item %Schema{
    module: MediaCentaur.ReleaseTracking.Item,
    file: "lib/media_centaur/release_tracking/item.ex",
    context: MediaCentaur.ReleaseTracking,
    table: "release_tracking_items",
    fields: [%{name: :media_type, type: "Ecto.Enum", values: [:movie, :tv_series]}],
    associations: []
  }
  @movie %Schema{
    module: MediaCentaur.Library.Movie,
    file: "lib/media_centaur/library/movie.ex",
    context: MediaCentaur.Library,
    table: "movies",
    fields: [%{name: :kind, type: "Ecto.Enum", values: [:feature, :short]}],
    associations: []
  }
  @schemas [@intent, @item, @movie]

  defp run(path, code), do: Reinterpretation.findings(@schemas, [Sources.parse(path, code)])

  test "a value matched outside the owner, anchored by the field name on the line" do
    code =
      "defmodule MediaCentaurWeb.Components.Title.Logic do\n  defp rung_marker(:ignored), do: \"Ignored\"\nend\n"

    assert [
             %Finding{
               rule: "R3",
               owner: MediaCentaur.Discovery,
               schema: MediaCentaur.Discovery.TitleIntent,
               field: :rung,
               value: :ignored,
               consumer: MediaCentaurWeb.Components.Title.Logic,
               consumer_context: :web,
               anchored?: true,
               line: 2
             }
           ] = run("lib/media_centaur_web/components/title/logic.ex", code)
  end

  test "anchored by a reference to the owning schema module anywhere in the file" do
    code =
      "defmodule MediaCentaurWeb.Components.Title.TrackingControls do\n  @spec control_form(MediaCentaur.Discovery.TitleIntent.rung()) :: atom\n  def control_form(:ignored), do: :ignored\nend\n"

    assert [%Finding{anchored?: true, line: 3}] =
             run("lib/media_centaur_web/components/title/tracking_controls.ex", code)
  end

  test "unanchored value is reported only when exactly one field in the app declares it" do
    code =
      "defmodule MediaCentaur.Activities do\n  def ingest(_), do: :ignored\n  def kind, do: :movie\nend\n"

    findings = run("lib/media_centaur/activities.ex", code)
    assert [%Finding{value: :ignored, anchored?: false}] = findings
  end

  test "the owner interpreting its own value is not a finding" do
    code = "defmodule MediaCentaur.Discovery do\n  def f(%{rung: :ignored}), do: :ok\nend\n"
    assert [] = run("lib/media_centaur/discovery.ex", code)
  end

  test "a kernel-owned value is not a finding" do
    code = "defmodule MediaCentaur.Acquisition do\n  def f(%{kind: :feature}), do: :ok\nend\n"
    assert [] = run("lib/media_centaur/acquisition.ex", code)
  end

  test "a template mention is reported as unanchored unless the line names the field" do
    code =
      ~s|defmodule MediaCentaurWeb.Components.Title.TrackingControls do\n  def t(assigns) do\n    ~H"""\n    <p :if={@form == :ignored}>x</p>\n    """\n  end\nend\n|

    assert [%Finding{value: :ignored, anchored?: false}] =
             run("lib/media_centaur_web/components/title/tracking_controls.ex", code)
  end

  test "findings are sorted by verdict key, then line" do
    code =
      "defmodule MediaCentaurWeb.Sample do\n  def a(rung), do: rung == :list\n  def b(rung), do: rung == :ignored\nend\n"

    assert [%Finding{value: :ignored, line: 3}, %Finding{value: :list, line: 2}] =
             run("lib/media_centaur_web/sample.ex", code)
  end

  test "a value declared by schemas in two contexts is shared vocabulary, not reported even when anchored" do
    code =
      "defmodule MediaCentaur.Activities do\n  def kind(media_type), do: media_type == :movie\nend\n"

    assert [] = run("lib/media_centaur/activities.ex", code)
  end

  test "a value declared by two schemas of one context is still reported outside it" do
    plan = %Schema{
      module: MediaCentaur.Acquisition.Plans.Plan,
      context: MediaCentaur.Acquisition,
      file: "lib/media_centaur/acquisition/plans/plan.ex",
      table: "acquisition_plans",
      fields: [%{name: :state, type: "Ecto.Enum", values: [:sample_state]}],
      associations: []
    }

    unit = %{
      plan
      | module: MediaCentaur.Acquisition.Pursuits.Unit,
        file: "lib/media_centaur/acquisition/pursuits/unit.ex"
    }

    code = "defmodule MediaCentaurWeb.Sample do\n  def f(state), do: state == :sample_state\nend\n"

    findings =
      Reinterpretation.findings([plan, unit], [Sources.parse("lib/media_centaur_web/sample.ex", code)])

    assert [MediaCentaur.Acquisition.Plans.Plan, MediaCentaur.Acquisition.Pursuits.Unit] =
             findings |> Enum.map(& &1.schema) |> Enum.sort()
  end
end
