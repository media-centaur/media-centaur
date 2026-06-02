defmodule MediaCentaurWeb.StatusLive.ActivityWidgets do
  @moduledoc """
  Runtime registry mapping a subsystem `component` to its Activity-widget
  function component, for the health-board drill-in.

  Mirrors `MediaCentaur.ErrorReports.Contributors`: the mapping is config data
  (`config :media_centaur, :health_activity_widgets, %{component => {module,
  function}}`), resolved at runtime, so the board renders a subsystem's widget
  without a compile-time dependency on it. A component with no registered widget
  renders the health-only floor (no Activity section).

  The widget is a plain function component; `render/3` applies it to a data
  bundle that `StatusLive` assembles from its already-loaded assigns (no
  render-time queries). Registry injectable for tests.
  """
  @type component :: atom()
  @type registry :: %{optional(component()) => {module(), atom()}}

  @doc "The configured `component => {module, function}` registry (defaults to `%{}`)."
  @spec registry() :: registry()
  def registry, do: Application.get_env(:media_centaur, :health_activity_widgets, %{})

  @doc "The `{module, function}` registered for `component`, or `nil`."
  @spec widget_for(component(), registry()) :: {module(), atom()} | nil
  def widget_for(component, registry \\ registry()), do: Map.get(registry, component)

  @doc """
  Renders `component`'s registered widget with `assigns`, or `nil` when none is
  registered (the health-only floor).
  """
  @spec render(component(), map(), registry()) :: Phoenix.LiveView.Rendered.t() | nil
  def render(component, assigns, registry \\ registry()) do
    case widget_for(component, registry) do
      {module, function} -> apply(module, function, [assigns])
      nil -> nil
    end
  end
end
