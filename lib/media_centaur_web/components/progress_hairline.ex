defmodule MediaCentaurWeb.Components.ProgressHairline do
  @moduledoc """
  The cinematic hero's progress hairline — a 2px track flush on the hero
  window's bottom edge, with a glowing primary fill at the subject's
  watched fraction.

  UIDR-024: this is the **only** progress gauge in a cinematic modal, and
  the one rendering of it. Every `CinematicShell` tenant that shows
  subject progress renders this component in its orientation slot — TV
  series (series fraction), movies, and collection members (that movie's
  fraction) alike. The unit never branches: the hairline always shows the
  *subject's* watched fraction; per-set state (a collection's members)
  belongs to the poster rail's tile underlines.

  A fraction of `0.0` renders the bare track — deliberate, so unstarted
  and watched states occupy identical geometry and the block below never
  shifts. Visual treatment lives in `.orientation-hairline` /
  `.orientation-hairline-fill` (app.css).
  """

  use MediaCentaurWeb, :html

  attr :fraction, :float,
    required: true,
    doc: "the subject's watched share, `0.0..1.0`. `0.0` renders the bare track."

  attr :label, :string,
    required: true,
    doc: ~s(progressbar `aria-label` naming the subject — "Movie progress" / "Series progress".)

  attr :class, :string, default: nil, doc: "extra classes for the track element."

  def progress_hairline(assigns) do
    ~H"""
    <div
      class={["orientation-hairline", @class]}
      role="progressbar"
      aria-valuenow={round(@fraction * 100)}
      aria-valuemin="0"
      aria-valuemax="100"
      aria-label={@label}
    >
      <div class="orientation-hairline-fill" style={"width: #{@fraction * 100}%"} />
    </div>
    """
  end
end
