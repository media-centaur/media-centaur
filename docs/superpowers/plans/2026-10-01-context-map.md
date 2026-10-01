# Context Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deterministic `mix context_map` that lists every Ecto schema by owning bounded context and every crossing of a context boundary at the data level (reinterpretation, cross-context key, foreign field), as sorted JSON plus a self-contained HTML page, with a verdicts file that will later gate precommit.

**Architecture:** A dev/test-only namespace `MediaCentaur.ContextMap` compiled from a new top-level `context_map/` directory (same arrangement as `credo_checks/`). Four input readers (`Contexts`, `Schemas`, `Sources`, `Surfaces`) produce plain structs; one AST `Walk` turns a source file into a flat list of *mentions* (an atom used as a key, a value, or a dot access, with its line and whether it sits in a pattern); three rule modules consume mentions and schemas and emit `Finding` structs; `Report` joins findings with verdicts and serialises; `Html` renders; the Mix task is the only entry point.

**Tech Stack:** Elixir 1.20, Sourceror 1.12 (already a dev/test dep), Ecto 3.14 schema reflection, Boundary's persisted module attribute, Jason, EEx. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-30-context-map-design.md`. Three signal details settled here and recorded back into the spec in Task 14: R3 reports an *unanchored* value only when that value belongs to exactly one schema field in the whole app (so `:movie` does not flood Discovery with findings); R2's "kernel" test applies to the *referenced* side of a crossing (the schema whose value is interpreted, or the key's target); `Item.library_container_id` resolves to no schema and is reported as an unresolved key rather than a kernel read.

**Every `mix` invocation below goes through `~/scripts/agents/agent-mix`** (CLAUDE.md: never run `mix` directly in an agent shell). Written as `agent-mix …`.

---

## File structure

```
context_map/
  media_centaur/context_map.ex                 # Boundary anchor + run/1 orchestration
  media_centaur/context_map/context.ex         # Context struct
  media_centaur/context_map/contexts.ex        # reads Boundary declarations
  media_centaur/context_map/schema.ex          # Schema struct
  media_centaur/context_map/schemas.ex         # Ecto reflection
  media_centaur/context_map/source.ex          # Source struct
  media_centaur/context_map/sources.ex         # parses lib/ with Sourceror
  media_centaur/context_map/walk.ex            # AST → mentions
  media_centaur/context_map/surfaces.ex        # web reference graph → LiveViews
  media_centaur/context_map/finding.ex         # Finding struct + key
  media_centaur/context_map/rules/reinterpretation.ex   # R3
  media_centaur/context_map/rules/cross_context_key.ex  # R4 + kernel reads
  media_centaur/context_map/rules/foreign_field.ex      # R1
  media_centaur/context_map/report.ex          # assemble, sort, encode, verdict join
  media_centaur/context_map/html.ex            # EEx render
  media_centaur/context_map/templates/context_map.html.eex
  mix/tasks/context_map.ex                     # mix context_map
test/context_map/
  contexts_test.exs
  schemas_test.exs
  sources_test.exs
  walk_test.exs
  surfaces_test.exs
  rules/reinterpretation_test.exs
  rules/cross_context_key_test.exs
  rules/foreign_field_test.exs
  report_test.exs
  html_test.exs
  fixture_instances_test.exs                   # § 4 of the spec, append-only
test/mix/tasks/context_map_test.exs
docs/context-map/context-map.json              # generated, committed
docs/context-map/verdicts.json                 # hand-maintained
docs/context-map.md                            # contributor doc
```

---

### Task 1: Compile path, Boundary anchor, empty task

**Files:**
- Modify: `mix.exs:61-63` (elixirc_paths), `.credo.exs:6` (included), `.formatter.exs` (inputs)
- Create: `context_map/media_centaur/context_map.ex`, `context_map/mix/tasks/context_map.ex`
- Test: `test/mix/tasks/context_map_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/mix/tasks/context_map_test.exs
defmodule Mix.Tasks.ContextMapTest do
  use MediaCentaur.Case, async: true

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  test "writes the JSON document to the path given", %{tmp_dir: tmp_dir} do
    json_path = Path.join(tmp_dir, "context-map.json")
    capture_io(fn -> Mix.Tasks.ContextMap.run(["--json", json_path]) end)
    assert {:ok, %{"contexts" => _, "findings" => _, "kernel_reads" => _}} = json_path |> File.read!() |> Jason.decode()
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/mix/tasks/context_map_test.exs`
Expected: FAIL, `Mix.Tasks.ContextMap.run/1 is undefined`.

- [ ] **Step 3: Add the compile path and tool configs**

In `mix.exs` replace the two `elixirc_paths` clauses:

```elixir
  defp elixirc_paths(:test), do: ["lib", "test/support", "credo_checks", "context_map"]
  defp elixirc_paths(:dev), do: ["lib", "credo_checks", "context_map"]
```

In `.credo.exs` line 6 add `"context_map/"` to `included`. In `.formatter.exs` add `"context_map/**/*.{ex,exs}"` to `inputs`.

- [ ] **Step 4: Write the anchor module with a stub run**

```elixir
# context_map/media_centaur/context_map.ex
defmodule MediaCentaur.ContextMap do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The context map: every Ecto schema by owning bounded context, and every
  crossing of a context boundary at the data level. Dev/test only — the
  `context_map/` directory is compiled by `elixirc_paths/1` for `:dev` and
  `:test`, like `credo_checks/`, and nothing under `lib/` references it.

  Design: `docs/superpowers/specs/2026-09-30-context-map-design.md`.
  Entry point: `mix context_map`.
  """

  @doc "Builds the whole document as a map ready for `Jason.encode!/2`."
  @spec build() :: map()
  def build do
    %{contexts: [], findings: [], kernel_reads: []}
  end
end
```

```elixir
# context_map/mix/tasks/context_map.ex
defmodule Mix.Tasks.ContextMap do
  @shortdoc "Generate the context map (schemas by context, boundary crossings)"
  use Boundary, top_level?: true, check: [in: false, out: false]
  use Mix.Task

  @moduledoc """
  Generates `docs/context-map/context-map.json` and, with `--html PATH`, a
  self-contained HTML rendering. `--check` fails when a finding has no
  verdict or a verdict has no finding (see `MediaCentaur.ContextMap.Report`).

      mix context_map
      mix context_map --html tmp/context-map.html
      mix context_map --check
  """

  @default_json "docs/context-map/context-map.json"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [json: :string, html: :string, check: :boolean])
    json_path = Keyword.get(opts, :json, @default_json)

    document = MediaCentaur.ContextMap.build()
    File.mkdir_p!(Path.dirname(json_path))
    File.write!(json_path, Jason.encode!(document, pretty: true) <> "\n")
    Mix.shell().info("context map: #{length(document.findings)} findings → #{json_path}")
  end
end
```

- [ ] **Step 5: Run the test**

Run: `agent-mix test test/mix/tasks/context_map_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mix.exs .credo.exs .formatter.exs context_map test/mix/tasks/context_map_test.exs
git commit -m "feat: context_map scaffold — dev-only namespace and empty mix task"
```

---

### Task 2: Contexts from Boundary declarations

**Files:**
- Create: `context_map/media_centaur/context_map/context.ex`, `context_map/media_centaur/context_map/contexts.ex`
- Test: `test/context_map/contexts_test.exs`

`use Boundary` persists its options on the module as the attribute `Boundary` (`Boundary.Definition.__before_compile__/1`), readable via `module.__info__(:attributes)`. Deps in those options are already full module names; exports are written relative to the context (`TitleIntent`) and must be prefixed.

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/contexts_test.exs
defmodule MediaCentaur.ContextMap.ContextsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Context
  alias MediaCentaur.ContextMap.Contexts

  test "lists Discovery with its deps and prefixed exports" do
    discovery = Enum.find(Contexts.all(), &(&1.name == MediaCentaur.Discovery))

    assert %Context{kernel?: false} = discovery
    assert MediaCentaur.Library in discovery.deps
    assert MediaCentaur.Discovery.TitleIntent in discovery.exports
  end

  test "Library and TMDB are the shared kernel" do
    kernel = for %Context{kernel?: true, name: name} <- Contexts.all(), do: name
    assert Enum.sort(kernel) == [MediaCentaur.Library, MediaCentaur.TMDB]
  end

  test "nested boundaries and tooling are not contexts" do
    names = Enum.map(Contexts.all(), & &1.name)
    refute MediaCentaur.Settings.Config in names
    refute MediaCentaur.Credo in names
    refute MediaCentaur.ContextMap in names
    refute MediaCentaurWeb in names
  end

  test "context_of folds nested modules into their context and the web layer into :web" do
    assert Contexts.context_of(MediaCentaur.Discovery.TitleIntent) == MediaCentaur.Discovery
    assert Contexts.context_of(MediaCentaur.Settings.Config) == MediaCentaur.Settings
    assert Contexts.context_of(MediaCentaurWeb.Components.Title.Logic) == :web
    assert Contexts.context_of(Mix.Tasks.ContextMap) == nil
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/contexts_test.exs`
Expected: FAIL, `MediaCentaur.ContextMap.Contexts` undefined.

- [ ] **Step 3: Implement**

```elixir
# context_map/media_centaur/context_map/context.ex
defmodule MediaCentaur.ContextMap.Context do
  @moduledoc "One bounded context as the map sees it: a `MediaCentaur.<Name>` facade with a `use Boundary` declaration."

  @enforce_keys [:name, :kernel?, :deps, :exports]
  defstruct [:name, :kernel?, :deps, :exports]

  @type t :: %__MODULE__{name: module(), kernel?: boolean(), deps: [module()], exports: [module()]}
end
```

```elixir
# context_map/media_centaur/context_map/contexts.ex
defmodule MediaCentaur.ContextMap.Contexts do
  @moduledoc """
  Reads the bounded contexts from the Boundary declarations the compiler
  already enforces. A context is a module named `MediaCentaur.<Name>` whose
  `use Boundary` is neither `classify_to` nor check-disabled tooling. Nested
  declarations (`MediaCentaur.Settings.Config`) fold into their parent by
  namespace. The web layer is `:web`, never a context.

  Shared-kernel membership is declared here (spec § 10), not detected.
  """

  alias MediaCentaur.ContextMap.Context

  @kernel [MediaCentaur.Library, MediaCentaur.TMDB]

  @spec all() :: [Context.t()]
  def all do
    {:ok, modules} = :application.get_key(:media_centaur, :modules)

    modules
    |> Enum.filter(&context_module?/1)
    |> Enum.map(&to_context/1)
    |> Enum.sort_by(&inspect(&1.name))
  end

  @doc "The context owning `module`, `:web` for the web layer, nil for anything else (Mix tasks, tooling)."
  @spec context_of(module()) :: module() | :web | nil
  def context_of(module) do
    case Module.split(module) do
      ["MediaCentaurWeb" | _] -> :web
      ["MediaCentaur", name | _] -> if context_module?(Module.concat(MediaCentaur, name)), do: Module.concat(MediaCentaur, name)
      _ -> nil
    end
  end

  @spec kernel?(module()) :: boolean()
  def kernel?(context), do: context in @kernel

  defp context_module?(module) do
    with ["MediaCentaur", _name] <- Module.split(module),
         true <- Code.ensure_loaded?(module),
         [%{opts: opts}] <- Keyword.get(module.__info__(:attributes), Boundary) do
      not Keyword.has_key?(opts, :classify_to) and not tooling?(opts)
    else
      _ -> false
    end
  end

  defp tooling?(opts), do: Keyword.get(opts, :check, []) == [in: false, out: false]

  defp to_context(module) do
    [%{opts: opts}] = Keyword.get(module.__info__(:attributes), Boundary)

    %Context{
      name: module,
      kernel?: kernel?(module),
      deps: opts |> Keyword.get(:deps, []) |> Enum.map(&dep_module/1) |> Enum.sort_by(&inspect/1),
      exports: opts |> Keyword.get(:exports, []) |> Enum.map(&export_module(module, &1)) |> Enum.sort_by(&inspect/1)
    }
  end

  defp dep_module({module, _mode}), do: module
  defp dep_module(module), do: module

  defp export_module(context, {module, _except}), do: export_module(context, module)

  defp export_module(context, module) do
    if List.starts_with?(Module.split(module), Module.split(context)), do: module, else: Module.concat(context, module)
  end
end
```

- [ ] **Step 4: Run the test**

Run: `agent-mix test test/context_map/contexts_test.exs`
Expected: PASS. If the "nested boundaries" test fails on a module you did not expect, print `Contexts.all()` names and adjust only `tooling?/1`; do not widen `context_module?/1`.

- [ ] **Step 5: Commit**

```bash
git add context_map test/context_map/contexts_test.exs
git commit -m "feat(context_map): contexts from Boundary declarations"
```

---

### Task 3: Schemas from Ecto reflection

**Files:**
- Create: `context_map/media_centaur/context_map/schema.ex`, `context_map/media_centaur/context_map/schemas.ex`
- Test: `test/context_map/schemas_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/schemas_test.exs
defmodule MediaCentaur.ContextMap.SchemasTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Schemas

  test "TitleIntent: context, table, enum values, no virtual or timestamp fields" do
    intent = Schemas.fetch!(MediaCentaur.Discovery.TitleIntent)

    assert %Schema{context: MediaCentaur.Discovery, table: "title_intents"} = intent
    assert %{name: :rung, type: "Ecto.Enum", values: [:ignored, :list, :follow, :grab]} = field(intent, :rung)
    assert %{name: :activity_id, type: "Ecto.UUID", values: nil} = field(intent, :activity_id)
    refute field(intent, :title)
    refute field(intent, :inserted_at)
    refute field(intent, :id)
  end

  test "WatchHistory.Event carries belongs_to associations with their targets" do
    event = Schemas.fetch!(MediaCentaur.WatchHistory.Event)
    movie = Enum.find(event.associations, &(&1.target == MediaCentaur.Library.Movie))
    assert %{kind: :belongs_to, field: :movie_id} = movie
  end

  test "every schema has an owning context" do
    assert Enum.all?(Schemas.all(), &(&1.context != nil))
  end

  test "value_owners maps an enum value to the fields that declare it" do
    owners = Schemas.value_owners(Schemas.all())
    assert {MediaCentaur.Discovery.TitleIntent, :rung} in owners[:ignored]
    assert length(owners[:movie]) > 1
  end

  defp field(schema, name), do: Enum.find(schema.fields, &(&1.name == name))
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/schemas_test.exs`
Expected: FAIL, `Schemas` undefined.

- [ ] **Step 3: Implement**

```elixir
# context_map/media_centaur/context_map/schema.ex
defmodule MediaCentaur.ContextMap.Schema do
  @moduledoc "One Ecto schema as the map sees it: owning context, table, persisted fields with enum values, associations with their target schema."

  @enforce_keys [:module, :context, :table, :fields, :associations]
  defstruct [:module, :context, :table, :fields, :associations]

  @type field :: %{name: atom(), type: String.t(), values: [atom()] | nil}
  @type association :: %{field: atom(), kind: :belongs_to | :has_one | :has_many | :many_to_many, target: module()}
  @type t :: %__MODULE__{module: module(), context: module() | nil, table: String.t() | nil, fields: [field()], associations: [association()]}
end
```

```elixir
# context_map/media_centaur/context_map/schemas.ex
defmodule MediaCentaur.ContextMap.Schemas do
  @moduledoc """
  Every Ecto schema in the application via `__schema__/1` reflection.
  Persisted fields only: primary keys, timestamps and virtual fields are
  dropped. `Ecto.Enum` fields carry their value set; other fields carry
  `values: nil`.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Schema

  @timestamps [:inserted_at, :updated_at]

  @spec all() :: [Schema.t()]
  def all do
    {:ok, modules} = :application.get_key(:media_centaur, :modules)

    modules
    |> Enum.filter(&schema_module?/1)
    |> Enum.map(&from_module/1)
    |> Enum.sort_by(&inspect(&1.module))
  end

  @spec fetch!(module()) :: Schema.t()
  def fetch!(module), do: from_module(module)

  @doc "Every enum value → the `{schema_module, field}` pairs declaring it, across all schemas."
  @spec value_owners([Schema.t()]) :: %{atom() => [{module(), atom()}]}
  def value_owners(schemas) do
    for schema <- schemas, %{name: field, values: values} when is_list(values) <- schema.fields, value <- values, reduce: %{} do
      acc -> Map.update(acc, value, [{schema.module, field}], &[{schema.module, field} | &1])
    end
    |> Map.new(fn {value, owners} -> {value, Enum.sort(owners)} end)
  end

  defp schema_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) and
      String.starts_with?(inspect(module), "MediaCentaur")
  end

  defp from_module(module) do
    drop = module.__schema__(:primary_key) ++ module.__schema__(:virtual_fields) ++ @timestamps

    %Schema{
      module: module,
      context: Contexts.context_of(module),
      table: module.__schema__(:source),
      fields: for(name <- module.__schema__(:fields), name not in drop, do: field(module, name)),
      associations: for(name <- module.__schema__(:associations), assoc = module.__schema__(:association, name), do: association(assoc))
    }
  end

  defp field(module, name) do
    case module.__schema__(:type, name) do
      {:parameterized, {Ecto.Enum, _}} -> %{name: name, type: "Ecto.Enum", values: Ecto.Enum.values(module, name)}
      type -> %{name: name, type: inspect(type), values: nil}
    end
  end

  defp association(%Ecto.Association.BelongsTo{field: field, owner_key: key, related: target}),
    do: %{field: key, kind: :belongs_to, target: target, name: field}

  defp association(%Ecto.Association.Has{field: field, cardinality: :one, related: target}),
    do: %{field: field, kind: :has_one, target: target, name: field}

  defp association(%Ecto.Association.Has{field: field, cardinality: :many, related: target}),
    do: %{field: field, kind: :has_many, target: target, name: field}

  defp association(%Ecto.Association.ManyToMany{field: field, related: target}),
    do: %{field: field, kind: :many_to_many, target: target, name: field}
end
```

- [ ] **Step 4: Run the test**

Run: `agent-mix test test/context_map/schemas_test.exs`
Expected: PASS. If `__schema__(:type, :rung)` is not the `{:parameterized, {Ecto.Enum, _}}` shape, print it once in iex (`agent-mix run -e 'IO.inspect MediaCentaur.Discovery.TitleIntent.__schema__(:type, :rung)'`) and match the shape Ecto 3.14 returns.

- [ ] **Step 5: Commit**

```bash
git add context_map test/context_map/schemas_test.exs
git commit -m "feat(context_map): schemas from Ecto reflection"
```

---

### Task 4: Sources — parse lib/ with Sourceror

**Files:**
- Create: `context_map/media_centaur/context_map/source.ex`, `context_map/media_centaur/context_map/sources.ex`
- Test: `test/context_map/sources_test.exs`

A `Source` is one file: the modules it defines, the context of its first module, the full module names it references (aliases resolved), whether it is a LiveView, its AST and its lines. Alias resolution is per file, not per scope — a stated limit.

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/sources_test.exs
defmodule MediaCentaur.ContextMap.SourcesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Source
  alias MediaCentaur.ContextMap.Sources

  @code """
  defmodule MediaCentaurWeb.SampleLive do
    use MediaCentaurWeb, :live_view
    alias MediaCentaur.Discovery.TitleIntent
    alias MediaCentaurWeb.Components.Title.{Logic, Row}
    alias MediaCentaur.Library.Movie, as: Film

    def pick(%TitleIntent{rung: rung}), do: Logic.marker(rung)
    def film(%Film{} = film), do: Row.render(film)
  end
  """

  test "modules, context, resolved references, live_view flag" do
    source = Sources.parse("lib/media_centaur_web/live/sample_live.ex", @code)

    assert %Source{path: "lib/media_centaur_web/live/sample_live.ex", modules: [MediaCentaurWeb.SampleLive], context: :web, live_view?: true} = source

    assert MediaCentaur.Discovery.TitleIntent in source.references
    assert MediaCentaurWeb.Components.Title.Logic in source.references
    assert MediaCentaurWeb.Components.Title.Row in source.references
    assert MediaCentaur.Library.Movie in source.references
    assert Enum.at(source.lines, 1) =~ "live_view"
  end

  test "a context module is not a live view and has its context" do
    source = Sources.parse("lib/media_centaur/discovery.ex", "defmodule MediaCentaur.Discovery do\n  def x, do: 1\nend\n")
    assert %Source{context: MediaCentaur.Discovery, live_view?: false} = source
  end

  test "all/0 reads every .ex under lib/media_centaur and lib/media_centaur_web, nothing under lib/mix" do
    paths = Sources.all() |> Enum.map(& &1.path)
    assert "lib/media_centaur/discovery.ex" in paths
    assert "lib/media_centaur_web/components/title/logic.ex" in paths
    refute Enum.any?(paths, &String.starts_with?(&1, "lib/mix/"))
    assert paths == Enum.sort(paths)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/sources_test.exs`
Expected: FAIL, `Sources` undefined.

- [ ] **Step 3: Implement**

```elixir
# context_map/media_centaur/context_map/source.ex
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
```

```elixir
# context_map/media_centaur/context_map/sources.ex
defmodule MediaCentaur.ContextMap.Sources do
  @moduledoc """
  Parses every `.ex` under `lib/media_centaur` and `lib/media_centaur_web`
  with Sourceror, so each node carries its line. `lib/mix` and
  `priv/repo/migrations` are not read: migrations are the one place
  literals are legitimately written.

  Aliases are resolved per file (`alias A.B`, `alias A.{B, C}`,
  `alias A.B, as: C`), not per scope — a stated limit of the map.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Source

  @roots ["lib/media_centaur", "lib/media_centaur_web"]

  @spec all() :: [Source.t()]
  def all do
    @roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.sort()
    |> Enum.map(&parse(&1, File.read!(&1)))
  end

  @spec parse(String.t(), String.t()) :: Source.t()
  def parse(path, code) do
    ast = Sourceror.parse_string!(code)
    modules = defined_modules(ast)
    aliases = aliases(ast)

    %Source{
      path: path,
      modules: modules,
      context: modules |> List.first() |> then(&if(&1, do: Contexts.context_of(&1))),
      references: references(ast, aliases),
      live_view?: live_view?(ast),
      ast: ast,
      lines: String.split(code, "\n")
    }
  end

  defp defined_modules(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc -> {node, [Module.concat(parts) | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(found)
  end

  defp aliases(ast) do
    {_, found} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = node, acc ->
          {node, Enum.reduce(children, acc, fn {:__aliases__, _, child}, acc -> Map.put(acc, List.last(child), Module.concat(base ++ child)) end)}

        {:alias, _, [{:__aliases__, _, parts}]} = node, acc ->
          {node, Map.put(acc, List.last(parts), Module.concat(parts))}

        {:alias, _, [{:__aliases__, _, parts}, [{{:__block__, _, [:as]}, {:__aliases__, _, [as]}}]]} = node, acc ->
          {node, Map.put(acc, as, Module.concat(parts))}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp references(ast, aliases) do
    {_, found} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:__aliases__, _, [head | rest] = parts} = node, acc when is_atom(head) ->
          resolved = if Map.has_key?(aliases, head), do: Module.concat([aliases[head] | rest]), else: Module.concat(parts)
          {node, MapSet.put(acc, resolved)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp live_view?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:use, _, [{:__aliases__, _, [:MediaCentaurWeb]}, {:__block__, _, [:live_view]}]} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end
end
```

- [ ] **Step 4: Run the test**

Run: `agent-mix test test/context_map/sources_test.exs`
Expected: PASS. Sourceror wraps literals as `{:__block__, meta, [literal]}`; if the `as:` or `live_view?` clauses do not match, inspect `Sourceror.parse_string!("alias A.B, as: C")` once and adjust the pattern to the wrapped shape.

- [ ] **Step 5: Commit**

```bash
git add context_map test/context_map/sources_test.exs
git commit -m "feat(context_map): parse lib/ sources with resolved references"
```

---

### Task 5: Walk — AST to mentions

**Files:**
- Create: `context_map/media_centaur/context_map/walk.ex`
- Test: `test/context_map/walk_test.exs`

A *mention* is one use of an atom in a file: `kind` is `:key` (a map or keyword key `rung:`), `:value` (a bare literal `:ignored`), or `:dot` (`x.rung`, `@detail.rung`, `i.rung` in a query); `pattern?` says whether it sits in a pattern (a `def` head, the left of `=`, the head of a `->` clause). HEEx template strings are scanned by regex, with `template?: true`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/walk_test.exs
defmodule MediaCentaur.ContextMap.WalkTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Sources
  alias MediaCentaur.ContextMap.Walk

  @code """
  defmodule Sample do
    import Ecto.Query

    def marker(:ignored), do: "Ignored"
    def marker(%{rung: rung}), do: rung
    def read(intent), do: intent.rung
    def write(changeset), do: Ecto.Changeset.put_change(changeset, :note, "x")
    def attrs, do: %{activity_id: 1, source: :friend}
    def query, do: from(i in Intent, where: i.rung != :ignored)
    def assign_it(socket) do
      %{rung: rung} = socket.assigns
      rung
    end
    def template(assigns) do
      ~H\"\"\"
      <p :if={@form == :ignored}>{@detail.rung}</p>
      \"\"\"
    end
  end
  """

  setup do
    %{mentions: Walk.mentions(Sources.parse("lib/media_centaur/sample.ex", @code))}
  end

  test "value literal in a def head is a pattern mention with its line", %{mentions: mentions} do
    assert %{kind: :value, atom: :ignored, line: 4, pattern?: true, template?: false} = find(mentions, :value, :ignored, 4)
  end

  test "map key in a def head is a pattern key; the same key in an expression is not", %{mentions: mentions} do
    assert %{pattern?: true} = find(mentions, :key, :rung, 5)
    assert %{pattern?: false} = find(mentions, :key, :activity_id, 8)
    assert %{pattern?: true} = find(mentions, :key, :rung, 11)
  end

  test "dot access and query field access are dot mentions", %{mentions: mentions} do
    assert find(mentions, :dot, :rung, 6)
    assert find(mentions, :dot, :rung, 9)
  end

  test "a value in an expression is not a pattern", %{mentions: mentions} do
    assert %{pattern?: false} = find(mentions, :value, :friend, 8)
    assert %{pattern?: false} = find(mentions, :value, :ignored, 9)
  end

  test "template strings yield template mentions on their own lines", %{mentions: mentions} do
    assert %{template?: true} = find(mentions, :value, :ignored, 16)
    assert %{template?: true} = find(mentions, :dot, :rung, 16)
  end

  test "keys are not also reported as values", %{mentions: mentions} do
    refute find(mentions, :value, :rung, 5)
  end

  defp find(mentions, kind, atom, line), do: Enum.find(mentions, &(&1.kind == kind and &1.atom == atom and &1.line == line))
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/walk_test.exs`
Expected: FAIL, `Walk` undefined.

- [ ] **Step 3: Implement**

```elixir
# context_map/media_centaur/context_map/walk.ex
defmodule MediaCentaur.ContextMap.Walk do
  @moduledoc """
  Turns a parsed source into a flat list of *mentions* — every atom used
  as a map/keyword key, as a bare literal value, or as a dot access —
  each with its line and whether it sits in a pattern (a `def` head, the
  left of `=`, the head of a `->` clause). The rules read mentions, never
  the AST.

  `~H` templates are strings to the parser; they are scanned by regex for
  `:atom` values and `.field` accesses and marked `template?: true`.
  """

  alias MediaCentaur.ContextMap.Source

  @type mention :: %{kind: :key | :value | :dot, atom: atom(), line: pos_integer(), pattern?: boolean(), template?: boolean()}

  @spec mentions(Source.t()) :: [mention()]
  def mentions(%Source{ast: ast}) do
    {_, {mentions, _depth}} = Macro.traverse(ast, {[], 0}, &pre/2, &post/2)
    mentions |> Enum.reverse() |> Enum.sort_by(&{&1.line, &1.kind, &1.atom})
  end

  # --- pattern tracking: wrap pattern positions so entering them bumps the depth ---

  defp pre({def, meta, [{name, head_meta, args} | body]}, acc) when def in [:def, :defp, :defmacro] and is_list(args),
    do: {{def, meta, [{name, head_meta, [wrap(args)]} | body]}, acc}

  defp pre({:=, meta, [left, right]}, acc), do: {{:=, meta, [wrap(left), right]}, acc}
  defp pre({:->, meta, [args, body]}, acc), do: {{:->, meta, [wrap(args), body]}, acc}
  defp pre({:__pattern__, _, [_]} = node, {mentions, depth}), do: {node, {mentions, depth + 1}}

  # sigil_H: the template is a string; scan it
  defp pre({:sigil_H, meta, [{:<<>>, _, [template]} | _]} = node, {mentions, depth}) when is_binary(template),
    do: {node, {template_mentions(template, meta[:line] || 1) ++ mentions, depth}}

  # keyword / map pair: the key is a key mention, and must not be re-walked as a value
  defp pre({{:__block__, meta, [key]}, value}, {mentions, depth}) when is_atom(key),
    do: {{nil, value}, {[mention(:key, key, meta, depth) | mentions], depth}}

  # dot access: x.field / i.field / @assigns.field
  defp pre({{:., meta, [_subject, field]}, _, []} = node, {mentions, depth}) when is_atom(field),
    do: {node, {[mention(:dot, field, meta, depth) | mentions], depth}}

  # bare atom literal (Sourceror wraps literals in __block__)
  defp pre({:__block__, meta, [atom]} = node, {mentions, depth}) when is_atom(atom) and not is_boolean(atom) and not is_nil(atom),
    do: {node, {[mention(:value, atom, meta, depth) | mentions], depth}}

  defp pre(node, acc), do: {node, acc}

  defp post({:__pattern__, _, [_]} = node, {mentions, depth}), do: {node, {mentions, depth - 1}}
  defp post(node, acc), do: {node, acc}

  defp wrap(inner), do: {:__pattern__, [], [inner]}

  defp mention(kind, atom, meta, depth),
    do: %{kind: kind, atom: atom, line: Keyword.get(meta, :line, 1), pattern?: depth > 0, template?: false}

  # --- templates ---

  defp template_mentions(template, start_line) do
    template
    |> String.split("\n")
    |> Enum.with_index(start_line)
    |> Enum.flat_map(fn {text, line} ->
      values = for [atom] <- Regex.scan(~r/(?<![\w@:])\:([a-z_][a-z0-9_?!]*)/, text), do: template_mention(:value, atom, line)
      dots = for [field] <- Regex.scan(~r/[\w\)\]]\.([a-z_][a-z0-9_?!]*)/, text), do: template_mention(:dot, field, line)
      values ++ dots
    end)
  end

  defp template_mention(kind, name, line),
    do: %{kind: kind, atom: String.to_atom(name), line: line, pattern?: false, template?: true}
end
```

- [ ] **Step 4: Run the test**

Run: `agent-mix test test/context_map/walk_test.exs`
Expected: PASS. The two likely adjustments: the sigil line (the `~H` node's `line:` is the sigil's own line, so the first template line is `start_line + 1` — fix the offset in `Enum.with_index/2`, the test pins line 16) and the keyword-pair shape (check `Sourceror.parse_string!("%{a: 1}")` once and match what it prints).

- [ ] **Step 5: Commit**

```bash
git add context_map test/context_map/walk_test.exs
git commit -m "feat(context_map): AST walk to key/value/dot mentions with pattern tracking"
```

---

### Task 6: Finding struct and stable key

**Files:**
- Create: `context_map/media_centaur/context_map/finding.ex`
- Test: covered by the rule tests (Tasks 7–9); add one key test here

- [ ] **Step 1: Write the failing test** — append to `test/context_map/walk_test.exs`'s sibling, a new file:

```elixir
# test/context_map/finding_test.exs
defmodule MediaCentaur.ContextMap.FindingTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Finding

  test "key is rule, schema, field, value, consumer — stable across runs and lines" do
    finding = %Finding{
      rule: "R3", owner: MediaCentaur.Discovery, schema: MediaCentaur.Discovery.TitleIntent, field: :rung, value: :ignored,
      consumer: MediaCentaurWeb.Components.Title.Logic, consumer_context: :web, surfaces: [], anchored?: true,
      file: "lib/media_centaur_web/components/title/logic.ex", line: 189, detail: nil
    }

    assert Finding.key(finding) == "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic"
    assert Finding.key(%{finding | line: 500}) == Finding.key(finding)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/finding_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

```elixir
# context_map/media_centaur/context_map/finding.ex
defmodule MediaCentaur.ContextMap.Finding do
  @moduledoc """
  One crossing the extractor reports. `key/1` is what the verdicts file
  references: rule, schema, field, value, consumer — never the line, so a
  verdict survives an unrelated edit to the consumer file.

  `detail` carries rule-specific facts: for R4 the target schema and
  whether the target context is in the owner's deps; for R1 the kind
  (`:owner_never_reads` or `:foreign_write`).
  """

  @enforce_keys [:rule, :owner, :schema, :field, :consumer, :consumer_context, :file, :line]
  defstruct [:rule, :owner, :schema, :field, :value, :consumer, :consumer_context, :file, :line, :detail, surfaces: [], anchored?: true]

  @type t :: %__MODULE__{
          rule: String.t(),
          owner: module() | nil,
          schema: module(),
          field: atom(),
          value: atom() | nil,
          consumer: module() | nil,
          consumer_context: module() | :web | nil,
          surfaces: [module()],
          anchored?: boolean(),
          file: String.t(),
          line: pos_integer(),
          detail: map() | nil
        }

  @spec key(t()) :: String.t()
  def key(%__MODULE__{} = finding) do
    [finding.rule, inspect(finding.schema), finding.field, finding.value || "", consumer_key(finding)]
    |> Enum.map_join("|", &to_string/1)
  end

  defp consumer_key(%{rule: "R4", detail: %{target: target}}), do: inspect(target)
  defp consumer_key(%{rule: "R4", detail: %{unresolved: true}}), do: "unresolved"
  defp consumer_key(%{rule: "R1", detail: %{kind: kind}, consumer_context: context}), do: "#{kind}:#{inspect(context)}"
  defp consumer_key(%{consumer: consumer}), do: inspect(consumer)
end
```

- [ ] **Step 4: Run the test**

Run: `agent-mix test test/context_map/finding_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add context_map test/context_map/finding_test.exs
git commit -m "feat(context_map): Finding struct with stable verdict key"
```

---

### Task 7: Rule R3 — reinterpretation

**Files:**
- Create: `context_map/media_centaur/context_map/rules/reinterpretation.ex`
- Test: `test/context_map/rules/reinterpretation_test.exs`

Inputs: schemas, sources. For each source whose context is not the owner of a schema with enum fields, every `:value` mention equal to one of that field's values is a finding when *anchored* (the line text contains the field name, or the file references the owning schema module) — or, when unanchored, only if that value belongs to exactly one schema field in the whole app. Schemas owned by a kernel context are skipped (R2). Sources with `context: nil` are skipped.

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/rules/reinterpretation_test.exs
defmodule MediaCentaur.ContextMap.Rules.ReinterpretationTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Rules.Reinterpretation
  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Sources

  @intent %Schema{
    module: MediaCentaur.Discovery.TitleIntent, context: MediaCentaur.Discovery, table: "title_intents",
    fields: [%{name: :rung, type: "Ecto.Enum", values: [:ignored, :list, :follow, :grab]}, %{name: :media_type, type: "Ecto.Enum", values: [:movie, :tv_series]}],
    associations: []
  }
  @item %Schema{
    module: MediaCentaur.ReleaseTracking.Item, context: MediaCentaur.ReleaseTracking, table: "release_tracking_items",
    fields: [%{name: :media_type, type: "Ecto.Enum", values: [:movie, :tv_series]}], associations: []
  }
  @movie %Schema{
    module: MediaCentaur.Library.Movie, context: MediaCentaur.Library, table: "movies",
    fields: [%{name: :kind, type: "Ecto.Enum", values: [:feature, :short]}], associations: []
  }
  @schemas [@intent, @item, @movie]

  defp run(path, code), do: Reinterpretation.findings(@schemas, [Sources.parse(path, code)])

  test "a value matched outside the owner, anchored by the field name on the line" do
    code = "defmodule MediaCentaurWeb.Components.Title.Logic do\n  defp rung_marker(:ignored), do: \"Ignored\"\nend\n"
    assert [%Finding{rule: "R3", owner: MediaCentaur.Discovery, schema: MediaCentaur.Discovery.TitleIntent, field: :rung, value: :ignored, consumer: MediaCentaurWeb.Components.Title.Logic, consumer_context: :web, anchored?: true, line: 2}] =
             run("lib/media_centaur_web/components/title/logic.ex", code)
  end

  test "anchored by a reference to the owning schema module anywhere in the file" do
    code = "defmodule MediaCentaurWeb.Components.Title.TrackingControls do\n  @spec control_form(MediaCentaur.Discovery.TitleIntent.rung()) :: atom\n  def control_form(:ignored), do: :ignored\nend\n"
    assert [%Finding{anchored?: true, line: 3}] = run("lib/media_centaur_web/components/title/tracking_controls.ex", code)
  end

  test "unanchored value is reported only when exactly one field in the app declares it" do
    code = "defmodule MediaCentaur.Activities do\n  def ingest(_), do: :ignored\n  def kind, do: :movie\nend\n"
    findings = run("lib/media_centaur/activities.ex", code)
    assert [%Finding{value: :ignored, anchored?: false}] = findings
  end

  test "the owner interpreting its own value is not a finding" do
    code = "defmodule MediaCentaur.Discovery do\n  def f(%{rung: :ignored}), do: :ok\nend\n"
    assert [] = run("lib/media_centaur/discovery.ex", code)
  end

  test "a kernel-owned value is not a finding" do
    code = "defmodule MediaCentaur.Acquisition do\n  def f(%{kind: :feature}), do: :ok\nend\n"
    assert [] = run("lib/media_centaur/acquisition.ex", code)
  end

  test "a template mention is reported as unanchored unless the line names the field" do
    code = "defmodule MediaCentaurWeb.Components.Title.TrackingControls do\n  def t(assigns) do\n    ~H\"\"\"\n    <p :if={@form == :ignored}>x</p>\n    \"\"\"\n  end\nend\n"
    assert [%Finding{value: :ignored, anchored?: false}] = run("lib/media_centaur_web/components/title/tracking_controls.ex", code)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/rules/reinterpretation_test.exs`
Expected: FAIL, `Reinterpretation` undefined.

- [ ] **Step 3: Implement**

```elixir
# context_map/media_centaur/context_map/rules/reinterpretation.ex
defmodule MediaCentaur.ContextMap.Rules.Reinterpretation do
  @moduledoc """
  R3 — a context never interprets another context's values.

  For every `Ecto.Enum` field of a non-kernel schema, each bare literal of
  one of its values in a file outside the owning context is a finding.
  *Anchored* when the line names the field or the file references the
  owning schema module; otherwise reported only when that value is
  declared by exactly one schema field in the whole application, so a
  vocabulary shared by many schemas (`:movie`) does not flood the map.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Schemas
  alias MediaCentaur.ContextMap.Source
  alias MediaCentaur.ContextMap.Walk

  @spec findings([Schemas.Schema.t()], [Source.t()]) :: [Finding.t()]
  def findings(schemas, sources) do
    owners = Schemas.value_owners(schemas)
    enum_fields = for schema <- schemas, not Contexts.kernel?(schema.context), %{values: values} = field when is_list(values) <- schema.fields, do: {schema, field}

    for %Source{context: context} = source when not is_nil(context) <- sources,
        mention <- Walk.mentions(source),
        mention.kind == :value,
        {schema, field} <- enum_fields,
        schema.context != context,
        mention.atom in field.values,
        anchored?(source, mention, schema, field) or length(owners[mention.atom]) == 1 do
      %Finding{
        rule: "R3",
        owner: schema.context,
        schema: schema.module,
        field: field.name,
        value: mention.atom,
        consumer: List.first(source.modules),
        consumer_context: context,
        anchored?: anchored?(source, mention, schema, field),
        file: source.path,
        line: mention.line
      }
    end
    |> Enum.uniq_by(&{Finding.key(&1), &1.line})
  end

  defp anchored?(source, mention, schema, field) do
    line_text = Enum.at(source.lines, mention.line - 1, "")
    String.contains?(line_text, Atom.to_string(field.name)) or MapSet.member?(source.references, schema.module)
  end
end
```

- [ ] **Step 4: Run the test**

Run: `agent-mix test test/context_map/rules/reinterpretation_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add context_map test/context_map/rules/reinterpretation_test.exs
git commit -m "feat(context_map): R3 reinterpretation rule"
```

---

### Task 8: Rule R4 — cross-context keys, and kernel reads

**Files:**
- Create: `context_map/media_centaur/context_map/rules/cross_context_key.ex`
- Test: `test/context_map/rules/cross_context_key_test.exs`

Inputs: schemas, contexts. Associations resolve directly. A field named `<stem>_id` or `<stem>_ids` with no association resolves to the schema whose module's last segment underscored equals `stem`, or whose table singularised (strip a trailing `s`) equals `stem`. Polymorphic pairs (`<stem>_type` enum beside `<stem>_id`) resolve each discriminator value the same way. External identifiers are kernel references, not keys. Output is `{findings, kernel_reads}`: a resolved key into a kernel context goes to `kernel_reads`; into any other context is a finding with `detail.in_deps`; an unresolved key is a finding with `detail.unresolved`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/rules/cross_context_key_test.exs
defmodule MediaCentaur.ContextMap.Rules.CrossContextKeyTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Context
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Rules.CrossContextKey
  alias MediaCentaur.ContextMap.Schema

  @contexts [
    %Context{name: MediaCentaur.Discovery, kernel?: false, deps: [MediaCentaur.Library], exports: []},
    %Context{name: MediaCentaur.Activities, kernel?: false, deps: [MediaCentaur.Discovery], exports: []},
    %Context{name: MediaCentaur.Library, kernel?: true, deps: [], exports: []},
    %Context{name: MediaCentaur.WatchHistory, kernel?: false, deps: [MediaCentaur.Library], exports: []},
    %Context{name: MediaCentaur.ReleaseTracking, kernel?: false, deps: [MediaCentaur.Library], exports: []}
  ]

  @activity %Schema{module: MediaCentaur.Activities.Activity, context: MediaCentaur.Activities, table: "activities", fields: [], associations: []}
  @movie %Schema{module: MediaCentaur.Library.Movie, context: MediaCentaur.Library, table: "movies", fields: [], associations: []}
  @episode %Schema{module: MediaCentaur.Library.Episode, context: MediaCentaur.Library, table: "episodes", fields: [], associations: []}
  @intent %Schema{
    module: MediaCentaur.Discovery.TitleIntent, context: MediaCentaur.Discovery, table: "title_intents",
    fields: [%{name: :tmdb_id, type: ":integer", values: nil}, %{name: :activity_id, type: "Ecto.UUID", values: nil}], associations: []
  }
  @event %Schema{
    module: MediaCentaur.WatchHistory.Event, context: MediaCentaur.WatchHistory, table: "watch_history_events",
    fields: [%{name: :movie_id, type: "Ecto.UUID", values: nil}],
    associations: [%{field: :movie_id, kind: :belongs_to, target: MediaCentaur.Library.Movie, name: :movie}]
  }
  @item %Schema{
    module: MediaCentaur.ReleaseTracking.Item, context: MediaCentaur.ReleaseTracking, table: "release_tracking_items",
    fields: [%{name: :library_container_id, type: "Ecto.UUID", values: nil}], associations: []
  }
  @override %Schema{
    module: MediaCentaur.Library.MediaTrackOverride, context: MediaCentaur.Library, table: "media_track_overrides",
    fields: [%{name: :owner_type, type: "Ecto.Enum", values: [:movie, :episode]}, %{name: :owner_id, type: "Ecto.UUID", values: nil}],
    associations: []
  }
  @schemas [@activity, @movie, @episode, @intent, @event, @item, @override]

  setup do
    {findings, kernel_reads} = CrossContextKey.findings(@schemas, @contexts)
    %{findings: findings, kernel_reads: kernel_reads}
  end

  test "a soft key into a context outside the owner's deps is a finding", %{findings: findings} do
    assert %Finding{rule: "R4", owner: MediaCentaur.Discovery, field: :activity_id, detail: %{target: MediaCentaur.Activities.Activity, in_deps: false}} =
             Enum.find(findings, &(&1.field == :activity_id))
  end

  test "an association into the kernel is a kernel read, not a finding", %{findings: findings, kernel_reads: kernel_reads} do
    refute Enum.find(findings, &(&1.field == :movie_id))
    assert %{schema: MediaCentaur.WatchHistory.Event, field: :movie_id, target: MediaCentaur.Library.Movie} = Enum.find(kernel_reads, &(&1.field == :movie_id))
  end

  test "an unresolvable key is reported as unresolved", %{findings: findings} do
    assert %Finding{detail: %{unresolved: true}} = Enum.find(findings, &(&1.field == :library_container_id))
  end

  test "external identifiers are kernel references", %{findings: findings, kernel_reads: kernel_reads} do
    refute Enum.find(findings, &(&1.field == :tmdb_id))
    assert Enum.find(kernel_reads, &(&1.field == :tmdb_id and &1.target == :external))
  end

  test "a polymorphic key resolves through its discriminator values; same-context targets are not crossings", %{findings: findings, kernel_reads: kernel_reads} do
    refute Enum.find(findings, &(&1.field == :owner_id))
    refute Enum.find(kernel_reads, &(&1.field == :owner_id))
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/rules/cross_context_key_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

```elixir
# context_map/media_centaur/context_map/rules/cross_context_key.ex
defmodule MediaCentaur.ContextMap.Rules.CrossContextKey do
  @moduledoc """
  R4 — keys follow ownership and the dependency direction; R2 — keys into
  the shared kernel are references, not crossings.

  Associations resolve to their target schema. A `<stem>_id` / `<stem>_ids`
  field without an association resolves to the schema whose module's last
  segment (underscored) or whose table (minus a trailing `s`) equals the
  stem; a `<stem>_type` enum beside it resolves each value the same way.
  `tmdb_id`, `imdb_id`, `tvdb_id` and `tmdb_person_id` are external
  identity. A key the resolver cannot place is reported unresolved rather
  than guessed.
  """

  alias MediaCentaur.ContextMap.Context
  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Schema

  @external [:tmdb_id, :imdb_id, :tvdb_id, :tmdb_person_id]

  @type kernel_read :: %{schema: module(), field: atom(), target: module() | :external, owner: module()}

  @spec findings([Schema.t()], [Context.t()]) :: {[Finding.t()], [kernel_read()]}
  def findings(schemas, contexts) do
    deps = Map.new(contexts, &{&1.name, &1.deps})
    by_stem = stems(schemas)

    schemas
    |> Enum.flat_map(&keys(&1, by_stem))
    |> Enum.reduce({[], []}, fn key, {findings, reads} ->
      case classify(key, deps) do
        :same_context -> {findings, reads}
        {:kernel_read, read} -> {findings, [read | reads]}
        {:finding, finding} -> {[finding | findings], reads}
      end
    end)
    |> then(fn {findings, reads} -> {Enum.sort_by(findings, &Finding.key/1), Enum.sort_by(reads, &{inspect(&1.schema), &1.field, inspect(&1.target)})} end)
  end

  # --- enumerate every key on a schema: {schema, field, target | :external | :unresolved} ---

  defp keys(%Schema{} = schema, by_stem) do
    assoc_fields = MapSet.new(schema.associations, & &1.field)
    discriminators = Map.new(schema.fields, &{&1.name, &1.values})

    from_assocs = for assoc <- schema.associations, do: {schema, assoc.field, assoc.target}

    from_fields =
      for %{name: name} <- schema.fields, not MapSet.member?(assoc_fields, name), stem = stem(name), stem != nil do
        cond do
          name in @external -> [{schema, name, :external}]
          is_list(discriminators[:"#{stem}_type"]) -> for value <- discriminators[:"#{stem}_type"], do: {schema, name, resolve(Atom.to_string(value), by_stem)}
          true -> [{schema, name, resolve(stem, by_stem)}]
        end
      end

    from_assocs ++ List.flatten(from_fields)
  end

  defp stem(name) do
    case Regex.run(~r/^(.+)_ids?$/, Atom.to_string(name)) do
      [_, stem] -> stem
      nil -> nil
    end
  end

  defp stems(schemas) do
    for schema <- schemas, stem <- [module_stem(schema.module), table_stem(schema.table)], stem != nil, reduce: %{} do
      acc -> Map.update(acc, stem, [schema.module], &Enum.uniq([schema.module | &1]))
    end
  end

  defp module_stem(module), do: module |> Module.split() |> List.last() |> Macro.underscore()
  defp table_stem(nil), do: nil
  defp table_stem(table), do: String.replace_suffix(table, "s", "")

  defp resolve(stem, by_stem) do
    case Map.get(by_stem, stem, []) do
      [target] -> target
      _ -> :unresolved
    end
  end

  # --- classify a key by where it points ---

  defp classify({schema, field, :external}, _deps),
    do: {:kernel_read, %{schema: schema.module, field: field, target: :external, owner: schema.context}}

  defp classify({schema, field, :unresolved}, _deps),
    do: {:finding, finding(schema, field, %{unresolved: true})}

  defp classify({schema, field, target}, deps) do
    target_context = Contexts.context_of(target)

    cond do
      target_context == schema.context -> :same_context
      Contexts.kernel?(target_context) -> {:kernel_read, %{schema: schema.module, field: field, target: target, owner: schema.context}}
      true -> {:finding, finding(schema, field, %{target: target, target_context: target_context, in_deps: target_context in Map.get(deps, schema.context, [])})}
    end
  end

  defp finding(schema, field, detail) do
    %Finding{
      rule: "R4",
      owner: schema.context,
      schema: schema.module,
      field: field,
      consumer: nil,
      consumer_context: Map.get(detail, :target_context),
      file: schema.module.module_info(:compile)[:source] |> to_string() |> Path.relative_to_cwd(),
      line: 1,
      detail: detail
    }
  end
end
```

- [ ] **Step 4: Run the test**

Run: `agent-mix test test/context_map/rules/cross_context_key_test.exs`
Expected: PASS. (`module_info(:compile)[:source]` is an absolute charlist path; `Path.relative_to_cwd/1` makes it `lib/...`. For test schemas whose module does not exist, this call fails — the fixture modules above are real app modules, so it does not. Keep it that way in tests.)

- [ ] **Step 5: Commit**

```bash
git add context_map test/context_map/rules/cross_context_key_test.exs
git commit -m "feat(context_map): R4 cross-context keys and kernel reads"
```

---

### Task 9: Rule R1 — foreign fields

**Files:**
- Create: `context_map/media_centaur/context_map/rules/foreign_field.ex`
- Test: `test/context_map/rules/foreign_field_test.exs`

Per schema field, mentions are attributed to contexts. A *read* is a `:dot` mention or a `:key` mention in a pattern. A *write* is a `:key` mention in an expression (an attrs map or keyword), or the field atom inside a `cast/3` permitted list, `put_change/3` or `force_change/3` (seen as a `:value` mention on a line containing `cast(`, `put_change(`, `force_change(` — line text, deterministic). The owning schema module's own file is excluded from the owner's counts. For a field name declared by more than one schema, only files referencing the owning schema module are counted. Finding when the owner (minus the schema file) never reads the field (`:owner_never_reads`), and once per non-owner context that writes it (`:foreign_write`). Kernel-owned schemas are skipped for `:owner_never_reads` (broad fan-out is their design) but not for `:foreign_write`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/rules/foreign_field_test.exs
defmodule MediaCentaur.ContextMap.Rules.ForeignFieldTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Rules.ForeignField
  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Sources

  @intent %Schema{
    module: MediaCentaur.Discovery.TitleIntent, context: MediaCentaur.Discovery, table: "title_intents",
    fields: [
      %{name: :rung, type: "Ecto.Enum", values: [:ignored, :list]},
      %{name: :activity_id, type: "Ecto.UUID", values: nil},
      %{name: :note, type: ":string", values: nil}
    ],
    associations: []
  }
  @activity %Schema{
    module: MediaCentaur.Activities.Activity, context: MediaCentaur.Activities, table: "activities",
    fields: [%{name: :note, type: ":string", values: nil}], associations: []
  }
  @schemas [@intent, @activity]

  @schema_file {"lib/media_centaur/discovery/title_intent.ex",
   "defmodule MediaCentaur.Discovery.TitleIntent do\n  def changeset(i, attrs), do: cast(i, attrs, [:rung, :activity_id, :note])\nend\n"}
  @discovery {"lib/media_centaur/discovery.ex",
   "defmodule MediaCentaur.Discovery do\n  def rungs, do: Repo.all(from(i in TitleIntent, select: {i.tmdb_id, i.rung}))\n  def note(%TitleIntent{note: note}), do: note\nend\n"}
  @activities {"lib/media_centaur/activities.ex",
   "defmodule MediaCentaur.Activities do\n  alias MediaCentaur.Discovery.TitleIntent\n  def link(title, id), do: Discovery.put_rung(title, :list, %{activity_id: id})\n  def own(%Activity{note: note}), do: note\nend\n"}

  defp run(files), do: ForeignField.findings(@schemas, Enum.map(files, fn {path, code} -> Sources.parse(path, code) end))

  test "a field the owner never reads, written from another context, yields both findings" do
    findings = run([@schema_file, @discovery, @activities]) |> Enum.filter(&(&1.field == :activity_id))

    assert Enum.find(findings, &match?(%Finding{rule: "R1", owner: MediaCentaur.Discovery, detail: %{kind: :owner_never_reads}}, &1))
    assert %Finding{detail: %{kind: :foreign_write}, consumer_context: MediaCentaur.Activities, consumer: MediaCentaur.Activities, line: 3} =
             Enum.find(findings, &match?(%{detail: %{kind: :foreign_write}}, &1))
  end

  test "a field the owner reads and nobody else writes is clean" do
    assert [] = run([@schema_file, @discovery, @activities]) |> Enum.filter(&(&1.field == :rung))
  end

  test "a non-distinctive field name counts only files that reference the owning schema" do
    # :note is on both schemas; Activities reads its own Activity.note without referencing TitleIntent — not attributed to TitleIntent.
    findings = run([@schema_file, @discovery, @activities]) |> Enum.filter(&(&1.schema == MediaCentaur.Activities.Activity))
    assert [%Finding{field: :note, detail: %{kind: :owner_never_reads}}] = findings
  end

  test "the usage table reports reads and writes per context" do
    usage = ForeignField.usage(@schemas, Enum.map([@schema_file, @discovery, @activities], fn {path, code} -> Sources.parse(path, code) end))
    assert %{reads: %{MediaCentaur.Discovery => 1}, writes: %{MediaCentaur.Activities => 1}} = usage[{MediaCentaur.Discovery.TitleIntent, :activity_id}]
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/rules/foreign_field_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

```elixir
# context_map/media_centaur/context_map/rules/foreign_field.ex
defmodule MediaCentaur.ContextMap.Rules.ForeignField do
  @moduledoc """
  R1 — each context keeps its own representation; it never adds a field
  to another context's table for its own need.

  Every mention of a field name is attributed to the mentioning file's
  context. A read is a dot access or a key in a pattern; a write is a key
  in an expression (an attrs map), or the field atom on a line that calls
  `cast(`, `put_change(` or `force_change(`. The schema's own file does
  not count for its owner. A field name declared by more than one schema
  counts only files that reference the owning schema module.

  Findings: `:owner_never_reads` (non-kernel schemas only) and one
  `:foreign_write` per non-owner context that writes the field.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Source
  alias MediaCentaur.ContextMap.Walk

  @write_calls ["cast(", "put_change(", "force_change("]

  @type usage :: %{reads: %{(module() | :web) => non_neg_integer()}, writes: %{(module() | :web) => non_neg_integer()}, sites: [{module() | :web, module(), String.t(), pos_integer(), :read | :write}]}

  @doc "Per `{schema_module, field}`: read and write counts by context, and every site."
  @spec usage([Schema.t()], [Source.t()]) :: %{{module(), atom()} => usage()}
  def usage(schemas, sources) do
    declared_by = for schema <- schemas, field <- schema.fields, reduce: %{} do
      acc -> Map.update(acc, field.name, [schema.module], &[schema.module | &1])
    end

    parsed = for source <- sources, source.context != nil, do: {source, Walk.mentions(source)}

    for schema <- schemas, field <- schema.fields, into: %{} do
      sites =
        for {source, mentions} <- parsed,
            source.path != schema_file(schema),
            distinctive?(declared_by, field.name) or MapSet.member?(source.references, schema.module),
            mention <- mentions,
            mention.atom == field.name,
            access = access(mention, source),
            access != nil do
          {source.context, List.first(source.modules), source.path, mention.line, access}
        end

      {{schema.module, field.name},
       %{
         reads: sites |> Enum.filter(&(elem(&1, 4) == :read)) |> Enum.frequencies_by(&elem(&1, 0)),
         writes: sites |> Enum.filter(&(elem(&1, 4) == :write)) |> Enum.frequencies_by(&elem(&1, 0)),
         sites: Enum.sort(sites)
       }}
    end
  end

  @spec findings([Schema.t()], [Source.t()]) :: [Finding.t()]
  def findings(schemas, sources) do
    usage = usage(schemas, sources)

    for schema <- schemas, field <- schema.fields, use = usage[{schema.module, field.name}] do
      never_read =
        if not Contexts.kernel?(schema.context) and Map.get(use.reads, schema.context, 0) == 0 do
          [finding(schema, field, schema.context, nil, schema_file(schema), 1, %{kind: :owner_never_reads})]
        else
          []
        end

      foreign_writes =
        for {context, module, path, line, :write} <- use.sites, context != schema.context, uniq: true do
          {context, module, path, line}
        end
        |> Enum.uniq_by(&elem(&1, 0))
        |> Enum.map(fn {context, module, path, line} -> finding(schema, field, context, module, path, line, %{kind: :foreign_write}) end)

      never_read ++ foreign_writes
    end
    |> List.flatten()
    |> Enum.sort_by(&Finding.key/1)
  end

  defp access(%{kind: :dot}, _source), do: :read
  defp access(%{kind: :key, pattern?: true}, _source), do: :read
  defp access(%{kind: :key, pattern?: false}, _source), do: :write

  defp access(%{kind: :value, line: line}, source) do
    text = Enum.at(source.lines, line - 1, "")
    if Enum.any?(@write_calls, &String.contains?(text, &1)), do: :write
  end

  defp distinctive?(declared_by, name), do: length(Map.get(declared_by, name, [])) == 1

  defp schema_file(%Schema{module: module}),
    do: module.module_info(:compile)[:source] |> to_string() |> Path.relative_to_cwd()

  defp finding(schema, field, context, module, path, line, detail) do
    %Finding{
      rule: "R1",
      owner: schema.context,
      schema: schema.module,
      field: field.name,
      consumer: module,
      consumer_context: context,
      file: path,
      line: line,
      detail: detail
    }
  end
end
```

- [ ] **Step 4: Run the test**

Run: `agent-mix test test/context_map/rules/foreign_field_test.exs`
Expected: PASS. Note the schema file is identified from the compiled module's source path, so the test's `@schema_file` path must equal `lib/media_centaur/discovery/title_intent.ex` relative to the repo root (it does).

- [ ] **Step 5: Commit**

```bash
git add context_map test/context_map/rules/foreign_field_test.exs
git commit -m "feat(context_map): R1 foreign-field rule with per-context usage"
```

---

### Task 10: Surfaces — component to LiveView

**Files:**
- Create: `context_map/media_centaur/context_map/surfaces.ex`
- Test: `test/context_map/surfaces_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/surfaces_test.exs
defmodule MediaCentaur.ContextMap.SurfacesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Sources
  alias MediaCentaur.ContextMap.Surfaces

  @files [
    {"lib/media_centaur_web/live/incoming_live.ex", "defmodule MediaCentaurWeb.IncomingLive do\n  use MediaCentaurWeb, :live_view\n  alias MediaCentaurWeb.Components.Acquisition.MediaResults\n  def r, do: MediaResults.list()\nend\n"},
    {"lib/media_centaur_web/components/acquisition/media_results.ex", "defmodule MediaCentaurWeb.Components.Acquisition.MediaResults do\n  alias MediaCentaurWeb.Components.Title.Logic\n  def list, do: Logic.marker(nil)\nend\n"},
    {"lib/media_centaur_web/components/title/logic.ex", "defmodule MediaCentaurWeb.Components.Title.Logic do\n  def marker(_), do: nil\nend\n"},
    {"lib/media_centaur_web/live/other_live.ex", "defmodule MediaCentaurWeb.OtherLive do\n  use MediaCentaurWeb, :live_view\nend\n"}
  ]

  test "a component's surfaces are the live views that reach it transitively" do
    sources = Enum.map(@files, fn {path, code} -> Sources.parse(path, code) end)
    surfaces = Surfaces.index(sources)

    assert surfaces[MediaCentaurWeb.Components.Title.Logic] == [MediaCentaurWeb.IncomingLive]
    assert surfaces[MediaCentaurWeb.Components.Acquisition.MediaResults] == [MediaCentaurWeb.IncomingLive]
    assert surfaces[MediaCentaurWeb.IncomingLive] == [MediaCentaurWeb.IncomingLive]
    assert surfaces[MediaCentaurWeb.OtherLive] == [MediaCentaurWeb.OtherLive]
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/surfaces_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

```elixir
# context_map/media_centaur/context_map/surfaces.ex
defmodule MediaCentaur.ContextMap.Surfaces do
  @moduledoc """
  For each web module, the LiveViews that reach it through module
  references, transitively. A component is a consumer; the LiveViews are
  where the consumer's behaviour is seen. Built from `Source.references`
  within `lib/media_centaur_web` only.
  """

  alias MediaCentaur.ContextMap.Source

  @spec index([Source.t()]) :: %{module() => [module()]}
  def index(sources) do
    web = Enum.filter(sources, &(&1.context == :web))
    live_views = for %Source{live_view?: true, modules: [live_view | _]} <- web, do: live_view

    reverse =
      for source <- web, from <- source.modules, to <- source.references, from != to, reduce: %{} do
        acc -> Map.update(acc, to, [from], &[from | &1])
      end

    modules = Enum.flat_map(web, & &1.modules)

    Map.new(modules, fn module -> {module, module |> reachers(reverse) |> Enum.filter(&(&1 in live_views)) |> Enum.sort_by(&inspect/1)} end)
  end

  defp reachers(module, reverse), do: reachers([module], reverse, MapSet.new([module])) |> MapSet.to_list()

  defp reachers([], _reverse, seen), do: seen

  defp reachers([module | rest], reverse, seen) do
    new = reverse |> Map.get(module, []) |> Enum.reject(&MapSet.member?(seen, &1))
    reachers(rest ++ new, reverse, Enum.into(new, seen))
  end
end
```

- [ ] **Step 4: Run the test**

Run: `agent-mix test test/context_map/surfaces_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add context_map test/context_map/surfaces_test.exs
git commit -m "feat(context_map): surfaces — live views reaching each web module"
```

---

### Task 11: Report — assemble, sort, serialise, verdicts

**Files:**
- Create: `context_map/media_centaur/context_map/report.ex`
- Modify: `context_map/media_centaur/context_map.ex` (real `build/0`)
- Test: `test/context_map/report_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/report_test.exs
defmodule MediaCentaur.ContextMap.ReportTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Report

  @finding %Finding{
    rule: "R3", owner: MediaCentaur.Discovery, schema: MediaCentaur.Discovery.TitleIntent, field: :rung, value: :ignored,
    consumer: MediaCentaurWeb.Components.Title.Logic, consumer_context: :web, surfaces: [MediaCentaurWeb.IncomingLive],
    anchored?: true, file: "lib/media_centaur_web/components/title/logic.ex", line: 189, detail: nil
  }

  test "a finding serialises with its key, module names as strings, and verdict fields" do
    [encoded] = Report.encode_findings([@finding], %{Finding.key(@finding) => %{"verdict" => "leak", "reason" => "search marker"}})

    assert encoded == %{
             key: "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic",
             rule: "R3", owner: "MediaCentaur.Discovery", schema: "MediaCentaur.Discovery.TitleIntent", field: "rung", value: "ignored",
             consumer: "MediaCentaurWeb.Components.Title.Logic", consumer_context: "web", surfaces: ["MediaCentaurWeb.IncomingLive"],
             anchored: true, file: "lib/media_centaur_web/components/title/logic.ex", line: 189, detail: nil,
             verdict: "leak", reason: "search marker"
           }
  end

  test "check reports unverdicted findings and stale verdicts" do
    assert {:error, %{unverdicted: ["R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic"], stale: ["R9|gone"]}} =
             Report.check([@finding], %{"R9|gone" => %{"verdict" => "allowed", "reason" => "x"}})

    assert :ok = Report.check([@finding], %{Finding.key(@finding) => %{"verdict" => "leak", "reason" => "y"}})
  end

  test "verdicts file parses into a map by key and rejects an unknown verdict" do
    assert %{"R3|a" => %{"verdict" => "leak", "reason" => "r"}} = Report.parse_verdicts(~s([{"key": "R3|a", "verdict": "leak", "reason": "r"}]))
    assert_raise ArgumentError, ~r/rule wrong/, fn -> Report.parse_verdicts(~s([{"key": "R3|a", "verdict": "rule wrong", "reason": "r"}])) end
  end

  test "the full document is deterministic" do
    assert MediaCentaur.ContextMap.build() == MediaCentaur.ContextMap.build()
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/report_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement Report**

```elixir
# context_map/media_centaur/context_map/report.ex
defmodule MediaCentaur.ContextMap.Report do
  @moduledoc """
  Assembles the document, joins findings with verdicts and checks them.

  Verdicts live in `docs/context-map/verdicts.json` as a list of
  `{"key", "verdict", "reason"}`; `verdict` is `leak` or `allowed`. A
  *rule wrong* verdict is never stored — it changes the rule (spec § 7).
  `check/2` fails on a finding without a verdict or a verdict without a
  finding, so every new crossing lands with its line in the same change.
  """

  alias MediaCentaur.ContextMap.Finding

  @verdicts ["leak", "allowed"]

  @spec encode_findings([Finding.t()], %{String.t() => map()}) :: [map()]
  def encode_findings(findings, verdicts) do
    for finding <- findings do
      key = Finding.key(finding)
      verdict = Map.get(verdicts, key, %{})

      %{
        key: key,
        rule: finding.rule,
        owner: name(finding.owner),
        schema: name(finding.schema),
        field: name(finding.field),
        value: name(finding.value),
        consumer: name(finding.consumer),
        consumer_context: name(finding.consumer_context),
        surfaces: Enum.map(finding.surfaces, &name/1),
        anchored: finding.anchored?,
        file: finding.file,
        line: finding.line,
        detail: finding.detail && Map.new(finding.detail, fn {k, v} -> {k, name(v)} end),
        verdict: verdict["verdict"],
        reason: verdict["reason"]
      }
    end
  end

  @spec check([Finding.t()], %{String.t() => map()}) :: :ok | {:error, %{unverdicted: [String.t()], stale: [String.t()]}}
  def check(findings, verdicts) do
    keys = MapSet.new(findings, &Finding.key/1)
    verdict_keys = MapSet.new(Map.keys(verdicts))
    unverdicted = keys |> MapSet.difference(verdict_keys) |> Enum.sort()
    stale = verdict_keys |> MapSet.difference(keys) |> Enum.sort()

    if unverdicted == [] and stale == [], do: :ok, else: {:error, %{unverdicted: unverdicted, stale: stale}}
  end

  @spec parse_verdicts(String.t()) :: %{String.t() => map()}
  def parse_verdicts(json) do
    json
    |> Jason.decode!()
    |> Map.new(fn %{"key" => key, "verdict" => verdict, "reason" => reason} = entry ->
      verdict in @verdicts or raise ArgumentError, "verdict #{inspect(verdict)} for #{key}: only #{inspect(@verdicts)} are stored; \"rule wrong\" changes the rule instead"
      {key, Map.take(entry, ["verdict", "reason"]) |> Map.put("reason", reason)}
    end)
  end

  @spec read_verdicts(String.t()) :: %{String.t() => map()}
  def read_verdicts(path) do
    case File.read(path) do
      {:ok, json} -> parse_verdicts(json)
      {:error, :enoent} -> %{}
    end
  end

  @doc "Module, atom or nil to its JSON name. `:web` stays `\"web\"`."
  @spec name(term()) :: String.t() | nil | term()
  def name(nil), do: nil
  def name(:web), do: "web"
  def name(:external), do: "external"
  def name(module) when is_atom(module), do: if(String.starts_with?(Atom.to_string(module), "Elixir."), do: inspect(module), else: Atom.to_string(module))
  def name(other), do: other
end
```

- [ ] **Step 4: Replace `build/0` in `MediaCentaur.ContextMap`**

```elixir
  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Report
  alias MediaCentaur.ContextMap.Rules
  alias MediaCentaur.ContextMap.Schemas
  alias MediaCentaur.ContextMap.Sources
  alias MediaCentaur.ContextMap.Surfaces

  @verdicts_path "docs/context-map/verdicts.json"

  @doc "Builds the whole document as a map ready for `Jason.encode!/2`. Every list is sorted; nothing in it depends on time or machine."
  @spec build() :: map()
  def build do
    contexts = Contexts.all()
    schemas = Schemas.all()
    sources = Sources.all()
    surfaces = Surfaces.index(sources)
    usage = Rules.ForeignField.usage(schemas, sources)
    verdicts = Report.read_verdicts(@verdicts_path)

    {key_findings, kernel_reads} = Rules.CrossContextKey.findings(schemas, contexts)

    findings =
      (Rules.Reinterpretation.findings(schemas, sources) ++ key_findings ++ Rules.ForeignField.findings(schemas, sources))
      |> Enum.map(&%{&1 | surfaces: Map.get(surfaces, &1.consumer, [])})
      |> Enum.sort_by(&{Finding.key(&1), &1.line})

    %{
      contexts: Enum.map(contexts, &encode_context(&1, schemas, usage)),
      kernel_reads: Enum.map(kernel_reads, &%{owner: Report.name(&1.owner), schema: Report.name(&1.schema), field: Report.name(&1.field), target: Report.name(&1.target)}),
      findings: Report.encode_findings(findings, verdicts)
    }
  end

  @doc "The findings alone, for `--check`."
  @spec findings() :: [Finding.t()]
  def findings do
    schemas = Schemas.all()
    sources = Sources.all()
    {key_findings, _} = Rules.CrossContextKey.findings(schemas, Contexts.all())
    Rules.Reinterpretation.findings(schemas, sources) ++ key_findings ++ Rules.ForeignField.findings(schemas, sources)
  end

  defp encode_context(context, schemas, usage) do
    %{
      name: Report.name(context.name),
      kernel: context.kernel?,
      deps: Enum.map(context.deps, &Report.name/1),
      exports: Enum.map(context.exports, &Report.name/1),
      schemas:
        for schema <- schemas, schema.context == context.name do
          %{
            module: Report.name(schema.module),
            table: schema.table,
            fields:
              for field <- schema.fields do
                use = usage[{schema.module, field.name}]

                %{
                  name: Report.name(field.name),
                  type: field.type,
                  values: field.values && Enum.map(field.values, &Report.name/1),
                  reads: Map.new(use.reads, fn {context, count} -> {Report.name(context), count} end),
                  writes: Map.new(use.writes, fn {context, count} -> {Report.name(context), count} end)
                }
              end,
            associations: Enum.map(schema.associations, &%{field: Report.name(&1.field), kind: Report.name(&1.kind), target: Report.name(&1.target)})
          }
        end
    }
  end
```

Add `alias MediaCentaur.ContextMap.Finding` to the alias block. `Rules.ForeignField` etc. resolve through `alias MediaCentaur.ContextMap.Rules`.

- [ ] **Step 5: Run the test and the whole context_map suite**

Run: `agent-mix test test/context_map`
Expected: PASS. The determinism test runs the real extractor twice; it should take a few seconds, not minutes. If it is slow, `Sources.all/0` is being called more than once per build — it is called once in `build/0` by design.

- [ ] **Step 6: Commit**

```bash
git add context_map test/context_map/report_test.exs
git commit -m "feat(context_map): report assembly, verdict join and check"
```

---

### Task 12: Mix task options — `--json`, `--check`, `--html`

**Files:**
- Modify: `context_map/mix/tasks/context_map.ex`
- Test: `test/mix/tasks/context_map_test.exs`

- [ ] **Step 1: Extend the test**

```elixir
  test "--check fails when a finding has no verdict", %{tmp_dir: tmp_dir} do
    verdicts = Path.join(tmp_dir, "verdicts.json")
    File.write!(verdicts, "[]\n")

    assert_raise Mix.Error, ~r/unverdicted/, fn ->
      capture_io(fn -> Mix.Tasks.ContextMap.run(["--check", "--verdicts", verdicts, "--json", Path.join(tmp_dir, "m.json")]) end)
    end
  end

  test "--html writes a page containing every finding key", %{tmp_dir: tmp_dir} do
    json_path = Path.join(tmp_dir, "context-map.json")
    html_path = Path.join(tmp_dir, "context-map.html")
    capture_io(fn -> Mix.Tasks.ContextMap.run(["--json", json_path, "--html", html_path]) end)

    %{"findings" => findings} = json_path |> File.read!() |> Jason.decode!()
    html = File.read!(html_path)
    assert Enum.all?(findings, &String.contains?(html, &1["key"]))
  end
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `agent-mix test test/mix/tasks/context_map_test.exs`
Expected: the `--check` test fails (no such option); the `--html` test fails (no file).

- [ ] **Step 3: Implement the task body**

```elixir
  @default_json "docs/context-map/context-map.json"
  @default_verdicts "docs/context-map/verdicts.json"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [json: :string, html: :string, check: :boolean, verdicts: :string])
    json_path = Keyword.get(opts, :json, @default_json)
    verdicts = MediaCentaur.ContextMap.Report.read_verdicts(Keyword.get(opts, :verdicts, @default_verdicts))

    document = MediaCentaur.ContextMap.build(verdicts)
    File.mkdir_p!(Path.dirname(json_path))
    File.write!(json_path, Jason.encode!(document, pretty: true) <> "\n")
    Mix.shell().info("context map: #{length(document.findings)} findings → #{json_path}")

    if html_path = opts[:html] do
      File.mkdir_p!(Path.dirname(html_path))
      File.write!(html_path, MediaCentaur.ContextMap.Html.render(document))
      Mix.shell().info("context map: html → #{html_path}")
    end

    if opts[:check] do
      case MediaCentaur.ContextMap.Report.check(MediaCentaur.ContextMap.findings(), verdicts) do
        :ok -> Mix.shell().info("context map: every finding has a verdict")
        {:error, %{unverdicted: unverdicted, stale: stale}} -> Mix.raise("context map check failed\n  unverdicted: #{inspect(unverdicted, pretty: true)}\n  stale: #{inspect(stale, pretty: true)}")
      end
    end
  end
```

Change `MediaCentaur.ContextMap.build/0` to `build/1` taking the verdicts map (drop `@verdicts_path` and `Report.read_verdicts` from it); update `ReportTest`'s determinism test to `build(%{}) == build(%{})`. `Html.render/1` arrives in Task 13; until then the `--html` test stays red — commit after Task 13.

---

### Task 13: HTML rendering

**Files:**
- Create: `context_map/media_centaur/context_map/html.ex`, `context_map/media_centaur/context_map/templates/context_map.html.eex`
- Test: `test/context_map/html_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/context_map/html_test.exs
defmodule MediaCentaur.ContextMap.HtmlTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Html

  @document %{
    contexts: [
      %{name: "MediaCentaur.Discovery", kernel: false, deps: ["MediaCentaur.Library"], exports: ["MediaCentaur.Discovery.TitleIntent"],
        schemas: [%{module: "MediaCentaur.Discovery.TitleIntent", table: "title_intents",
                    fields: [%{name: "rung", type: "Ecto.Enum", values: ["ignored", "list"], reads: %{"MediaCentaur.Discovery" => 2, "web" => 3}, writes: %{"MediaCentaur.Discovery" => 1}}],
                    associations: []}]},
      %{name: "MediaCentaur.Library", kernel: true, deps: [], exports: [], schemas: []}
    ],
    kernel_reads: [%{owner: "MediaCentaur.Discovery", schema: "MediaCentaur.Discovery.TitleIntent", field: "tmdb_id", target: "external"}],
    findings: [
      %{key: "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic", rule: "R3", owner: "MediaCentaur.Discovery",
        schema: "MediaCentaur.Discovery.TitleIntent", field: "rung", value: "ignored", consumer: "MediaCentaurWeb.Components.Title.Logic",
        consumer_context: "web", surfaces: ["MediaCentaurWeb.IncomingLive"], anchored: true, file: "lib/x.ex", line: 189, detail: nil, verdict: nil, reason: nil}
    ]
  }

  test "renders matrix, panels and findings with the finding key, and escapes" do
    html = Html.render(@document)

    assert html =~ "<title>Context map</title>"
    assert html =~ "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic"
    assert html =~ "title_intents"
    assert html =~ "MediaCentaurWeb.IncomingLive"
    assert html =~ "data-cell=\"MediaCentaur.Discovery→web\""
    refute html =~ "<script src="
  end

  test "escapes reasons" do
    finding = Map.merge(hd(@document.findings), %{verdict: "leak", reason: "<b>x</b>"})
    html = Html.render(%{@document | findings: [finding]})
    assert html =~ "&lt;b&gt;x&lt;/b&gt;"
    refute html =~ "<b>x</b>"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `agent-mix test test/context_map/html_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the renderer**

```elixir
# context_map/media_centaur/context_map/html.ex
defmodule MediaCentaur.ContextMap.Html do
  @moduledoc """
  Renders the document as one self-contained page: the context matrix,
  one panel per context with its schemas and fields, and the findings
  list. No external scripts or styles; filtering is a few lines of inline
  JS over `data-` attributes. Every value is HTML-escaped.
  """

  require EEx

  @template Path.join(__DIR__, "templates/context_map.html.eex")
  @external_resource @template

  EEx.function_from_file(:defp, :page, @template, [:assigns])

  @spec render(map()) :: String.t()
  def render(document) do
    consumers = consumers(document)
    matrix = matrix(document, consumers)
    page(%{document: document, consumers: consumers, matrix: matrix})
  end

  @doc false
  def h(value), do: value |> to_string() |> Plug.HTML.html_escape()

  defp consumers(document) do
    from_findings = for f <- document.findings, c = f.consumer_context, c != nil, do: c
    (Enum.map(document.contexts, & &1.name) ++ from_findings ++ ["web"]) |> Enum.uniq() |> Enum.sort()
  end

  # owner → consumer → %{rule => count}
  defp matrix(document, consumers) do
    for owner <- Enum.map(document.contexts, & &1.name), into: %{} do
      row =
        for consumer <- consumers, into: %{} do
          counts = document.findings |> Enum.filter(&(&1.owner == owner and (&1.consumer_context || "unresolved") == consumer)) |> Enum.frequencies_by(& &1.rule)
          {consumer, counts}
        end

      {owner, row}
    end
  end
end
```

```eex
<%# context_map/media_centaur/context_map/templates/context_map.html.eex %>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Context map</title>
<style>
  :root { --bg: #f7f7f5; --fg: #1a1a1a; --muted: #6b6b66; --line: #d9d9d4; --panel: #ffffff; --accent: #2a5db0; --r1: #b35c00; --r3: #a0203a; --r4: #3c6e2f; --kernel: #e9eef6; }
  @media (prefers-color-scheme: dark) { :root { --bg: #15161a; --fg: #e8e8e4; --muted: #9a9a94; --line: #2c2d33; --panel: #1d1e24; --accent: #7aa2e8; --r1: #e6a15c; --r3: #ef7f98; --r4: #8cc77a; --kernel: #1f2a3a; } }
  body { margin: 0; padding: 24px 16px; background: var(--bg); color: var(--fg); font: 14px/1.45 system-ui, sans-serif; }
  h1, h2, h3 { font-weight: 600; margin: 0 0 8px; } h1 { font-size: 22px; } h2 { font-size: 17px; margin-top: 32px; } h3 { font-size: 15px; }
  table { border-collapse: collapse; } th, td { border: 1px solid var(--line); padding: 4px 8px; text-align: left; vertical-align: top; }
  th { color: var(--muted); font-weight: 500; } td.diag { background: var(--line); color: var(--muted); } td.kernel { background: var(--kernel); }
  .matrix-wrap { overflow-x: auto; } .matrix th.rot { writing-mode: vertical-rl; transform: rotate(180deg); white-space: nowrap; }
  .count { display: inline-block; min-width: 1.4em; padding: 0 4px; border-radius: 3px; color: #fff; font-size: 12px; margin-right: 2px; }
  .R1 { background: var(--r1); } .R3 { background: var(--r3); } .R4 { background: var(--r4); }
  .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 6px; padding: 12px 16px; margin: 12px 0; }
  .panel.kernel { border-color: var(--accent); } .schema { margin: 8px 0 16px; } .mono { font-family: ui-monospace, monospace; font-size: 12.5px; }
  .muted { color: var(--muted); } .chip { display: inline-block; padding: 0 6px; border-radius: 3px; font-size: 12px; color: #fff; margin-left: 4px; }
  .finding { border-top: 1px solid var(--line); padding: 8px 0; } .finding.unverdicted { border-left: 3px solid var(--accent); padding-left: 8px; }
  .filters { display: flex; gap: 12px; flex-wrap: wrap; margin: 8px 0 16px; } .filters label { display: flex; gap: 4px; align-items: center; }
  .hidden { display: none; }
</style>
</head>
<body>
<h1>Context map</h1>
<p class="muted">Schemas by bounded context and every crossing of a boundary at the data level. R1 foreign field · R3 reinterpretation · R4 cross-context key. Shaded cells are shared-kernel reads. Spec: <span class="mono">docs/superpowers/specs/2026-09-30-context-map-design.md</span>.</p>

<h2>Context matrix</h2>
<p class="muted">Rows own the representation; columns interpret, key into, or write it.</p>
<div class="matrix-wrap"><table class="matrix">
<tr><th>owner ↓ / consumer →</th><%= for consumer <- @consumers do %><th class="rot"><%= h(consumer) %></th><% end %></tr>
<%= for context <- @document.contexts do %>
<tr><th><%= h(context.name) %><%= if context.kernel do %> <span class="muted">(kernel)</span><% end %></th>
<%= for consumer <- @consumers do %>
<% counts = @matrix[context.name][consumer] %>
<td class="<%= if consumer == context.name, do: "diag" %>" data-cell="<%= h(context.name) %>→<%= h(consumer) %>">
<%= for {rule, count} <- Enum.sort(counts) do %><span class="count <%= rule %>" title="<%= rule %>"><%= count %></span><% end %>
</td>
<% end %>
</tr>
<% end %>
</table></div>

<h2>Entities</h2>
<%= for context <- @document.contexts do %>
<div class="panel <%= if context.kernel, do: "kernel" %>">
<h3><%= h(context.name) %><%= if context.kernel do %> <span class="muted">shared kernel</span><% end %></h3>
<p class="muted mono">deps: <%= Enum.map_join(context.deps, ", ", &h/1) %></p>
<%= if context.schemas == [] do %><p class="muted">no schemas</p><% end %>
<%= for schema <- context.schemas do %>
<div class="schema">
<div><span class="mono"><%= h(schema.module) %></span> <span class="muted mono"><%= h(schema.table) %></span>
<%= if schema.module in context.exports do %><span class="chip" style="background: var(--accent)">exported</span><% end %></div>
<table>
<tr><th>field</th><th>type</th><th>reads</th><th>writes</th><th>findings</th></tr>
<%= for field <- schema.fields do %>
<% field_findings = Enum.filter(@document.findings, &(&1.schema == schema.module and &1.field == field.name)) %>
<tr>
<td class="mono"><%= h(field.name) %><%= if field.values do %><br><span class="muted"><%= Enum.map_join(field.values, " · ", &h/1) %></span><% end %></td>
<td class="mono muted"><%= h(field.type) %></td>
<td class="mono"><%= Enum.map_join(Enum.sort(field.reads), ", ", fn {c, n} -> "#{h(c)} #{n}" end) %></td>
<td class="mono"><%= Enum.map_join(Enum.sort(field.writes), ", ", fn {c, n} -> "#{h(c)} #{n}" end) %></td>
<td><%= for f <- field_findings do %><span class="chip <%= f.rule %>" title="<%= h(f.key) %>"><%= f.rule %><%= if f.value do %> <%= h(f.value) %><% end %> ← <%= h(f.consumer || f.consumer_context || "unresolved") %></span><% end %></td>
</tr>
<% end %>
<%= for assoc <- schema.associations do %>
<tr><td class="mono"><%= h(assoc.field) %></td><td class="mono muted"><%= h(assoc.kind) %></td><td colspan="3" class="mono">→ <%= h(assoc.target) %></td></tr>
<% end %>
</table>
</div>
<% end %>
</div>
<% end %>

<h2>Findings <span class="muted">(<%= length(@document.findings) %>)</span></h2>
<div class="filters">
<%= for rule <- ["R1", "R3", "R4"] do %><label><input type="checkbox" data-filter-rule="<%= rule %>" checked> <%= rule %></label><% end %>
<label><input type="checkbox" data-filter="unverdicted"> unverdicted only</label>
<label><input type="checkbox" data-filter="anchored"> anchored only</label>
</div>
<%= for f <- Enum.sort_by(@document.findings, &{not is_nil(&1.verdict), &1.key}) do %>
<div class="finding <%= if is_nil(f.verdict), do: "unverdicted" %>" data-rule="<%= f.rule %>" data-verdict="<%= h(f.verdict || "") %>" data-anchored="<%= f.anchored %>">
<div><span class="chip <%= f.rule %>"><%= f.rule %></span> <span class="mono"><%= h(f.schema) %>.<%= h(f.field) %><%= if f.value do %> = <%= h(f.value) %><% end %></span>
<%= if f.consumer do %> ← <span class="mono"><%= h(f.consumer) %></span><% end %>
<%= if f.detail do %><span class="muted mono"> <%= h(inspect(f.detail)) %></span><% end %>
<%= unless f.anchored do %><span class="muted"> candidate</span><% end %></div>
<div class="muted mono"><%= h(f.file) %>:<%= f.line %><%= if f.surfaces != [] do %> · surfaces: <%= Enum.map_join(f.surfaces, ", ", &h/1) %><% end %></div>
<div class="mono muted"><%= h(f.key) %></div>
<%= if f.verdict do %><div><strong><%= h(f.verdict) %></strong> — <%= h(f.reason) %></div><% end %>
</div>
<% end %>

<h2>Kernel reads <span class="muted">(<%= length(@document.kernel_reads) %>)</span></h2>
<table><tr><th>schema</th><th>field</th><th>target</th></tr>
<%= for r <- @document.kernel_reads do %><tr><td class="mono"><%= h(r.schema) %></td><td class="mono"><%= h(r.field) %></td><td class="mono"><%= h(r.target) %></td></tr><% end %>
</table>

<script>
  const boxes = document.querySelectorAll('.filters input');
  function apply() {
    const rules = new Set([...document.querySelectorAll('[data-filter-rule]:checked')].map(b => b.dataset.filterRule));
    const onlyUnverdicted = document.querySelector('[data-filter="unverdicted"]').checked;
    const onlyAnchored = document.querySelector('[data-filter="anchored"]').checked;
    document.querySelectorAll('.finding').forEach(el => {
      const show = rules.has(el.dataset.rule) && (!onlyUnverdicted || el.dataset.verdict === '') && (!onlyAnchored || el.dataset.anchored === 'true');
      el.classList.toggle('hidden', !show);
    });
  }
  boxes.forEach(b => b.addEventListener('change', apply));
</script>
</body>
</html>
```

The template reads `@document`, `@consumers`, `@matrix` from the `assigns` map (EEx's `@` is `assigns.key`). `Plug.HTML.html_escape/1` is available (Plug is a dependency).

- [ ] **Step 4: Run the html test and the mix task test**

Run: `agent-mix test test/context_map/html_test.exs test/mix/tasks/context_map_test.exs`
Expected: PASS for both files.

- [ ] **Step 5: Commit Tasks 12 and 13 together**

```bash
git add context_map test/context_map/html_test.exs test/mix/tasks/context_map_test.exs test/context_map/report_test.exs
git commit -m "feat(context_map): --check, --html and the self-contained page"
```

---

### Task 14: Fixture instances test, first run, spec amendments

**Files:**
- Create: `test/context_map/fixture_instances_test.exs`, `docs/context-map/verdicts.json`, `docs/context-map/context-map.json`
- Modify: `docs/superpowers/specs/2026-09-30-context-map-design.md` (§ 3 R2/R3 limits, § 4 table — dated amendment)

- [ ] **Step 1: Write the fixture test (append-only, ADR-027)**

```elixir
# test/context_map/fixture_instances_test.exs
# POLICY: append-only (ADR-027). Each row is a crossing the extractor must always
# report — the recall floor. A refinement that loses one is rejected.
defmodule MediaCentaur.ContextMap.FixtureInstancesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap
  alias MediaCentaur.ContextMap.Finding

  setup_all do
    %{findings: ContextMap.findings(), document: ContextMap.build(%{})}
  end

  @ignored_consumers [
    MediaCentaurWeb.Components.Title.Logic,
    MediaCentaurWeb.Components.Title.WatchlistToggle,
    MediaCentaurWeb.Components.Title.TrackingControls,
    MediaCentaurWeb.DiscoveryLive.FeedEntries
  ]

  for consumer <- @ignored_consumers do
    test "R3: TitleIntent.rung :ignored interpreted in #{inspect(consumer)}", %{findings: findings} do
      assert Enum.any?(findings, &match?(%Finding{rule: "R3", schema: MediaCentaur.Discovery.TitleIntent, field: :rung, value: :ignored, consumer: unquote(consumer)}, &1))
    end
  end

  test "R3: the Incoming search surface carries the ignored marker", %{findings: findings} do
    logic = Enum.find(findings, &match?(%Finding{rule: "R3", value: :ignored, consumer: MediaCentaurWeb.Components.Title.Logic}, &1))
    assert MediaCentaurWeb.IncomingLive in Map.get(ContextMap.Surfaces.index(ContextMap.Sources.all()), logic.consumer)
  end

  test "R1: TitleIntent.activity_id is never read by Discovery and is written from Activities", %{findings: findings} do
    assert Enum.any?(findings, &match?(%Finding{rule: "R1", schema: MediaCentaur.Discovery.TitleIntent, field: :activity_id, detail: %{kind: :owner_never_reads}}, &1))
    assert Enum.any?(findings, &match?(%Finding{rule: "R1", schema: MediaCentaur.Discovery.TitleIntent, field: :activity_id, detail: %{kind: :foreign_write}, consumer_context: MediaCentaur.Activities}, &1))
  end

  test "R1: TitleIntent.source is written from Activities", %{findings: findings} do
    assert Enum.any?(findings, &match?(%Finding{rule: "R1", schema: MediaCentaur.Discovery.TitleIntent, field: :source, detail: %{kind: :foreign_write}, consumer_context: MediaCentaur.Activities}, &1))
  end

  test "R4: TitleIntent.activity_id keys into Activities, which Discovery does not depend on", %{findings: findings} do
    assert Enum.any?(findings, &match?(%Finding{rule: "R4", schema: MediaCentaur.Discovery.TitleIntent, field: :activity_id, detail: %{target: MediaCentaur.Activities.Activity, in_deps: false}}, &1))
  end

  test "R4: ReleaseTracking.Item.library_container_id is reported unresolved", %{findings: findings} do
    assert Enum.any?(findings, &match?(%Finding{rule: "R4", schema: MediaCentaur.ReleaseTracking.Item, field: :library_container_id, detail: %{unresolved: true}}, &1))
  end

  test "R2: WatchHistory.Event.movie_id is a kernel read", %{document: document} do
    assert Enum.any?(document.kernel_reads, &(&1.schema == "MediaCentaur.WatchHistory.Event" and &1.field == "movie_id"))
  end
end
```

- [ ] **Step 2: Run it**

Run: `agent-mix test test/context_map/fixture_instances_test.exs`
Expected: PASS. Any failing row is a false negative in a signal from Tasks 7–9: fix the signal there (with its own unit test), not the fixture. Where Activities writes `activity_id`: confirm by reading `lib/media_centaur/activities.ex` around the `Discovery.put_rung` call; if the attrs map is built in a helper whose keys are variables, R1 cannot see it — that is a stated limit to record in the spec, and the fixture row changes to the file that does hold the literal key.

- [ ] **Step 3: First run and commit the generated document**

```bash
agent-mix context_map --html tmp/context-map.html
echo '[]' > docs/context-map/verdicts.json
```

Open `tmp/context-map.html` with `subl` for the user. Commit `docs/context-map/context-map.json` and the empty verdicts file.

- [ ] **Step 4: Amend the spec** — append under § 3 R3 *Limits*: "2026-10-01: an unanchored value is reported only when exactly one schema field in the application declares it (`Schemas.value_owners/1`); a vocabulary shared by several schemas (`:movie`) is reported only when anchored." Under § 3 R2 *Signal*: "2026-10-01: 'owner' here means the referenced side — the schema whose value is interpreted (R3) or the key's target (R4)." In § 4 replace the R2 row with `WatchHistory.Event.movie_id → Library.Movie | expected in kernel_reads` and add `R4 | Release Tracking | Item.library_container_id | reported unresolved; expected verdict allowed, reason "kernel container id"`. Section 5's example output stands.

- [ ] **Step 5: Contributor doc and docs map**

Create `docs/context-map.md`:

```markdown
# Context map

`mix context_map` generates `docs/context-map/context-map.json` — every Ecto
schema by owning bounded context, and every crossing of a context boundary
at the data level — and, with `--html PATH`, a self-contained page.

Rules and signals: `docs/superpowers/specs/2026-09-30-context-map-design.md` § 3.
Verdicts: `docs/context-map/verdicts.json`, one `{key, verdict, reason}` per
finding, `verdict` ∈ `leak | allowed`. A *rule wrong* judgment changes the
rule, never the file. `mix context_map --check` fails on a finding without a
verdict or a verdict without a finding; it joins `mix precommit` once the
calibration loop (spec § 7) reaches stability.

    mix context_map --html tmp/context-map.html   # regenerate and view
    mix context_map --check                       # every finding has a verdict?
```

Add a row to the docs map in `CLAUDE.md`: `| Context map (schemas by context, boundary crossings, verdicts) | [docs/context-map.md](docs/context-map.md) |`.

- [ ] **Step 6: Precommit and commit**

Run: `agent-mix precommit`
Expected: clean. Credo now covers `context_map/`; fix anything it reports (predicate naming, no abbreviations, specs).

```bash
git add test/context_map/fixture_instances_test.exs docs/context-map docs/context-map.md docs/superpowers/specs/2026-09-30-context-map-design.md CLAUDE.md
git commit -m "feat(context_map): fixture instances, first generated map, contributor doc"
```

---

### Task 15: Hand-off to calibration

Not code. After Task 14 the loop in spec § 7 starts: the user reads `tmp/context-map.html`, gives verdicts in `docs/context-map/verdicts.json`, and every *rule wrong* judgment comes back as a change to a rule module with its unit test, then a rerun. `--check` joins `mix precommit` only when § 7's stability condition holds; that is a one-line change to the `precommit` alias in `mix.exs` (`"context_map --check"` after `"boundaries"`), made in its own commit with the ADR that records the rule.

---

## Self-review

**Spec coverage.** § 1 glossary — moduledocs use the terms. § 3 R1 → Task 9; R2 → Tasks 8 and 7 (kernel skip); R3 → Task 7; R4 → Task 8; G1 — no signal, documented. § 4 → Task 14. § 5 extractor inputs: Boundary → Task 2; Ecto → Task 3; Sourceror → Tasks 4–5; surfaces → Task 10; output shape → Task 11 (keys, sorting, no timestamps); structure (one module per input and rule, Report, task as entry point) → file structure. § 6 HTML (matrix, panels, findings, no external scripts) → Task 13. § 7 verdicts file, check, rule-wrong never stored → Tasks 11–12, 15. § 8 → Task 15 and explicitly out of scope. § 9 testing: signals per rule, fixtures, determinism, verdict join, renderer contains every key → Tasks 7–9, 14, 11, 12. § 10 kernel membership → `Contexts.@kernel`. The spec's `@type` atom-union fields (R3 signal) are **not** implemented: every fixture enum is `Ecto.Enum`, and no schema in the app declares a string field with an atom-union type; recorded in the Task 14 amendment as a limit.

**Placeholders.** None; every code step has its code. Task 12's `--html` test is red until Task 13 by design and they commit together.

**Type consistency.** `Finding` fields: `rule, owner, schema, field, value, consumer, consumer_context, surfaces, anchored?, file, line, detail` — used identically in Tasks 6–14. `Schema.fields` entries: `%{name, type, values}`; associations `%{field, kind, target, name}` — Task 3 produces, Tasks 8–9 consume. `Walk.mentions/1` → `%{kind, atom, line, pattern?, template?}` — Tasks 5, 7, 9. `ContextMap.build/1` takes the verdicts map after Task 12; `findings/0` is separate. `Report.name/1` is the one module-to-string function.
