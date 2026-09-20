defmodule MediaCentaurWeb.Live.TitleDetailHost.TmdbEvents do
  @moduledoc """
  The words for what *Refresh from TMDB* found (UIDR-044). Pure: the
  host runs `MediaCentaur.TMDB.Store.check/1` off the view and hands the
  result here for the flash.
  """

  @doc "Maps a `TMDB.Store.check/1` result to a `{level, message}` flash."
  @spec check_flash({:ok, :unchanged | :changed, term()} | {:error, term()}) ::
          {:info | :error, String.t()}
  def check_flash({:ok, :unchanged, _record}), do: {:info, "Checked TMDB — nothing has changed."}
  def check_flash({:ok, :changed, _record}), do: {:info, "Updated from TMDB."}
  def check_flash({:error, _reason}), do: {:error, "TMDB didn't answer — try again later."}
end
