defmodule MediaCentarr.Acquisition.Pursuits.EventTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Pursuits.Event

  describe "create_changeset/1" do
    test "valid attrs produce a valid changeset" do
      attrs = %{
        pursuit_id: Ecto.UUID.generate(),
        denormalized_pursuit_title: "Sample Movie",
        kind: "pursuit_started",
        payload: %{"origin" => "auto"},
        occurred_at: DateTime.utc_now(:second)
      }

      changeset = Event.create_changeset(attrs)
      assert changeset.valid?
    end

    test "permits nil pursuit_id (FK already nilified)" do
      attrs = %{
        pursuit_id: nil,
        denormalized_pursuit_title: "Sample Movie",
        kind: "pursuit_satisfied",
        payload: %{},
        occurred_at: DateTime.utc_now(:second)
      }

      changeset = Event.create_changeset(attrs)
      assert changeset.valid?
    end

    test "requires kind, denormalized_pursuit_title, occurred_at" do
      changeset = Event.create_changeset(%{})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :kind)
      assert Keyword.has_key?(changeset.errors, :denormalized_pursuit_title)
      assert Keyword.has_key?(changeset.errors, :occurred_at)
    end

    test "rejects unknown kind values" do
      attrs = %{
        pursuit_id: Ecto.UUID.generate(),
        denormalized_pursuit_title: "X",
        kind: "made_up_kind",
        payload: %{},
        occurred_at: DateTime.utc_now(:second)
      }

      changeset = Event.create_changeset(attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :kind)
    end

    test "payload defaults to empty map when omitted" do
      attrs = %{
        pursuit_id: Ecto.UUID.generate(),
        denormalized_pursuit_title: "X",
        kind: "pursuit_started",
        occurred_at: DateTime.utc_now(:second)
      }

      changeset = Event.create_changeset(attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :payload) == %{}
    end
  end

  describe "kinds/0" do
    test "returns the eighteen v1 kinds" do
      kinds = Event.kinds()

      expected = ~w(
        pursuit_started search_started release_picked release_no_match
        download_started health_changed stall_confirmed zero_seeders_confirmed
        auto_cancelled fallback_initiated user_decision_requested
        user_decision_recorded identity_mismatch identity_verified
        pursuit_satisfied pursuit_exhausted pursuit_cancelled
        target_changed
      )

      assert Enum.sort(kinds) == Enum.sort(expected)
    end
  end
end
