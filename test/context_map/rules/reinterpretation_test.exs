defmodule MediaCentaur.ContextMap.Rules.ReinterpretationTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Rules.Reinterpretation
  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Sources

  @intent %Schema{
    module: MediaCentaur.Discovery.TitleIntent,
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
    context: MediaCentaur.ReleaseTracking,
    table: "release_tracking_items",
    fields: [%{name: :media_type, type: "Ecto.Enum", values: [:movie, :tv_series]}],
    associations: []
  }
  @movie %Schema{
    module: MediaCentaur.Library.Movie,
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
end
