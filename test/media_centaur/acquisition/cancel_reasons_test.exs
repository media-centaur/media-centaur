defmodule MediaCentaur.Acquisition.CancelReasonsTest do
  @moduledoc """
  The closed vocabulary written to `cancelled_reason` and rendered in
  pursuit timelines. The module exists because inline literals drifted —
  two pages used different reasons for the same action — so the test that
  matters is that every named constant is in `all/0` and that `valid?/1`
  accepts exactly those strings.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.CancelReasons

  @constants [
    :user_disabled,
    :user_request,
    :item_removed,
    :in_library,
    :identity_mismatch,
    :abandoned,
    :zero_seeders,
    :stall,
    :superseded_by_plans,
    :auto_grab_disabled
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
