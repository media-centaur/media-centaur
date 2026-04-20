# Creating Custom Views

Views are pluggable visualizations. Implement the `ExCodeView.View` behaviour to add your own.

## The View Behaviour

```elixir
@callback name() :: String.t()
@callback description() :: String.t()
@callback template_path() :: String.t()
@callback js_sources() :: [String.t()]
@callback prepare(analysis :: map(), opts :: keyword()) :: {:ok, map()} | {:error, String.t()}
```

### Callbacks

- **`name/0`** — CLI identifier (e.g., `"sunburst"`). Used in `mix view sunburst`.
- **`description/0`** — One-line human-readable description. Shown by `mix view --list`.
- **`template_path/0`** — Absolute path to the HTML template file. Use `:code.priv_dir(:your_app)` to resolve.
- **`js_sources/0`** — Ordered list of absolute paths to JS files. These are concatenated in order into the template.
- **`prepare/2`** — Receives `%ExCodeView.Schema.Analysis{}` and keyword opts. Transform, enrich, or pass through the data. Return `{:ok, data}` or `{:error, reason}`.

## Template Requirements

The HTML template must contain exactly two placeholders:

- `{{DATA}}` — replaced with the analysis JSON (first occurrence only)
- `{{SCRIPT}}` — replaced with concatenated JS (first occurrence only)

Typical pattern:

```html
<!DOCTYPE html>
<html>
<body>
  <script>window.__DATA__ = {{DATA}};</script>
  <script type="module">
  {{SCRIPT}}
  </script>
</body>
</html>
```

The renderer uses `String.replace/3` with `global: false` — only the first occurrence of each placeholder is replaced.

## The prepare/2 Callback

The `opts` keyword list always includes `:project_dir` (the analyzed project's root). Use it if you need to read additional files.

Two patterns exist in the built-in views:

**Passthrough** (city view) — data is already complete:
```elixir
def prepare(analysis, _opts), do: {:ok, analysis}
```

**Enrichment** (ERD view) — read source files and add data:
```elixir
def prepare(analysis, opts) do
  project_dir = Keyword.fetch!(opts, :project_dir)
  # ... extract additional data from source files ...
  {:ok, %{analysis | erd_schemas: extracted_schemas}}
end
```

## Registration

In the consuming project's `config/config.exs`:

```elixir
config :ex_code_view, views: [MyPackage.Views.Sunburst]
```

Multiple views can be registered. Built-in views (city, erd) are always available.

## Complete Example

```elixir
defmodule MyPackage.Views.Sunburst do
  @behaviour ExCodeView.View

  @impl true
  def name, do: "sunburst"

  @impl true
  def description, do: "Sunburst diagram of module hierarchy"

  @impl true
  def template_path do
    Path.join(:code.priv_dir(:my_package), "views/sunburst/template.html")
  end

  @impl true
  def js_sources do
    base = Path.join(:code.priv_dir(:my_package), "views/sunburst/js")
    ~w(lib.js data.js layout.js app.js) |> Enum.map(&Path.join(base, &1))
  end

  @impl true
  def prepare(analysis, _opts), do: {:ok, analysis}
end
```

## Reference Implementations

- **City view** (`lib/ex_code_view/views/city.ex`) — passthrough prepare, Three.js viewer with importmap
- **ERD view** (`lib/ex_code_view/views/erd.ex`) — enriching prepare that extracts Ecto schemas from AST, SVG viewer
