defmodule MediaCentaurWeb.Components.Detail.MetadataRow do
  @moduledoc """
  Horizontal metadata row: an outline type badge followed by dotted text
  items (year, runtime, rating, status, country, etc).

  `items` is a list of strings; nil and blank strings are silently dropped
  so the calling template doesn't need to defend against missing data.

  `remaining_text` (UIDR-024) is the mid-watch "29m left" figure — the
  hero hairline's caption — rendered as the line's final item, lightly
  tinted toward primary. Callers suppress the status item while a
  remaining figure exists; this component only places it.
  """

  use MediaCentaurWeb, :html

  attr :badge_text, :string, required: true

  attr :items, :list,
    default: [],
    doc:
      "list of display strings (year, runtime, rating, status, country). `nil` and blank entries are silently dropped. Element type is `String.t()` — primitive, no struct needed."

  attr :remaining_text, :string,
    default: nil,
    doc:
      "remaining-time item (\"29m left\") rendered last, tinted toward primary — UIDR-024. `nil` renders nothing."

  def metadata_row(assigns) do
    items =
      (assigns.items || [])
      |> Enum.reject(&blank?/1)
      |> Enum.with_index()

    assigns = assign(assigns, :indexed_items, items)

    ~H"""
    <div class="flex items-center flex-wrap gap-x-2 gap-y-1 text-sm text-base-content/60">
      <.badge variant="type">{@badge_text}</.badge>
      <%= for {item, idx} <- @indexed_items do %>
        <span :if={idx > 0} class="text-base-content/30 select-none">·</span>
        <span>{item}</span>
      <% end %>
      <%= if @remaining_text do %>
        <span :if={@indexed_items != []} class="text-base-content/30 select-none">·</span>
        <span class="text-primary/75">{@remaining_text}</span>
      <% end %>
    </div>
    """
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
