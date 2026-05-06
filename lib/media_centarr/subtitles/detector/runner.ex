defmodule MediaCentarr.Subtitles.Detector.Runner do
  @moduledoc """
  Indirection seam for invoking external commands.

  Detectors that need a subprocess (today: `Detector.Ffprobe`) call
  `run/2` instead of `System.cmd/3` directly. The default impl is a
  thin pass-through; tests override
  `Application.put_env(:media_centarr, :subtitles_runner, fn ... end)`
  to feed canned `{stdout, exit_code}` results without spawning a real
  process.

  This is the project's standard way of handling external-binary seams
  — no mocking library, no `:meck`, just a function reference.
  """

  @typedoc "Result of running an external command — same shape as `System.cmd/3`."
  @type result :: {String.t(), non_neg_integer()}

  @typedoc "Function that runs a command. Wraps `System.cmd/3`."
  @type runner_fn :: (String.t(), [String.t()] -> result | {:error, term()})

  @spec run(String.t(), [String.t()]) :: result | {:error, term()}
  def run(executable, args) do
    runner = Application.get_env(:media_centarr, :subtitles_runner, &default_runner/2)
    runner.(executable, args)
  end

  defp default_runner(executable, args) do
    # `env: []` clears the inherited environment for the child process
    # — sobelow flags `System.cmd` calls that don't, since a hostile
    # env var could change subprocess behaviour. ffprobe doesn't need
    # any of our env to do its job.
    System.cmd(executable, args, stderr_to_stdout: true, env: [])
  rescue
    error in [ErlangError, File.Error] -> {:error, error}
  end
end
