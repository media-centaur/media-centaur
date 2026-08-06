defmodule MediaCentaurWeb.StatusLive.ActivityWidgetsTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.StatusLive.ActivityWidgets

  def stub_widget(assigns), do: Phoenix.HTML.raw("<div>STUB-RENDERED #{assigns.label}</div>")

  @registry %{watcher: {__MODULE__, :stub_widget}}

  describe "widget_for/2" do
    test "resolves a registered component" do
      assert ActivityWidgets.widget_for(:watcher, @registry) == {__MODULE__, :stub_widget}
    end

    test "returns nil for an unregistered component" do
      assert ActivityWidgets.widget_for(:tmdb, @registry) == nil
    end
  end

  describe "render/3" do
    test "renders the registered widget with the given assigns" do
      out = ActivityWidgets.render(:watcher, %{label: "hi"}, @registry)
      assert Phoenix.HTML.safe_to_string(out) =~ "STUB-RENDERED"
      assert Phoenix.HTML.safe_to_string(out) =~ "hi"
    end

    test "returns nil for an unregistered component (the health-only floor)" do
      assert ActivityWidgets.render(:tmdb, %{}, @registry) == nil
    end
  end

  describe "registry/0" do
    test "reads the configured registry (watcher is registered in config.exs)" do
      assert {_mod, _fun} = ActivityWidgets.registry()[:watcher]
    end
  end
end
