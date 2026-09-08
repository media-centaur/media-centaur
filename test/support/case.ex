defmodule MediaCentaur.Case do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The root case template every test module in this suite uses, directly
  or through `MediaCentaur.DataCase` and `MediaCentaurWeb.ConnCase`.

      use MediaCentaur.Case, async: true    # a pure test: owns nothing global
      use MediaCentaur.Case, async: false   # owns the machine for its duration

  `async:` is always written out — it is the one statement of whether the
  test owns the machine, and a Credo check refuses a bare `use ExUnit.Case`
  or a template used without it.

  Its single job is the edge `MediaCentaur.GlobalStateSandbox` needs: a
  sync test checks the machine out at entry and back in at exit. An async
  test is not checked out and must not write global state; concurrent
  tests share the machine, so nothing is reset for them.
  """

  use ExUnit.CaseTemplate

  setup tags do
    MediaCentaur.GlobalStateSandbox.checkout(tags)
    :ok
  end
end
