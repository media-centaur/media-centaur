# Writing Viewer JavaScript

Visualizer views use a specific JS architecture: no bundler, no ES module imports between files. Files are concatenated in order into a single `<script type="module">` tag.

## Concatenation Pattern

The renderer (`Visualizer.Renderer`) works as follows:

1. Reads the HTML template from `template_path/0`
2. Reads each JS file from `js_sources/0` in order
3. Joins all JS with newlines into a single string
4. Injects the JSON data at `{{DATA}}`
5. Injects the combined JS at `{{SCRIPT}}`

Because all JS lives in one `<script type="module">` scope, variables and functions declared in earlier files are directly accessible in later files. No import/export needed.

## Recommended File Decomposition

```
lib.js          # Pure functions — no DOM, no globals. Testable under Node.js.
data.js         # Read window.__DATA__, build lookup maps and derived data.
layout.js       # Spatial positioning algorithms (coordinates, sizes, grouping).
render.js       # DOM/SVG/Canvas/WebGL creation (optional — some views combine with layout).
interaction.js  # Event handlers, tooltips, keyboard shortcuts, controls.
app.js          # Entry point — wires everything together, kicks off rendering.
```

Not all files are required. The city view omits `render.js` (Three.js scene setup lives in `app.js`). The ERD view includes `render.js` for SVG element creation.

## lib.js Convention

This is the most important convention. `lib.js` must contain **only pure functions**:

- No `document`, `window`, or DOM access
- No framework-specific globals (no `THREE`, no `d3`)
- No side effects
- Testable with `node --test lib.test.js`

Define layout constants, math helpers, and data transformations here. Everything else goes in the other files.

## Testing JS

Tests use Node.js built-in test runner:

```bash
node --test priv/views/myview/js/lib.test.js
```

The test file reads and evaluates `lib.js`, then tests its functions:

```javascript
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const libSource = fs.readFileSync(new URL('./lib.js', import.meta.url), 'utf8');
const lib = new Function(libSource + '\nreturn { myFunction, MY_CONSTANT };')();

describe('myFunction', () => {
  it('does the thing', () => {
    assert.deepStrictEqual(lib.myFunction(input), expected);
  });
});
```

`mix test.all` runs both Elixir tests and all JS tests.

## JSON Schema Contract

The data injected at `{{DATA}}` is a JSON-encoded `%Visualizer.Schema.Analysis{}`:

| Field | JS Type | Description |
|-------|---------|-------------|
| `roots` | `string[]` | Top-level namespace names |
| `modules` | `Array<{id, file, depth, namespace, metrics}>` | All discovered modules |
| `namespaces` | `Array<{id, path, root, modules, children}>` | Namespace hierarchy |
| `dependencies` | `Array<{from, to, count, dep_type, references}>` | Cross-module dependencies |
| `erd_schemas` | `Array<{module_id, table_name, fields, associations}>` | Data model schemas |
| `available_metrics` | `string[]` | Metric keys present in module metrics |

### Key Conventions

- Module `id` is dot-separated: `"MyApp.Accounts.User"`
- Namespace `id` is slash-separated: `"my_app/accounts"`
- Namespace `path` matches the directory structure under `lib/`
- `depth` is 0 for root-level modules, increases with nesting
- `metrics.loc` is lines of code, `metrics.public_functions` is count of `def` functions
- `dep_type` is `"runtime"` or `"compile"`
- `references` contains `{file, line, target_function}` for each reference site

## Reference Implementations

- **City view JS** (`priv/views/city/js/`) — Three.js with importmap, isometric camera, raycaster interaction
- **ERD view JS** (`priv/views/erd/js/`) — pure SVG, no external dependencies, drag-to-pan + scroll-to-zoom
