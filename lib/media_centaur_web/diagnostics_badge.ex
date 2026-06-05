defmodule MediaCentaurWeb.DiagnosticsBadge do
  @moduledoc """
  Discovery badge for the Status nav: the count of unseen, auto-detected open
  incidents (`:log`/`:subsystem` newer than `diagnostics_seen_at`). Owns the
  `diagnostics_seen_at` Settings entry so `ErrorReports` needs no `Settings` dep.

  Provides an `on_mount` hook that assigns `:diagnostics_unseen` app-wide and
  live-refreshes it on the `error_reports` PubSub broadcast.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias MediaCentaur.ErrorReports
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Entry
  alias MediaCentaur.Topics

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

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.error_reports())
    end

    socket =
      socket
      |> assign(:diagnostics_unseen, count())
      |> attach_hook(:diagnostics_badge, :handle_info, &refresh/2)

    {:cont, socket}
  end

  defp refresh({:buckets_changed, _buckets}, socket) do
    {:cont, assign(socket, :diagnostics_unseen, count())}
  end

  defp refresh(_msg, socket), do: {:cont, socket}
end
