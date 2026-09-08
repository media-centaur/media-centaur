defmodule MediaCentaur.GlobalStateSandbox.StubOrphans do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Records every crash the suite logs for a request no `Req.Test` stub
  could answer, so that check-in can fail the test whose stubs the
  crashing process needed.

  Two things log such a crash. A task the test started and did not drive
  to completion outlives the test process that owned its stubs, raises on
  its next request, and is usually gone again before check-in can see it
  as a live child of `MediaCentaur.TaskSupervisor` — the stub loss is what
  kills it. Or a request runs during the test for a stub that was never
  installed, which ExUnit's log capture keeps out of sight. The crash
  report is logged synchronously in the dying process either way, and
  this `:logger` handler is where it is caught.

  Installed once by `MediaCentaur.GlobalStateSandbox.capture_baseline!/0`.
  The records live in an ETS table owned by the process running
  `test_helper.exs`; `list/0` reads them, `clear/0` empties them.
  """

  @table :media_centaur_stub_orphans
  @handler :media_centaur_stub_orphans
  # Private mode (no owner in the caller chain) and shared mode (an owner
  # without that stub) word the failure differently.
  @signatures ["cannot find mock/stub", "no mock or stub for"]

  @doc "Creates the record table and attaches the handler at error level."
  @spec install() :: :ok
  def install do
    :ets.new(@table, [:named_table, :public, :bag])
    :ok = :logger.add_handler(@handler, __MODULE__, %{level: :error, config: %{}})
  end

  @doc "Every recorded crash message, oldest first."
  @spec list() :: [String.t()]
  def list, do: @table |> :ets.tab2list() |> Enum.sort() |> Enum.map(&elem(&1, 1))

  @doc "Forgets every record."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc false
  def log(%{msg: msg}, _config) do
    text = message_text(msg)

    if String.contains?(text, @signatures) do
      :ets.insert(@table, {System.unique_integer([:monotonic]), summary(text)})
    end

    :ok
  end

  defp message_text({:string, chardata}), do: IO.chardata_to_string(chardata)
  defp message_text({:report, report}), do: inspect(report, limit: :infinity, printable_limit: :infinity)
  defp message_text({format, args}), do: format |> :io_lib.format(args) |> IO.chardata_to_string()

  # The stub name, the process, and the function the task ran — enough to
  # find the spawn — without the whole crash report.
  defp summary(text) do
    [stub] =
      Regex.run(
        ~r/(?:cannot find mock\/stub|no mock or stub for) :\w+(?: in process #PID<[\d.]+>)?/,
        text
      ) ||
        ["a request no stub could answer"]

    case Regex.run(~r/in (MediaCentaur[\w.]*\/\d)/, text, capture: :all_but_first) do
      [function] -> "#{stub} (#{function})"
      nil -> stub
    end
  end
end
