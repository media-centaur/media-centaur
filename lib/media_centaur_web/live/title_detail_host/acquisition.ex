defmodule MediaCentaurWeb.Live.TitleDetailHost.Acquisition do
  @moduledoc """
  The title detail's acquisition acts, shared by every host of the
  modal: moving a title's rung.

  `apply_rung/4` is the one write behind the bookmark and the tracking
  switches (`set_rung`). Raising onto a rung that follows releases needs
  the calendar, which is a TMDB fetch — so a title that has none yet is
  set asynchronously (`ReleaseTracking.set_rung_async/3`) and the modal
  catches up on the `:releases_updated` broadcast; every other move is
  local and lands before the reply. `attrs` is the provenance a
  feed-born listing carries onto the record it creates.
  """

  import Phoenix.LiveView, only: [put_flash: 3]

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TMDB.Title

  @spec apply_rung(Phoenix.LiveView.Socket.t(), Title.t(), TitleIntent.rung() | :off, map()) ::
          Phoenix.LiveView.Socket.t()
  def apply_rung(socket, %Title{} = title, :off, _attrs) do
    {:ok, nil} = ReleaseTracking.set_rung(title, :off)
    socket
  end

  def apply_rung(socket, %Title{} = title, rung, attrs) do
    needs_calendar? =
      TitleIntent.follows_releases?(rung) and
        is_nil(ReleaseTracking.get_item_by_tmdb(title.tmdb_id, title.media_type))

    if needs_calendar? do
      ReleaseTracking.set_rung_async(title, rung, attrs)
      put_flash(socket, :info, "Tracking #{title.name} — releases will appear under Coming up.")
    else
      {:ok, _intent} = ReleaseTracking.set_rung(title, rung, attrs)
      socket
    end
  end
end
