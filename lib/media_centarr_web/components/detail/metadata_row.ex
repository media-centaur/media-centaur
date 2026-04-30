defmodule MediaCentarrWeb.Components.Detail.MetadataRow do
  @moduledoc """
  Horizontal metadata row: an outline type badge followed by dotted text
  items (year, runtime, rating, status, country, etc).

  `items` is a list of strings; nil and blank strings are silently dropped
  so the calling template doesn't need to defend against missing data.
  """
  use MediaCentarrWeb, :html

  attr :badge_text, :string, required: true

  attr :items, :list,
    default: [],
    doc:
      "list of display strings (year, runtime, rating, status, country). `nil` and blank entries are silently dropped. Element type is `String.t()` — primitive, no struct needed."

  def metadata_row(assigns) do
    items =
      (assigns.items || [])
      |> Enum.reject(&blank?/1)
      |> Enum.with_index()

    assigns = assign(assigns, :indexed_items, items)

    ~H"""
    <div class="flex items-center flex-wrap gap-x-2 gap-y-1 text-sm text-base-content/60">
      <span class="badge badge-outline badge-sm">{@badge_text}</span>
      <%= for {item, idx} <- @indexed_items do %>
        <span :if={idx > 0} class="text-base-content/30 select-none">·</span>
        <span>{item}</span>
      <% end %>
    </div>
    """
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
