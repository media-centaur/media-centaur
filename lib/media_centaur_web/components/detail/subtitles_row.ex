defmodule MediaCentaurWeb.Components.Detail.SubtitlesRow do
  @moduledoc """
  Compact label-plus-codes row showing the subtitle languages
  available on a movie's linked file(s).

  Releases routinely ship a dozen-plus subtitle tracks; listing them
  all wraps the row across lines for languages the user will never
  pick. The row leads with the languages the user configured as
  understood (Settings → Language), comma-delimited, folding the rest
  behind a trailing `+` (`en+`) that expands to the full list on click —
  a pure client-side toggle, no server round-trip. With no configured
  languages everything shows up front; with none matching, the row is
  just the `+`.

  Pure display: takes the pre-aggregated list from
  `MediaCentaur.Subtitles.aggregate_track_languages/1`, where each
  entry is an ISO 639-1 code or `nil` (sidecar with unrecognised
  language suffix). `nil` renders as the literal text `external` so the
  user can distinguish between "I have French subs" and "I have a
  sidecar but its language is unknown". An empty list renders nothing.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Iso639
  alias Phoenix.LiveView.JS

  attr :languages, :list,
    required: true,
    doc:
      "deduped, sorted from `MediaCentaur.Subtitles.aggregate_track_languages/1`. Each entry is an ISO 639-1 code (`String.t()`) or `nil` for an unknown-language sidecar. Element types are primitive — no struct."

  attr :understood, :list,
    default: [],
    doc:
      "the user's understood-language codes (`LanguagePolicy.understood_languages`, ISO 639-2). Languages matching these lead the row; the rest fold behind the trailing-+ reveal. Empty list shows everything."

  def subtitles_row(assigns) do
    {shown, hidden} = split_languages(assigns.languages, assigns.understood)

    assigns =
      assigns
      |> assign(:collapsed_label, "#{join_labels(shown)}+")
      |> assign(:full_text, join_labels(assigns.languages))
      |> assign(:folded?, hidden != [])

    ~H"""
    <div :if={@languages != []} class="flex items-baseline gap-3 text-sm">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50 shrink-0">
        Subtitles
      </h3>
      <p :if={!@folded?} class="text-base-content/80 leading-relaxed min-w-0">
        {@full_text}
      </p>
      <p :if={@folded?} class="text-base-content/80 leading-relaxed min-w-0">
        <%!-- The trailing "+" is the whole affordance: click to expand
              to the complete list. Kept terse on purpose — the folded
              languages are ones the user didn't configure as understood. --%>
        <button
          id="subtitles-row-folded"
          type="button"
          class="cursor-pointer hover:text-base-content"
          title="Show all subtitle languages"
          phx-click={
            JS.hide(to: "#subtitles-row-folded")
            |> JS.show(to: "#subtitles-row-all", display: "inline")
          }
          data-nav-item
          tabindex="0"
        >
          {@collapsed_label}
        </button>
        <span id="subtitles-row-all" class="hidden">{@full_text}</span>
      </p>
    </div>
    """
  end

  @doc """
  Splits the aggregated language list into `{shown, hidden}`: entries
  matching the user's understood languages (cross-form — the policy
  stores ISO 639-2, tracks carry 639-1) lead; everything else folds
  behind the reveal. No configured languages → everything shown.
  Relative order within each group is preserved.
  """
  @spec split_languages([String.t() | nil], [String.t()]) ::
          {[String.t() | nil], [String.t() | nil]}
  def split_languages(languages, []), do: {languages, []}

  def split_languages(languages, understood) when is_list(understood) do
    Enum.split_with(languages, fn language ->
      is_binary(language) and Enum.any?(understood, &Iso639.equal?(&1, language))
    end)
  end

  @doc """
  The display label for one aggregated subtitle entry: an unknown-language
  sidecar (`nil`) reads as `external`; a recognised ISO 639-1 code renders
  verbatim.
  """
  @spec language_label(String.t() | nil) :: String.t()
  def language_label(nil), do: "external"
  def language_label(code) when is_binary(code), do: code

  defp join_labels(languages), do: Enum.map_join(languages, ", ", &language_label/1)
end
