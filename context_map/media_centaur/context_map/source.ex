defmodule MediaCentaur.ContextMap.Source do
  @moduledoc "One parsed source file under `lib/`. `struct_keys` holds the keys of every `defstruct` in the file (embedded Ecto schemas are `Schemas`, not struct keys)."

  @enforce_keys [:path, :modules, :context, :references, :struct_keys, :live_view?, :ast, :lines]
  defstruct [:path, :modules, :context, :references, :struct_keys, :live_view?, :ast, :lines]

  @type t :: %__MODULE__{
          path: String.t(),
          modules: [module()],
          context: module() | :web | nil,
          references: MapSet.t(module()),
          struct_keys: MapSet.t(atom()),
          live_view?: boolean(),
          ast: Macro.t(),
          lines: [String.t()]
        }

  @doc "The text of 1-based `line`, empty when the file has no such line."
  @spec line(t(), pos_integer()) :: String.t()
  def line(%__MODULE__{lines: lines}, line), do: Enum.at(lines, line - 1, "")
end
