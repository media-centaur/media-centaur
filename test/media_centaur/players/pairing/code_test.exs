defmodule MediaCentaur.Players.Pairing.CodeTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Players.Pairing.Code

  @now ~U[2026-10-22 12:00:00Z]

  test "new/1 mints six digits that expire after the lifetime" do
    code = Code.new(@now)
    assert String.match?(code.code, ~r/^\d{6}$/)
    assert code.expires_at == DateTime.add(@now, Code.lifetime_minutes(), :minute)
    assert code.attempts_left == Code.max_attempts()
  end

  test "open?/2 is true until the expiry instant" do
    code = Code.new(@now)
    assert Code.open?(code, @now)
    assert Code.open?(code, DateTime.add(code.expires_at, -1, :second))
    refute Code.open?(code, code.expires_at)
    refute Code.open?(code, DateTime.add(code.expires_at, 1, :second))
  end

  test "redeem/3 matches the digits while open, and counts a miss" do
    code = Code.new(@now)
    assert Code.redeem(code, code.code, @now) == :ok
    assert Code.redeem(code, code.code, code.expires_at) == :expired

    assert {:miss, missed} = Code.redeem(code, "x" <> code.code, @now)
    assert missed.attempts_left == code.attempts_left - 1

    spent = %{code | attempts_left: 1}
    assert Code.redeem(spent, "x" <> code.code, @now) == :spent
  end
end
