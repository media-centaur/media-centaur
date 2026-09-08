defmodule MediaCentaur.TMDB.RateLimiterTest do
  # Drives the application singleton — owns the machine.
  use MediaCentaur.Case, async: false

  alias MediaCentaur.TMDB.RateLimiter

  test "reset/0 empties the window so every slot is available again" do
    :ok = RateLimiter.wait()
    :ok = RateLimiter.wait()
    assert %{used: 2} = RateLimiter.status()

    assert RateLimiter.reset() == :ok

    assert %{used: 0, available: total, total: total} = RateLimiter.status()
  end
end
