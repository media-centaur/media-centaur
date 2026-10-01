defmodule MediaCentaur.ContextMap.Context do
  @moduledoc "One bounded context as the map sees it: a `MediaCentaur.<Name>` facade with a `use Boundary` declaration."

  @enforce_keys [:name, :kernel?, :deps, :exports]
  defstruct [:name, :kernel?, :deps, :exports]

  @type t :: %__MODULE__{name: module(), kernel?: boolean(), deps: [module()], exports: [module()]}
end
