defmodule MediaCentarrWeb.Components.Detail.ChipList do
  @moduledoc """
  Pill-shaped chips for genres, themes, or any short tag list.
  Nil and blank strings are silently dropped so callers don't have
  to defend against missing data.
  """
  use MediaCentarrWeb, :html

  attr :items, :list, default: []

  def chip_list(assigns) do
    items = Enum.reject(assigns.items || [], &blank?/1)

    assigns = assign(assigns, :items, items)

    ~H"""
    <div :if={@items != []} class="flex flex-wrap gap-1.5">
      <span
        :for={item <- @items}
        class="px-2.5 py-1 rounded-full bg-base-content/[0.04] border border-base-content/[0.08] text-xs text-base-content/80"
      >
        {item}
      </span>
    </div>
    """
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
