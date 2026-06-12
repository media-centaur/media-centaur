defmodule MediaCentaur.Repo.DataMigrations.DedupeSignalEventsTest do
  use MediaCentaur.DataCase, async: false

  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.Event
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.DedupeSignalEvents

  defp event_count(pursuit_id) do
    Repo.aggregate(from(e in Event, where: e.pursuit_id == ^pursuit_id), :count)
  end

  describe "dedupe/1" do
    test "collapses identical signal events sharing pursuit, kind, payload, and timestamp" do
      pursuit = create_pursuit(%{title: "Sample Show"})
      occurred_at = ~U[2026-06-12 11:00:00Z]

      # The per-unit emission bug: one torrent transition, recorded once
      # per unit — identical rows except for id.
      for _duplicate <- 1..5 do
        create_pursuit_event(pursuit, "download_started", %{
          payload: %{"client" => "qbittorrent"},
          occurred_at: occurred_at
        })
      end

      assert :ok = DedupeSignalEvents.dedupe(Repo)
      assert event_count(pursuit.id) == 1
    end

    test "keeps distinct transitions and distinct timestamps apart" do
      pursuit = create_pursuit(%{title: "Sample Show"})

      create_pursuit_event(pursuit, "health_changed", %{
        payload: %{"from_state" => "downloading", "to_state" => "stalled"},
        occurred_at: ~U[2026-06-12 11:00:00Z]
      })

      # Same payload, later tick — a real second transition, kept.
      create_pursuit_event(pursuit, "health_changed", %{
        payload: %{"from_state" => "downloading", "to_state" => "stalled"},
        occurred_at: ~U[2026-06-12 12:00:00Z]
      })

      # Different payload at the first timestamp — kept.
      create_pursuit_event(pursuit, "health_changed", %{
        payload: %{"from_state" => "stalled", "to_state" => "downloading"},
        occurred_at: ~U[2026-06-12 11:00:00Z]
      })

      assert :ok = DedupeSignalEvents.dedupe(Repo)
      assert event_count(pursuit.id) == 3
    end

    test "never touches decision or user events, and is idempotent" do
      pursuit = create_pursuit(%{title: "Sample Show"})
      occurred_at = ~U[2026-06-12 11:00:00Z]

      for _duplicate <- 1..2 do
        create_pursuit_event(pursuit, "user_decision_requested", %{
          payload: %{"prompt" => "Pick an alternative release."},
          occurred_at: occurred_at
        })
      end

      assert :ok = DedupeSignalEvents.dedupe(Repo)
      assert :ok = DedupeSignalEvents.dedupe(Repo)
      assert event_count(pursuit.id) == 2
    end
  end
end
