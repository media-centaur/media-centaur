defmodule MediaCentaurWeb.StorybookCompileTest do
  @moduledoc """
  Compile smoke for every storybook file. Closes the gap that `mix compile`
  doesn't cover: Phoenix Storybook compiles `.story.exs` and `_*.index.exs`
  files **lazily on dev page-load**, so a story with a typo or stale alias
  silently breaks until someone opens its catalog page.

  This test compiles each file in isolation and fails with the file path
  plus the underlying reason on the first compile error. One test per
  file, generated at module-compile time, so a single broken story
  doesn't mask the rest.

  Runs as part of `mix test` → `mix precommit`. ~5s for ~50 files.
  """

  use ExUnit.Case, async: false

  setup_all do
    # The storybook backend compiles in :test too (see
    # `lib/media_centaur_web/storybook.ex`), so every story module is
    # already loaded from the app beams. Re-compiling each file is the
    # whole point of this smoke — the "redefining module" warning it
    # triggers (~100 lines per run) is expected, not a defect. Suppress
    # module-conflict warnings for this suite only; async: false keeps
    # the global compiler option from racing other tests.
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)
    on_exit(fn -> Code.put_compiler_option(:ignore_module_conflict, previous) end)
    :ok
  end

  story_files =
    Path.wildcard("storybook/**/*.story.exs") ++
      Path.wildcard("storybook/**/_*.index.exs")

  if story_files == [] do
    raise "StorybookCompileTest: no story files found — wildcard is wrong"
  end

  for path <- story_files do
    @tag path: path
    test "compiles: #{path}" do
      relative = unquote(path)

      try do
        Code.compile_file(relative)
      rescue
        error ->
          flunk("""
          Failed to compile #{relative}:

          #{Exception.message(error)}
          """)
      end
    end
  end
end
