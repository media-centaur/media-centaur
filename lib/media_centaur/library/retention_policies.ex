defmodule MediaCentaur.Library.RetentionPolicies do
  @moduledoc """
  Retention policies owned by Library — both `:external`: the change log
  caps itself inline on every insert, and the absence sweeper unlinks
  long-absent files on its own daily TTL check (reporting its runs via
  `Retention.record_run/2`).
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Config
  alias MediaCentaur.Retention.Policy

  @change_log_cap 100

  @impl true
  def policies do
    ttl_days = Config.get(:file_absence_ttl_days) || 30

    [
      %Policy{
        key: :change_log,
        subsystem: :library,
        label: "Library change log",
        description:
          "Only the #{@change_log_cap} most recent library changes are kept, " <>
            "trimmed as new changes arrive.",
        mode: :external
      },
      %Policy{
        key: :absent_files,
        subsystem: :watcher,
        label: "Absent files",
        description:
          "Files missing for #{ttl_days} days (with their drive confirmed present) are " <>
            "unlinked from the library, checked daily.",
        mode: :external
      }
    ]
  end
end
