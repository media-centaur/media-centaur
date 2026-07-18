defmodule MediaCentaurWeb.DiagnosticsBadge do
  @moduledoc """
  Discovery badge for the Status nav: the count of unseen, auto-detected open
  incidents (`:log`/`:subsystem` newer than `diagnostics_seen_at`). Owns the
  `diagnostics_seen_at` Settings entry so `ErrorReports` needs no `Settings` dep.

  The app-wide `:diagnostics_unseen` assign is seeded by the
  `MediaCentaurWeb.ShellBadges` on_mount hook, which reads this module's
  `count/0` through its cached projection.
  """

  alias MediaCentaur.ErrorReports
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Entry

  @key "diagnostics_seen_at"
  @epoch ~U[1970-01-01 00:00:00Z]

  @spec count() :: non_neg_integer()
  def count, do: ErrorReports.count_unseen_incidents(seen_at())

  @spec seen_at() :: DateTime.t()
  def seen_at do
    case Settings.get_by_key(@key) do
      {:ok, %Entry{value: %{"at" => iso}}} ->
        case DateTime.from_iso8601(iso) do
          {:ok, datetime, _offset} -> datetime
          _ -> @epoch
        end

      _ ->
        @epoch
    end
  end

  @spec mark_seen() :: :ok
  def mark_seen do
    Settings.find_or_create_entry(%{
      key: @key,
      value: %{"at" => DateTime.to_iso8601(DateTime.utc_now())}
    })

    :ok
  end
end
