defmodule MediaCentaurWeb.Components.Detail.OrientationMarquee do
  @moduledoc """
  TV-series orientation marquee for the detail panel's action region:
  an overline ("Up next" / "Start here" / "Series complete"), the next
  episode's position as large display type (`S4 · E10` — never the
  episode title, in any spoiler mode), and the whispered subline
  (`21m · 9 of 22 this season · 49% of the series`).

  Together with the hero's season hairline this replaces both the
  auto-scroll-to-current-episode behaviour and the PlayCard progress
  row for TV series (2026-08-04 orientation design). All copy and
  numbers come from `MediaCentaurWeb.ViewModel.Orientation` — the
  component only lays them out.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.ViewModel.Orientation

  attr :orientation, Orientation,
    required: true,
    doc: "built by `Orientation.build/2` from the detail page's season views + resume hint."

  def orientation_marquee(assigns) do
    assigns =
      assigns
      |> assign(:marquee, Orientation.marquee(assigns.orientation))
      |> assign(:subline, Orientation.subline(assigns.orientation))

    ~H"""
    <div data-role="orientation-marquee">
      <div class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/40">
        {Orientation.overline(@orientation)}
      </div>
      <div :if={@marquee} class="orientation-marquee-episode">
        {elem(@marquee, 0)}<span class="orientation-marquee-dot">·</span>{elem(@marquee, 1)}
      </div>
      <div :if={@subline} class="mt-0.5 text-[13px] text-base-content/50 tabular-nums">
        {@subline}
      </div>
    </div>
    """
  end
end
