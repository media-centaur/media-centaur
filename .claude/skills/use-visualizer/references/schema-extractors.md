# Creating Custom Schema Extractors

Schema extractors pull data model information from module ASTs. The built-in extractor handles Ecto schemas. Implement `Visualizer.SchemaExtractor` to support other frameworks (e.g., Ash).

## The SchemaExtractor Behaviour

```elixir
@callback extract(module_body :: Macro.t(), module_id :: String.t()) ::
            {:ok, ErdSchema.t()} | :skip
```

- **`module_body`** — the AST inside a `defmodule` block (from `Code.string_to_quoted/2`). May be a `{:__block__, _, children}` tuple or a single expression.
- **`module_id`** — fully qualified module name as a string (e.g., `"MyApp.Accounts.User"`).
- Return `{:ok, %ErdSchema{}}` if the module defines a data model, `:skip` otherwise.

## ErdSchema Struct

```elixir
%Visualizer.Schema.ErdSchema{
  module_id: "MyApp.Accounts.User",
  table_name: "users",
  fields: [
    %Visualizer.Schema.ErdField{name: "email", type: "string"},
    %Visualizer.Schema.ErdField{name: "age", type: "integer"}
  ],
  associations: [
    %Visualizer.Schema.ErdAssociation{type: "has_many", name: "posts", target: "MyApp.Blog.Post"},
    %Visualizer.Schema.ErdAssociation{type: "belongs_to", name: "org", target: "MyApp.Accounts.Org"}
  ]
}
```

### Fields

- `module_id` — must match the `module_id` argument
- `table_name` — the database table name as a string
- `fields` — list of `%ErdField{name, type}` where both are strings
- `associations` — list of `%ErdAssociation{type, name, target}` where:
  - `type` is one of: `"belongs_to"`, `"has_many"`, `"has_one"`, `"many_to_many"`
  - `name` is the association name as a string
  - `target` is the fully qualified module name of the associated schema

## AST Helpers

`Visualizer.AST` provides shared helpers:

- **`extract_do_body/1`** — extracts the body from a `do` block in the AST. Handles both `[{:do, body}]` and `[{{:__block__, _, [:do]}, body}]` forms.
- **`walk_modules/2`** — walks an AST tree, calling a callback for each `defmodule`. The callback receives `(module_name, body, meta)` and returns a list.
- **`resolve_module_name/2`** — resolves an `__aliases__` AST node to a dot-separated module name string.

## Implementation Pattern

1. Check for a marker indicating the framework is in use (e.g., `use Ecto.Schema`)
2. Find the schema-defining macro call (e.g., `schema "table_name" do ... end`)
3. Extract fields from inside the macro body
4. Extract associations from inside the macro body
5. Return `{:ok, %ErdSchema{}}` or `:skip`

## Reference Implementation

See `Visualizer.SchemaExtractors.Ecto` (`lib/visualizer/schema_extractors/ecto.ex`) for a complete working example that extracts Ecto schema fields and associations from the AST.

## Integration

Schema extractors are called from view `prepare/2` callbacks. The ERD view currently uses `SchemaExtractors.Ecto` directly. To use a custom extractor, implement your own view or fork the ERD view's `prepare/2` logic.
