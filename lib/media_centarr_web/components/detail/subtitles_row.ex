defmodule MediaCentarrWeb.Components.Detail.SubtitlesRow do
  @moduledoc """
  Compact label-plus-codes row showing the subtitle languages
  available on a movie's linked file(s).

  Pure display: takes the pre-aggregated list from
  `MediaCentarr.Subtitles.aggregate_languages/1`, where each entry is
  an ISO 639-1 code or `nil` (sidecar with unrecognised language
  suffix). `nil` renders as the literal text `external` so the user
  can distinguish between "I have French subs" and "I have a sidecar
  but its language is unknown".

  An empty list renders nothing — the entire row is skipped, keeping
  the detail panel clean for movies without detected subtitles.

  Aggregation, deduping, and ordering all happen upstream in the
  Subtitles context. This component does not transform the input.
  """

  use MediaCentarrWeb, :html

  attr :languages, :list,
    required: true,
    doc:
      "deduped, sorted from `MediaCentarr.Subtitles.aggregate_languages/1`. Each entry is an ISO 639-1 code (`String.t()`) or `nil` for an unknown-language sidecar. Element types are primitive — no struct."

  def subtitles_row(assigns) do
    ~H"""
    <div :if={@languages != []} class="flex items-baseline gap-3 text-sm">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50 shrink-0">
        Subtitles
      </h3>
      <p class="text-base-content/80 leading-relaxed">
        <%= for {language, index} <- Enum.with_index(@languages) do %>
          <span :if={index > 0} class="text-base-content/30 mx-1.5">·</span><span class={
            language == nil && "text-base-content/50 italic"
          }>{display(language)}</span>
        <% end %>
      </p>
    </div>
    """
  end

  defp display(nil), do: "external"
  defp display(code) when is_binary(code), do: code
end
