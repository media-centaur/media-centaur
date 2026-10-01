defmodule MediaCentaur.ContextMap.Schema do
  @moduledoc "One Ecto schema as the map sees it: owning context, table, persisted fields with enum values, associations with their target schema and, for `belongs_to`, the foreign-key column."

  @enforce_keys [:module, :context, :table, :fields, :associations]
  defstruct [:module, :context, :table, :fields, :associations]

  @type field :: %{name: atom(), type: String.t(), values: [atom()] | nil}
  @type association :: %{
          name: atom(),
          kind: :belongs_to | :has_one | :has_many | :many_to_many,
          target: module(),
          foreign_key: atom() | nil
        }
  @type t :: %__MODULE__{
          module: module(),
          context: module() | nil,
          table: String.t() | nil,
          fields: [field()],
          associations: [association()]
        }
end
