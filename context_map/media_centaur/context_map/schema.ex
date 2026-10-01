defmodule MediaCentaur.ContextMap.Schema do
  @moduledoc "One Ecto schema as the map sees it: owning context, source file, table (nil for an embedded schema), persisted fields with enum values, associations with their target schema and, for `belongs_to`, the foreign-key column. Each field and association carries `line` and `declaration`, its declaration in `file` (see `MediaCentaur.ContextMap.Schemas`)."

  @enforce_keys [:module, :context, :file, :table, :fields, :associations]
  defstruct [:module, :context, :file, :table, :fields, :associations]

  @type field :: %{
          name: atom(),
          type: String.t(),
          values: [atom()] | nil,
          line: pos_integer(),
          declaration: String.t()
        }
  @type association :: %{
          name: atom(),
          kind: :belongs_to | :has_one | :has_many | :many_to_many,
          target: module(),
          foreign_key: atom() | nil,
          line: pos_integer(),
          declaration: String.t()
        }
  @type t :: %__MODULE__{
          module: module(),
          context: module() | nil,
          file: String.t(),
          table: String.t() | nil,
          fields: [field()],
          associations: [association()]
        }
end
