defmodule MediaCentaur.ContextMap.ContextsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Context
  alias MediaCentaur.ContextMap.Contexts

  test "lists Discovery with its deps and prefixed exports" do
    discovery = Enum.find(Contexts.all(), &(&1.name == MediaCentaur.Discovery))

    assert %Context{kernel?: false} = discovery
    assert MediaCentaur.Library in discovery.deps
    assert MediaCentaur.Discovery.TitleIntent in discovery.exports
  end

  test "Library and TMDB are the shared kernel" do
    kernel = for %Context{kernel?: true, name: name} <- Contexts.all(), do: name
    assert Enum.sort(kernel) == [MediaCentaur.Library, MediaCentaur.TMDB]
  end

  test "nested boundaries and tooling are not contexts" do
    names = Enum.map(Contexts.all(), & &1.name)
    refute MediaCentaur.Settings.Config in names
    refute MediaCentaur.Credo in names
    refute MediaCentaur.ContextMap in names
    refute MediaCentaurWeb in names
  end

  test "context_of folds nested modules into their context and the web layer into :web" do
    assert Contexts.context_of(MediaCentaur.Discovery.TitleIntent) == MediaCentaur.Discovery
    assert Contexts.context_of(MediaCentaur.Settings.Config) == MediaCentaur.Settings
    assert Contexts.context_of(MediaCentaurWeb.Components.Title.Logic) == :web
    assert Contexts.context_of(Mix.Tasks.ContextMap) == nil
  end
end
