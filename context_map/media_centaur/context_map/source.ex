defmodule MediaCentaur.ContextMap.Source do
  @moduledoc "One parsed source file under `lib/`."

  @enforce_keys [:path, :modules, :context, :references, :live_view?, :ast, :lines]
  defstruct [:path, :modules, :context, :references, :live_view?, :ast, :lines]

  @type t :: %__MODULE__{
          path: String.t(),
          modules: [module()],
          context: module() | :web | nil,
          references: MapSet.t(module()),
          live_view?: boolean(),
          ast: Macro.t(),
          lines: [String.t()]
        }

  @doc "The text of 1-based `line`, empty when the file has no such line."
  @spec line(t(), pos_integer()) :: String.t()
  def line(%__MODULE__{lines: lines}, line), do: Enum.at(lines, line - 1, "")
end
