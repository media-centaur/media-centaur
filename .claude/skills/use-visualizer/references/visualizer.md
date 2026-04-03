# Rules for working with Visualizer

Visualizer analyzes Elixir codebases and generates self-contained HTML visualizations. The pipeline is: file discovery -> AST parsing -> namespace hierarchy -> coupling analysis -> view rendering -> single HTML file.

## Running Visualizations

```bash
mix visualize              # Default view (city)
mix visualize erd          # Specific view
mix visualize --open       # Open in browser after generation
mix visualize -o out.html  # Custom output path
mix visualize --json       # Raw analysis JSON instead of HTML
mix visualize --no-coupling # Skip dependency analysis (faster)
mix visualize --list       # List available views
```

## Built-in Views

- **city** — 3D software city (Three.js). Modules are buildings, namespaces are districts, coupling is arcs between buildings.
- **erd** — Entity-Relationship Diagram (SVG). Ecto schemas grouped by Phoenix context with association lines.

## Configuration

All configuration is under `config :visualizer`:

```elixir
config :visualizer,
  default_view: "city",       # View used when none specified
  views: [],                  # External view modules to register
  source_dir: "lib",          # Directory to scan
  extensions: [".ex"],        # File extensions to include
  exclude: []                 # Glob patterns to exclude from analysis
```

## Programmatic API

```elixir
{:ok, analysis} = Visualizer.analyze(project_dir, opts)
```

Returns `{:ok, %Visualizer.Schema.Analysis{}}` or `{:error, reason}`.

Options: `:no_coupling`, `:source_dir`, `:extensions`, `:exclude`.

The `Analysis` struct contains: `roots`, `modules`, `namespaces`, `dependencies`, `erd_schemas`, `available_metrics`.

## Important Gotchas

- **Coupling analysis requires compilation.** It reads the Mix compiler manifest. If the project hasn't been compiled, coupling data will be empty.
- **ERD does NOT require Ecto as a dependency.** Schema extraction works directly from AST via `Code.string_to_quoted/2`.
- **Output is fully self-contained.** All JavaScript, CSS, and data are inlined into a single HTML file. No server needed.
- **The `--json` flag** outputs raw analysis JSON — useful for building custom tooling on top of Visualizer.

## Extension Points

Visualizer is extensible via two behaviours:

- **`Visualizer.View`** — add new visualization types. See the `visualizer:views` sub-rule.
- **`Visualizer.SchemaExtractor`** — add schema extraction for frameworks beyond Ecto (e.g., Ash). See the `visualizer:schema-extractors` sub-rule.
- **Viewer JavaScript** — the JS concatenation pattern and testing approach. See the `visualizer:viewer-js` sub-rule.

## JSON Schema Contract

The JSON data injected into views follows this structure:

```json
{
  "roots": ["my_app"],
  "modules": [{"id": "MyApp.Foo", "file": "my_app/foo.ex", "depth": 0, "namespace": "my_app", "metrics": {"loc": 42, "public_functions": 3}}],
  "namespaces": [{"id": "my_app", "path": "my_app", "root": "my_app", "modules": ["MyApp.Foo"], "children": []}],
  "dependencies": [{"from": "MyApp.Foo", "to": "MyApp.Bar", "count": 1, "dep_type": "runtime", "references": []}],
  "erd_schemas": [{"module_id": "MyApp.Foo", "table_name": "foos", "fields": [{"name": "title", "type": "string"}], "associations": [{"type": "belongs_to", "name": "bar", "target": "MyApp.Bar"}]}],
  "available_metrics": ["loc", "public_functions"]
}
```

- Module IDs are dot-separated (`MyApp.Accounts.User`)
- Namespace IDs are slash-separated (`my_app/accounts`), matching directory structure
- Dependency `from`/`to` must exactly match module IDs
- `dep_type` is `"runtime"` or `"compile"`
