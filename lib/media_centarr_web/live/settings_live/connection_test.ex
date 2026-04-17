defmodule MediaCentarrWeb.Live.SettingsLive.ConnectionTest do
  @moduledoc """
  Persisted connection-test results for Prowlarr and the download client.

  A connection test is a point-in-time observation — a success a week ago
  doesn't tell you much about right now. This module handles the pure
  formatting concerns: parsing/serializing the stored JSON, rendering the
  age ("3 min ago"), and deciding when a result is stale enough to warrant
  a retest.

  Persistence itself (reading/writing `Settings.Entry`) lives in
  `MediaCentarrWeb.SettingsLive` — this module is pure and tested under
  `async: true` with injected timestamps.
  """

  @type status :: :ok | :error
  @type info :: %{status: status(), tested_at: DateTime.t()}

  # After this many seconds, display the age with a "retest" hint — the
  # result is likely still correct but worth re-verifying.
  @stale_after_seconds 24 * 60 * 60

  @doc """
  Parses a stored map (as returned from `Settings.Entry`) into an `info`
  struct. Returns `nil` if the stored value is missing or malformed.
  """
  @spec parse(map() | nil) :: info() | nil
  def parse(nil), do: nil

  def parse(%{"status" => status, "tested_at" => iso})
      when status in ["ok", "error"] and is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _offset} ->
        %{status: String.to_existing_atom(status), tested_at: datetime}

      _ ->
        nil
    end
  end

  def parse(_), do: nil

  @doc "Serializes an `info` struct into a map suitable for JSON storage."
  @spec serialize(info()) :: map()
  def serialize(%{status: status, tested_at: %DateTime{} = tested_at}) do
    %{
      "status" => Atom.to_string(status),
      "tested_at" => DateTime.to_iso8601(tested_at)
    }
  end

  @doc """
  Returns a human-readable age like `"just now"`, `"3 min ago"`,
  `"2 hours ago"`, `"5 days ago"`. The `now` argument is injectable for
  deterministic testing.
  """
  @spec relative_age(DateTime.t(), DateTime.t()) :: String.t()
  def relative_age(tested_at, now \\ DateTime.utc_now()) do
    seconds = DateTime.diff(now, tested_at, :second)
    do_age(seconds)
  end

  defp do_age(seconds) when seconds < 60, do: "just now"

  defp do_age(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    "#{minutes} #{pluralize(minutes, "min", "min")} ago"
  end

  defp do_age(seconds) when seconds < 86_400 do
    hours = div(seconds, 3600)
    "#{hours} #{pluralize(hours, "hour", "hours")} ago"
  end

  defp do_age(seconds) do
    days = div(seconds, 86_400)
    "#{days} #{pluralize(days, "day", "days")} ago"
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_, _singular, plural), do: plural

  @doc "True when the test result is older than the staleness threshold."
  @spec stale?(DateTime.t(), DateTime.t()) :: boolean()
  def stale?(tested_at, now \\ DateTime.utc_now()) do
    DateTime.diff(now, tested_at, :second) > @stale_after_seconds
  end

  @doc "Returns the Settings.Entry key for a given test subject."
  @spec storage_key(:prowlarr | :download_client) :: String.t()
  def storage_key(:prowlarr), do: "acquisition:prowlarr:last_test"
  def storage_key(:download_client), do: "acquisition:download_client:last_test"
end
