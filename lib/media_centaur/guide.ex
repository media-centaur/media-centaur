defmodule MediaCentaur.Guide do
  @moduledoc """
  Public context for the in-app guide. Read-only access to the compiled
  chapter index. See `MediaCentaur.Guide.Library` for the load mechanism.

  Chapters carry their body as raw markdown; rendering to HEEx is a web-layer
  concern (`MediaCentaurWeb.GuideMarkdown`), so this context stays data-only.
  """
  use Boundary, deps: [], exports: [Chapter]

  alias MediaCentaur.Guide.{Chapter, Library}

  @spec chapters() :: [Chapter.t()]
  defdelegate chapters(), to: Library

  @doc "Chapters grouped into ordered parts: `[{part_name, [chapter]}]`."
  @spec parts() :: [{String.t(), [Chapter.t()]}]
  def parts do
    chapters()
    |> Enum.chunk_by(& &1.part)
    |> Enum.map(fn [%{part: part} | _] = chs -> {part, chs} end)
  end

  @spec fetch_chapter(String.t()) :: {:ok, Chapter.t()} | :error
  defdelegate fetch_chapter(slug), to: Library, as: :fetch
end
