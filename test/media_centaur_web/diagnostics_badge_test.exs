defmodule MediaCentaurWeb.DiagnosticsBadgeTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaurWeb.DiagnosticsBadge

  test "count/0 reflects unseen detected incidents and mark_seen/0 clears it" do
    {:ok, _incident} =
      Store.upsert_log_incident(
        build_log_incident_attrs(
          fingerprint: "fp_unseen",
          severity: :error,
          occurred_at: DateTime.utc_now()
        )
      )

    assert DiagnosticsBadge.count() >= 1

    DiagnosticsBadge.mark_seen()

    assert DiagnosticsBadge.count() == 0
  end

  describe "Status nav badge render" do
    setup do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, conn: conn}
    end

    test "shows the unseen count in the sidebar on a non-status page", %{conn: conn} do
      {:ok, _incident} =
        Store.upsert_log_incident(
          build_log_incident_attrs(fingerprint: "fp_nav", occurred_at: DateTime.utc_now())
        )

      {:ok, _view, html} = live(conn, ~p"/history")

      assert html =~ "badge-error"
    end

    test "clears the badge after visiting /status", %{conn: conn} do
      {:ok, _incident} =
        Store.upsert_log_incident(
          build_log_incident_attrs(fingerprint: "fp_clear", occurred_at: DateTime.utc_now())
        )

      # Visiting /status advances diagnostics_seen_at past the incident.
      {:ok, _status_view, _html} = live(conn, ~p"/status")

      assert DiagnosticsBadge.count() == 0

      {:ok, _view, html} = live(conn, ~p"/history")
      refute html =~ "badge-error"
    end
  end
end
