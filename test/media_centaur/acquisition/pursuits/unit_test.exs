defmodule MediaCentaur.Acquisition.Pursuits.UnitTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.Unit

  @pursuit_id Ecto.UUID.generate()

  describe "create_changeset/1" do
    test "valid attrs produce a valid changeset starting in active state" do
      changeset =
        Unit.create_changeset(%{
          pursuit_id: @pursuit_id,
          label: "S01E03",
          query: "Sample Show S01E03",
          position: 2
        })

      assert changeset.valid?
      assert changeset.changes.pursuit_id == @pursuit_id
      assert changeset.changes.label == "S01E03"
      assert changeset.changes.query == "Sample Show S01E03"
      assert changeset.changes.position == 2
      assert Ecto.Changeset.get_field(changeset, :state) == "active"
      assert Ecto.Changeset.get_field(changeset, :attempt_count) == 0
      assert Ecto.Changeset.get_field(changeset, :tried_release_guids) == []
    end

    test "label and query are optional (single-unit TMDB pursuits carry neither)" do
      changeset = Unit.create_changeset(%{pursuit_id: @pursuit_id})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :position) == 0
    end

    test "requires pursuit_id" do
      changeset = Unit.create_changeset(%{label: "S01E03"})

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :pursuit_id)
    end
  end

  describe "state transitions" do
    test "satisfy_changeset closes an active unit and clears awaiting-decision" do
      unit = %Unit{state: "active", awaiting_decision_at: DateTime.utc_now(:second)}

      changeset = Unit.satisfy_changeset(unit)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :state) == "satisfied"
      assert Ecto.Changeset.get_field(changeset, :awaiting_decision_at) == nil
    end

    test "exhaust_changeset closes an active unit" do
      changeset = Unit.exhaust_changeset(%Unit{state: "active"})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :state) == "exhausted"
    end

    test "cancel_changeset closes an active unit" do
      changeset = Unit.cancel_changeset(%Unit{state: "active"})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :state) == "cancelled"
    end

    test "terminal transitions reject a unit that is not in flight" do
      transitions = [&Unit.satisfy_changeset/1, &Unit.exhaust_changeset/1, &Unit.cancel_changeset/1]

      for transition <- transitions do
        changeset = transition.(%Unit{state: "satisfied"})

        refute changeset.valid?
        assert Keyword.has_key?(changeset.errors, :state)
      end
    end
  end

  describe "awaiting-decision flag" do
    test "set_awaiting_decision_changeset stamps the flag once and is idempotent" do
      now = DateTime.utc_now(:second)
      changeset = Unit.set_awaiting_decision_changeset(%Unit{awaiting_decision_at: nil}, now)

      assert Ecto.Changeset.get_field(changeset, :awaiting_decision_at) == now

      already_set = %Unit{awaiting_decision_at: now}
      later = DateTime.add(now, 3600, :second)
      idempotent = Unit.set_awaiting_decision_changeset(already_set, later)

      assert Ecto.Changeset.get_field(idempotent, :awaiting_decision_at) == now
    end

    test "clear_awaiting_decision_changeset clears the flag" do
      unit = %Unit{awaiting_decision_at: DateTime.utc_now(:second)}

      changeset = Unit.clear_awaiting_decision_changeset(unit)

      assert Ecto.Changeset.get_field(changeset, :awaiting_decision_at) == nil
    end
  end

  describe "attempt accounting" do
    test "record_attempt_changeset bumps attempt_count and appends the guid once" do
      unit = %Unit{attempt_count: 1, tried_release_guids: ["guid-a"]}

      changeset = Unit.record_attempt_changeset(unit, "guid-b")

      assert Ecto.Changeset.get_field(changeset, :attempt_count) == 2
      assert Ecto.Changeset.get_field(changeset, :tried_release_guids) == ["guid-a", "guid-b"]
    end

    test "record_attempt_changeset does not duplicate an already-tried guid" do
      unit = %Unit{attempt_count: 1, tried_release_guids: ["guid-a"]}

      changeset = Unit.record_attempt_changeset(unit, "guid-a")

      assert Ecto.Changeset.get_field(changeset, :attempt_count) == 2
      assert Ecto.Changeset.get_field(changeset, :tried_release_guids) == ["guid-a"]
    end

    test "record_attempt_changeset with nil guid bumps the count only" do
      changeset = Unit.record_attempt_changeset(%Unit{attempt_count: 0, tried_release_guids: []}, nil)

      assert Ecto.Changeset.get_field(changeset, :attempt_count) == 1
      assert Ecto.Changeset.get_field(changeset, :tried_release_guids) == []
    end
  end

  describe "set_current_target_changeset/2" do
    test "sets and clears the current target id" do
      target_id = Ecto.UUID.generate()

      set = Unit.set_current_target_changeset(%Unit{}, target_id)
      assert Ecto.Changeset.get_field(set, :current_target_id) == target_id

      cleared = Unit.set_current_target_changeset(%Unit{current_target_id: target_id}, nil)
      assert Ecto.Changeset.get_field(cleared, :current_target_id) == nil
    end
  end
end
