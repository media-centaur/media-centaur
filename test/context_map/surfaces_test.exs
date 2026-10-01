defmodule MediaCentaur.ContextMap.SurfacesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Sources
  alias MediaCentaur.ContextMap.Surfaces

  @files [
    {"lib/media_centaur_web/live/incoming_live.ex",
     "defmodule MediaCentaurWeb.IncomingLive do\n  use MediaCentaurWeb, :live_view\n  alias MediaCentaurWeb.Components.Acquisition.MediaResults\n  def r, do: MediaResults.list()\nend\n"},
    {"lib/media_centaur_web/components/acquisition/media_results.ex",
     "defmodule MediaCentaurWeb.Components.Acquisition.MediaResults do\n  alias MediaCentaurWeb.Components.Title.Logic\n  def list, do: Logic.marker(nil)\nend\n"},
    {"lib/media_centaur_web/components/title/logic.ex",
     "defmodule MediaCentaurWeb.Components.Title.Logic do\n  def marker(_), do: nil\nend\n"},
    {"lib/media_centaur_web/live/other_live.ex",
     "defmodule MediaCentaurWeb.OtherLive do\n  use MediaCentaurWeb, :live_view\nend\n"}
  ]

  test "a component's surfaces are the live views that reach it transitively" do
    sources = Enum.map(@files, fn {path, code} -> Sources.parse(path, code) end)
    surfaces = Surfaces.index(sources)

    assert surfaces[MediaCentaurWeb.Components.Title.Logic] == [MediaCentaurWeb.IncomingLive]

    assert surfaces[MediaCentaurWeb.Components.Acquisition.MediaResults] == [
             MediaCentaurWeb.IncomingLive
           ]

    assert surfaces[MediaCentaurWeb.IncomingLive] == [MediaCentaurWeb.IncomingLive]
    assert surfaces[MediaCentaurWeb.OtherLive] == [MediaCentaurWeb.OtherLive]
  end
end
