defmodule MediaCentaurWeb.TitleRef do
  @moduledoc """
  The `?title=<media_type>-<tmdb_id>` URL param — how every title surface
  names the title it has open (UIDR-035). The ref is the app-wide title
  identity (`MediaCentaur.TMDB.Title.ref/1`); this module is only its
  spelling in a URL and in `phx-value-ref` payloads.
  """

  alias MediaCentaur.TMDB.Title

  @type ref :: {integer(), Title.media_type()}

  @doc "ref → the `?title=` param value."
  @spec param(ref()) :: String.t()
  def param({tmdb_id, media_type}), do: "#{media_type}-#{tmdb_id}"

  @doc "`?title=<media_type>-<tmdb_id>` → ref."
  @spec parse(String.t() | nil) :: {:ok, ref()} | :error
  def parse("movie-" <> id), do: parse_id(id, :movie)
  def parse("tv_series-" <> id), do: parse_id(id, :tv_series)
  def parse(_other), do: :error

  defp parse_id(id, media_type) do
    case Integer.parse(id) do
      {tmdb_id, ""} -> {:ok, {tmdb_id, media_type}}
      _other -> :error
    end
  end
end
