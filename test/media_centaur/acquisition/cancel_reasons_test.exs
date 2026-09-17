defmodule MediaCentaur.Acquisition.CancelReasonsTest do
  @moduledoc """
  The closed vocabulary written to `acquisition_targets.cancelled_reason` and
  rendered in pursuit timelines.

  Internal consistency — every named constant is in `all/0`, `valid?/1`
  accepts exactly those strings — is necessary but was never sufficient: it
  passed for months while the declared set and the set production code
  actually wrote had no value in common. The block that matters is
  "every reason production code writes is in the set", which names the write
  site for each one.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.CancelReasons

  @constants [
    :user_request,
    :item_removed,
    :auto_grab_disabled,
    :pursuit_cancelled,
    :pursuit_satisfied,
    :replaced_by_pick,
    :replaced_by_user_pivot,
    :orphan_target,
    :exhausted,
    :download_failed,
    :zero_seeders
  ]

  describe "all/0" do
    test "contains every named constant" do
      for constant <- @constants do
        assert apply(CancelReasons, constant, []) in CancelReasons.all(),
               "#{constant}/0 is not listed in all/0"
      end
    end

    test "has no duplicates and no extras beyond the named constants" do
      assert CancelReasons.all() == Enum.uniq(CancelReasons.all())
      assert length(CancelReasons.all()) == length(@constants)
    end

    test "every reason is a non-empty snake_case string" do
      for reason <- CancelReasons.all() do
        assert is_binary(reason)
        assert reason =~ ~r/^[a-z][a-z_]*[a-z]$/
      end
    end

    test "each constant returns the string form of its own name" do
      for constant <- @constants do
        assert apply(CancelReasons, constant, []) == Atom.to_string(constant)
      end
    end
  end

  # The guard the module was missing. Internal consistency (every constant is
  # in `all/0`) was already covered and passed for months while the declared
  # set and the written set had *zero* overlap. This block names the actual
  # write site for every reason production code can store, so a new writer
  # that invents a literal fails here.
  describe "every reason production code writes is in the set" do
    test "pursuit command reasons" do
      # Targets.close_in_flight_for/3 and Helpers.fail_current_target/2
      for {reason, site} <- [
            {"pursuit_cancelled", "Commands.Cancel"},
            {"pursuit_satisfied", "Commands.Satisfy"},
            {"replaced_by_pick", "Commands.PickTarget"},
            {"replaced_by_user_pivot", "Commands.ChangeTarget"}
          ] do
        assert CancelReasons.valid?(reason), "#{site} writes #{reason}, not in the set"
      end
    end

    test "target job reasons" do
      for {reason, site} <- [
            {"orphan_target", "Jobs.PursueTarget"},
            {"exhausted", "Jobs.PursueTarget"}
          ] do
        assert CancelReasons.valid?(reason), "#{site} writes #{reason}, not in the set"
      end
    end

    test "policy auto-cancel reasons" do
      # Commands.AutoCancel stores the Policy decision atom.
      for atom <- [:download_failed, :zero_seeders] do
        assert CancelReasons.valid?(CancelReasons.from_policy(atom)),
               "Policy emits #{atom}, not in the set"
      end
    end
  end

  describe "valid?/1" do
    test "accepts every recognised reason" do
      for reason <- CancelReasons.all() do
        assert CancelReasons.valid?(reason)
      end
    end

    test "rejects unknown strings, atoms, and nil" do
      refute CancelReasons.valid?("made_up_reason")
      refute CancelReasons.valid?("")
      refute CancelReasons.valid?(nil)
      # The atom form is not the stored form — accepting it would let an
      # atom reach a string column.
      refute CancelReasons.valid?(:user_request)
    end
  end
end
