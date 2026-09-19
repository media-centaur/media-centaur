defmodule MediaCentaur.TimeSeries.LocalDay do
  @moduledoc """
  Local-midnight alignment without a time-zone database.

  The app ships none (`DateTime.shift_zone/2` with a named zone falls back
  to UTC everywhere), so the local offset comes from the operating system
  through `:calendar.local_time/0` against `:calendar.universal_time/0`,
  read at fold time. That is the offset in force *now*: a day-wide bar
  that lies across a daylight-saving change is an hour longer or shorter
  than its neighbours, and bars before the change sit an hour off their
  local midnight until the window rolls past it. Documented, bounded, and
  not worth a dependency.
  """

  @day 86_400

  @doc "Seconds the machine's local clock is ahead of UTC (negative when behind)."
  @spec utc_offset_seconds() :: integer()
  def utc_offset_seconds do
    local = :calendar.datetime_to_gregorian_seconds(:calendar.local_time())
    universal = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time())
    local - universal
  end

  @doc """
  Epoch seconds of the local midnight at or before `unix`, for a zone
  `offset` seconds from UTC.
  """
  @spec start_of_day(integer(), integer()) :: integer()
  def start_of_day(unix, offset) do
    local = unix + offset
    local - Integer.mod(local, @day) - offset
  end
end
