defmodule MediaCentaur.TmpDataDir do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  A per-test `data_dir` for tests that write under it (the TMDB artwork
  cache, app artwork, social avatars): a fresh tmp dir per test, removed
  on exit. The config term is swapped in place, so the test module must
  be `async: false`; `GlobalStateSandbox` restores the term at check-in.

      import MediaCentaur.TmpDataDir
      setup :setup_tmp_data_dir

  The context gains `:data_dir`.
  """

  alias MediaCentaur.Settings.Config

  @doc "Points `data_dir` at a fresh tmp dir for this test and puts it in the context as `:data_dir`."
  @spec setup_tmp_data_dir(map()) :: map()
  def setup_tmp_data_dir(context \\ %{}) do
    dir = Path.join(System.tmp_dir!(), "mc-data-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    config = :persistent_term.get({Config, :config})
    :persistent_term.put({Config, :config}, Map.put(config, :data_dir, dir))
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)

    Map.put(context, :data_dir, dir)
  end
end
