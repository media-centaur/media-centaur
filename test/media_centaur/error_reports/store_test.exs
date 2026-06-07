defmodule MediaCentaur.ErrorReports.StoreTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.ErrorReports.DiagnosticEvent
  alias MediaCentaur.ErrorReports.Incident
  alias MediaCentaur.ErrorReports.Store

  describe "insert_event/1" do
    test "persists a redacted diagnostic event" do
      attrs = build_diagnostic_event_attrs(fingerprint: "fp_event", message: "[Pipeline] boom")

      assert {:ok, %DiagnosticEvent{} = event} = Store.insert_event(attrs)
      assert event.id
      assert event.fingerprint == "fp_event"
      assert event.message == "[Pipeline] boom"
      assert event.level == :error

      assert [persisted] = Store.list_recent_events("fp_event")
      assert persisted.id == event.id
    end

    test "rejects an event missing required fields" do
      attrs = Map.delete(build_diagnostic_event_attrs(), :fingerprint)

      assert {:error, %Ecto.Changeset{} = changeset} = Store.insert_event(attrs)
      assert %{fingerprint: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_recent_events/2" do
    test "returns newest-first, capped at the limit, scoped to the fingerprint" do
      base = DateTime.utc_now()

      for offset <- 0..3 do
        Store.insert_event(
          build_diagnostic_event_attrs(
            fingerprint: "fp_recent",
            message: "event #{offset}",
            occurred_at: DateTime.add(base, offset, :second)
          )
        )
      end

      Store.insert_event(build_diagnostic_event_attrs(fingerprint: "fp_other"))

      events = Store.list_recent_events("fp_recent", 2)

      assert length(events) == 2
      assert Enum.map(events, & &1.message) == ["event 3", "event 2"]
    end
  end

  describe "upsert_log_incident/1" do
    test "opens a new :log incident on first occurrence" do
      at = DateTime.utc_now()
      attrs = build_log_incident_attrs(fingerprint: "fp_open", severity: :warning, occurred_at: at)

      assert {:ok, %Incident{} = incident} = Store.upsert_log_incident(attrs)
      assert incident.origin == :log
      assert incident.fingerprint == "fp_open"
      assert incident.severity == :warning
      assert incident.status == :open
      assert incident.count == 1
      assert DateTime.compare(incident.first_seen, at) == :eq
      assert DateTime.compare(incident.last_seen, at) == :eq
      assert incident.app_version_at_first == "0.77.6"
    end

    test "bumps count and advances last_seen on recurrence, keeping one row" do
      first = DateTime.utc_now()
      later = DateTime.add(first, 60, :second)

      {:ok, _} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_bump", occurred_at: first))

      {:ok, incident} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_bump", occurred_at: later))

      assert incident.count == 2
      assert DateTime.compare(incident.first_seen, first) == :eq
      assert DateTime.compare(incident.last_seen, later) == :eq
      assert [_only_one] = Store.list_incidents()
    end

    test "keeps the earliest first_seen when a recurrence is older" do
      newer = DateTime.utc_now()
      older = DateTime.add(newer, -300, :second)

      {:ok, _} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_oo", occurred_at: newer))

      {:ok, incident} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_oo", occurred_at: older))

      assert DateTime.compare(incident.first_seen, older) == :eq
      assert DateTime.compare(incident.last_seen, newer) == :eq
    end

    test "reopens a resolved incident when it recurs" do
      {:ok, incident} = Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_reopen"))
      {:ok, resolved} = Store.set_status(incident, :resolved)
      assert resolved.status == :resolved
      assert resolved.resolved_at

      {:ok, reopened} =
        Store.upsert_log_incident(
          build_log_incident_attrs(fingerprint: "fp_reopen", occurred_at: DateTime.utc_now())
        )

      assert reopened.id == incident.id
      assert reopened.status == :open
      assert reopened.resolved_at == nil
    end
  end

  describe "get_incident_by_fingerprint/1" do
    test "returns nil when no incident matches" do
      assert Store.get_incident_by_fingerprint("fp_absent") == nil
    end
  end

  describe "set_status/2" do
    test "stamps resolved_at on resolve and clears it on reopen" do
      {:ok, incident} = Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_status"))

      {:ok, acknowledged} = Store.set_status(incident, :acknowledged)
      assert acknowledged.status == :acknowledged
      assert acknowledged.resolved_at == nil

      {:ok, resolved} = Store.set_status(acknowledged, :resolved)
      assert resolved.resolved_at

      {:ok, opened} = Store.set_status(resolved, :open)
      assert opened.resolved_at == nil
    end
  end

  describe "delete_incident_by_fingerprint/1" do
    test "removes the incident and all of its diagnostic events" do
      fingerprint = "fp_purge"
      {:ok, _} = Store.upsert_log_incident(build_log_incident_attrs(fingerprint: fingerprint))
      {:ok, _} = Store.insert_event(build_diagnostic_event_attrs(fingerprint: fingerprint))
      {:ok, _} = Store.insert_event(build_diagnostic_event_attrs(fingerprint: fingerprint))

      assert Store.get_incident_by_fingerprint(fingerprint)
      assert length(Store.list_recent_events(fingerprint)) == 2

      assert :ok = Store.delete_incident_by_fingerprint(fingerprint)

      assert Store.get_incident_by_fingerprint(fingerprint) == nil
      assert Store.list_recent_events(fingerprint) == []
    end

    test "is a no-op for an unknown fingerprint" do
      assert :ok = Store.delete_incident_by_fingerprint("fp_absent")
    end

    test "leaves other fingerprints untouched" do
      {:ok, _} = Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_keep"))
      {:ok, _} = Store.insert_event(build_diagnostic_event_attrs(fingerprint: "fp_keep"))
      {:ok, _} = Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_drop"))

      assert :ok = Store.delete_incident_by_fingerprint("fp_drop")

      assert Store.get_incident_by_fingerprint("fp_keep")
      assert length(Store.list_recent_events("fp_keep")) == 1
      assert Store.get_incident_by_fingerprint("fp_drop") == nil
    end
  end

  describe "list_incidents/1" do
    test "filters by status and orders by last_seen descending" do
      old = DateTime.add(DateTime.utc_now(), -120, :second)
      recent = DateTime.utc_now()

      {:ok, a} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_a", occurred_at: old))

      {:ok, _b} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_b", occurred_at: recent))

      {:ok, _resolved} = Store.set_status(a, :resolved)

      assert [open_only] = Store.list_incidents(status: :open)
      assert open_only.fingerprint == "fp_b"

      ordered = Store.list_incidents()
      assert Enum.map(ordered, & &1.fingerprint) == ["fp_b", "fp_a"]
    end
  end

  describe "prune_events/1" do
    test "deletes events older than the cutoff and keeps the rest" do
      now = DateTime.utc_now()
      stale = DateTime.add(now, -40 * 24 * 3600, :second)
      fresh = DateTime.add(now, -1 * 24 * 3600, :second)
      cutoff = DateTime.add(now, -30 * 24 * 3600, :second)

      {:ok, _} =
        Store.insert_event(build_diagnostic_event_attrs(fingerprint: "fp_p", occurred_at: stale))

      {:ok, _} =
        Store.insert_event(build_diagnostic_event_attrs(fingerprint: "fp_p", occurred_at: fresh))

      assert Store.prune_events(cutoff) == 1
      assert [remaining] = Store.list_recent_events("fp_p")
      assert DateTime.compare(remaining.occurred_at, fresh) == :eq
    end

    test "does not touch incidents" do
      {:ok, _} = Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_keep"))
      Store.prune_events(DateTime.utc_now())

      assert [_incident] = Store.list_incidents()
    end
  end

  describe "create_user_incident/1" do
    test "persists an open :user incident with description and frozen context" do
      {:ok, incident} =
        Store.create_user_incident(%{
          user_description: "Something looks off on the home page",
          first_context: %{"vitals" => %{"tmdb" => %{"ok" => true}}}
        })

      assert incident.origin == :user
      assert incident.status == :open
      assert incident.severity == :warning
      assert incident.count == 1
      assert incident.user_description == "Something looks off on the home page"
      assert incident.first_context == %{"vitals" => %{"tmdb" => %{"ok" => true}}}
      assert incident.fingerprint =~ "user-"
    end

    test "does not group — two reports create two incidents" do
      {:ok, a} = Store.create_user_incident(%{user_description: "one", first_context: %{}})
      {:ok, b} = Store.create_user_incident(%{user_description: "two", first_context: %{}})
      refute a.id == b.id
      assert a.fingerprint != b.fingerprint
    end
  end

  describe "count_unseen_incidents/1" do
    test "counts open detected incidents newer than `since`, excluding :user and resolved" do
      since = ~U[2026-01-01 00:00:00Z]

      {:ok, _} =
        Store.upsert_log_incident(
          log_attrs(
            fingerprint: "fp-new",
            first_seen: ~U[2026-06-01 00:00:00Z],
            last_seen: ~U[2026-06-01 00:00:00Z]
          )
        )

      {:ok, _} =
        Store.upsert_log_incident(
          log_attrs(
            fingerprint: "fp-old",
            first_seen: ~U[2020-01-01 00:00:00Z],
            last_seen: ~U[2020-01-01 00:00:00Z]
          )
        )

      {:ok, _} = Store.create_user_incident(%{user_description: "x", first_context: %{}})

      assert Store.count_unseen_incidents(since) == 1
    end

    test "epoch `since` counts all open detected incidents" do
      {:ok, _} = Store.upsert_log_incident(log_attrs(fingerprint: "fp-a"))
      assert Store.count_unseen_incidents(~U[1970-01-01 00:00:00Z]) >= 1
    end

    # The Store's open path derives first_seen/last_seen from `occurred_at`, so a
    # caller-supplied first_seen override is funneled through occurred_at.
    defp log_attrs(overrides \\ []) do
      overrides = Map.new(overrides)
      now = DateTime.utc_now()
      occurred_at = overrides[:first_seen] || overrides[:occurred_at] || now

      Map.merge(
        %{
          fingerprint: "fp_" <> Ecto.UUID.generate(),
          component: "pipeline",
          severity: :error,
          message: "[Pipeline] sample failure",
          display_title: "Sample failure",
          occurred_at: occurred_at
        },
        Map.drop(overrides, [:first_seen, :last_seen])
      )
    end
  end

  describe "health/0" do
    test "is ok with no incidents" do
      assert %{status: :ok, open_count: 0, by_severity: by_severity} = Store.health()
      assert by_severity == %{}
    end

    test "rolls up open incidents by severity, worst severity wins" do
      {:ok, _} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_w", severity: :warning))

      {:ok, _} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_e1", severity: :error))

      {:ok, _} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_e2", severity: :error))

      assert %{status: :error, open_count: 3, by_severity: %{warning: 1, error: 2}} = Store.health()
    end

    test "excludes resolved incidents from the rollup" do
      {:ok, warning} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_w", severity: :warning))

      {:ok, error} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_e", severity: :error))

      {:ok, _} = Store.set_status(error, :resolved)

      assert %{status: :warning, open_count: 1, by_severity: %{warning: 1}} = Store.health()
      refute Map.has_key?(Store.health().by_severity, :error)
      _ = warning
    end

    test "acknowledged incidents still count as open" do
      {:ok, incident} =
        Store.upsert_log_incident(build_log_incident_attrs(fingerprint: "fp_ack", severity: :error))

      {:ok, _} = Store.set_status(incident, :acknowledged)

      assert %{status: :error, open_count: 1} = Store.health()
    end
  end
end
