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
end
