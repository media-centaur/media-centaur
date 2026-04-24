# Status page error reporting — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Status page's per-file error table with a fingerprint-bucketed summary and add a review-before-send "Report to developer" flow that opens a pre-filled GitHub issue.

**Architecture:** New `MediaCentarr.ErrorReports` bounded context subscribes to the Console PubSub stream, groups `:error`-level entries by a normalized-message fingerprint, and exposes a 1-hour rolling snapshot. StatusLive renders a top-3 summary + header button that opens a LiveComponent modal with a redacted payload preview and a single confirm button. Submission is purely browser-side (`window.open` on a GitHub `/issues/new?title=&body=` URL).

**Tech Stack:** Elixir, Phoenix LiveView, DaisyUI/TailwindCSS, `:crypto.hash/2`, `:persistent_term` (for `Config.get/1`), Phoenix PubSub, Phoenix colocated hooks registered in `assets/js/app.js`.

**Spec:** [`docs/superpowers/specs/2026-04-24-status-error-reporting-design.md`](../specs/2026-04-24-status-error-reporting-design.md)

---

## File structure

**Create:**

| File | Responsibility |
|---|---|
| `lib/media_centarr/error_reports.ex` | Public facade: `list_buckets/0`, `get_bucket/1`, `subscribe/0`. `use Boundary`. |
| `lib/media_centarr/error_reports/bucket.ex` | `%Bucket{}` struct, exported from the boundary. |
| `lib/media_centarr/error_reports/fingerprint.ex` | Pure — `fingerprint/2` returns `%{key, display_title, normalized_message}`. |
| `lib/media_centarr/error_reports/redactor.ex` | Pure — `normalize/1`, `configured_urls/0`. Regex + active-config strip. |
| `lib/media_centarr/error_reports/env_metadata.ex` | Pure — `collect/0` returns app/OTP/Elixir/OS/locale/uptime map. |
| `lib/media_centarr/error_reports/issue_url.ex` | Pure — `build/2` returns `{:ok, url, flags}`; `format_body/2`, `format_title/1`. |
| `lib/media_centarr/error_reports/buckets.ex` | GenServer. Subscribes to `Console`, fingerprints entries, prunes by window, throttled broadcast. |
| `lib/media_centarr_web/live/status_live/report_modal.ex` | LiveComponent. Radio list + preview + confirm. |
| `assets/js/hooks/error_report.js` | One-line hook: handleEvent `open_issue` → `window.open(url, "_blank", "noopener")`. |
| `test/media_centarr/error_reports/fingerprint_test.exs` | Pure tests, `async: true`. |
| `test/media_centarr/error_reports/redactor_test.exs` | Pure tests, `async: true`. |
| `test/media_centarr/error_reports/issue_url_test.exs` | Pure tests, `async: true`. |
| `test/media_centarr/error_reports/env_metadata_test.exs` | Pure tests, `async: true`. |
| `test/media_centarr/error_reports/buckets_test.exs` | GenServer via public API. |
| `test/media_centarr_web/live/status_live/report_modal_test.exs` | LiveView integration test. |

**Modify:**

| File | Change |
|---|---|
| `lib/media_centarr/topics.ex` | Add `def error_reports, do: "error_reports:updates"`. |
| `lib/media_centarr/application.ex` | Add `MediaCentarr.ErrorReports.Buckets` to supervision tree; add `MediaCentarr.ErrorReports` to Boundary `deps`. |
| `lib/media_centarr_web/live/status_live.ex` | Remove `recent_errors_table/1`, remove `recent_errors` assign, subscribe to `ErrorReports.subscribe/0`, render `error_summary_card/1`, mount `ReportModal` on demand. |
| `lib/media_centarr_web/live/status_helpers.ex` | Remove `merge_recent_errors/2`. |
| `lib/media_centarr_web/live.ex` (or wherever LiveView boundary lives) | Add `MediaCentarr.ErrorReports` to LiveView boundary deps. |
| `assets/js/app.js` | Import & register `ErrorReport` hook. |

**Delete (inside existing files):** The `recent_errors_table/1` private component and the `recent_errors` assign references.

---

## Conventions the engineer must follow

- **Use `Log` macros, not `Logger`:** any logging in `lib/media_centarr/error_reports/` must `require MediaCentarr.Log` and call `Log.info(:system, ...)` / `Log.error(:system, ...)`. Direct `Logger` calls fail `mix credo --strict`.
- **Boundary declarations:** every new module under `MediaCentarr.ErrorReports` is part of that context; the facade declares `use Boundary, deps: [...], exports: [...]`. Sub-modules use `use Boundary` only if needed — the facade pattern is sufficient here.
- **`use MediaCentarrWeb, :live_component`** for the modal (existing pattern).
- **Tests:** pure modules are `async: true` and use `MediaCentarr.TestFactory` where helpful. GenServer tests call the public API only (ADR-026) — never `:sys.get_state`, never `GenServer.call/cast` in tests.
- **No HTML-structure assertions.** LiveView tests verify assigns and `push_event` records, not rendered markup.
- **Version control:** this repo uses `jj` (Jujutsu). Do not use raw `git` commands. After each task's commit step, run `jj describe -m "..."` and start the next task's work on top with `jj new` only when the task changes subject (otherwise amend the in-flight change via fresh edits + `jj describe` when the scope becomes clearer).
- **Precommit:** `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit` must be green before any `jj describe` at the end of a task.

---

## Task 1: Add `MediaCentarr.Topics.error_reports/0`

**Files:**
- Modify: `lib/media_centarr/topics.ex`

- [ ] **Step 1: Add the topic constant**

Open `lib/media_centarr/topics.ex`. After the existing `def controls_updates, do: "controls:updates"` line, add:

```elixir
  def error_reports, do: "error_reports:updates"
```

- [ ] **Step 2: Verify compile**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`
Expected: no warnings, clean compile.

- [ ] **Step 3: Commit**

```bash
jj describe -m "feat(error_reports): add topic constant"
jj new
```

---

## Task 2: `MediaCentarr.ErrorReports.Bucket` struct

**Files:**
- Create: `lib/media_centarr/error_reports/bucket.ex`

- [ ] **Step 1: Create the struct module**

```elixir
defmodule MediaCentarr.ErrorReports.Bucket do
  @moduledoc """
  A single error fingerprint bucket held by `MediaCentarr.ErrorReports.Buckets`.

  Buckets are keyed by `fingerprint` — a stable hash of
  `{component, normalized_message}` that groups the same error across files,
  parameters, and users. `count` is the occurrence count inside the retention
  window; `sample_entries` carries up to the last 5 redacted log lines from
  the same bucket for developer context.
  """

  @enforce_keys [
    :fingerprint,
    :component,
    :normalized_message,
    :display_title,
    :count,
    :first_seen,
    :last_seen,
    :sample_entries
  ]
  defstruct [
    :fingerprint,
    :component,
    :normalized_message,
    :display_title,
    :count,
    :first_seen,
    :last_seen,
    :sample_entries
  ]

  @type sample_entry :: %{timestamp: DateTime.t(), message: binary()}

  @type t :: %__MODULE__{
          fingerprint: binary(),
          component: atom(),
          normalized_message: binary(),
          display_title: binary(),
          count: non_neg_integer(),
          first_seen: DateTime.t(),
          last_seen: DateTime.t(),
          sample_entries: [sample_entry()]
        }
end
```

- [ ] **Step 2: Verify compile**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`
Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
jj describe -m "feat(error_reports): add Bucket struct"
jj new
```

---

## Task 3: `MediaCentarr.ErrorReports.Redactor` — regex rules

**Files:**
- Create: `lib/media_centarr/error_reports/redactor.ex`
- Test: `test/media_centarr/error_reports/redactor_test.exs`

- [ ] **Step 1: Write the failing tests for regex rules**

```elixir
defmodule MediaCentarr.ErrorReports.RedactorTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ErrorReports.Redactor

  describe "normalize/1 regex rules" do
    test "redacts absolute paths" do
      assert Redactor.normalize("file not found: /data/media/shows/Show (2020).mkv")
             =~ "<path>"

      refute Redactor.normalize("file not found: /data/media/shows/Show (2020).mkv")
             =~ "/data"
    end

    test "redacts UUIDs" do
      input = "entity 3f9c1a2b-4e5d-6f70-aaaa-bbbbccccdddd failed"
      assert Redactor.normalize(input) =~ "<uuid>"
      refute Redactor.normalize(input) =~ "3f9c1a2b"
    end

    test "redacts UUIDs case-insensitively" do
      input = "ID 3F9C1A2B-4E5D-6F70-AAAA-BBBBCCCCDDDD"
      assert Redactor.normalize(input) =~ "<uuid>"
    end

    test "redacts IPv4 addresses" do
      assert Redactor.normalize("connecting to 192.168.1.42") =~ "<ip>"
      refute Redactor.normalize("connecting to 192.168.1.42") =~ "192.168"
    end

    test "redacts emails" do
      assert Redactor.normalize("user shawn@example.com failed") =~ "<email>"
      refute Redactor.normalize("user shawn@example.com failed") =~ "shawn@"
    end

    test "redacts long digit runs (>=3)" do
      assert Redactor.normalize("returned 429 after 12345 ms") =~ "<N>"
    end

    test "preserves 1-2 digit numbers" do
      # Version numbers, small counts remain legible
      assert Redactor.normalize("retry 1 of 5 failed") =~ "retry 1 of 5"
    end

    test "collapses whitespace and trims" do
      assert Redactor.normalize("  foo   bar  \n baz  ") == "foo bar baz"
    end

    test "applies NFC normalization" do
      nfd = "café"
      nfc = "café"
      assert Redactor.normalize(nfd) == nfc
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centarr/error_reports/redactor_test.exs`
Expected: FAIL with "module MediaCentarr.ErrorReports.Redactor is not available".

- [ ] **Step 3: Write the Redactor module (regex rules only, no active-config strip yet)**

```elixir
defmodule MediaCentarr.ErrorReports.Redactor do
  @moduledoc """
  Strips sensitive and variable substrings from error text so that
  two users hitting the same bug produce the same fingerprint.

  Two passes:

  1. Active-config strip — exact-literal replacement of the TMDB API key
     and every configured external URL (Prowlarr, download client, etc.)
     with `<redacted:api_key>` / `<redacted:url>`. Added in a later task.
  2. Regex substitutions — paths, UUIDs, IPs, emails, long digit runs.

  Unicode-aware; callers can assume input has been NFC-normalized.
  """

  @path_re ~r|(?<![A-Za-z0-9_])/(?:[^\s/"']+/){1,}[^\s/"']*|u
  @uuid_re ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/iu
  @ipv4_re ~r/\b(?:\d{1,3}\.){3}\d{1,3}\b/u
  @email_re ~r/\b[\w.+-]+@[\w.-]+\.\w{2,}\b/u
  @digits_re ~r/\b\d{3,}\b/u
  @ws_re ~r/\s+/u

  @spec normalize(binary()) :: binary()
  def normalize(message) when is_binary(message) do
    message
    |> :unicode.characters_to_nfc_binary()
    |> apply_regex_rules()
    |> collapse_ws()
    |> String.trim()
  end

  defp apply_regex_rules(text) do
    text
    |> Regex.replace(@uuid_re, "<uuid>")
    |> then(&Regex.replace(@path_re, &1, "<path>"))
    |> then(&Regex.replace(@email_re, &1, "<email>"))
    |> then(&Regex.replace(@ipv4_re, &1, "<ip>"))
    |> then(&Regex.replace(@digits_re, &1, "<N>"))
  end

  defp collapse_ws(text), do: Regex.replace(@ws_re, text, " ")
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centarr/error_reports/redactor_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(error_reports): Redactor regex rules"
jj new
```

---

## Task 4: `Redactor` — active-config strip

**Files:**
- Modify: `lib/media_centarr/error_reports/redactor.ex`
- Modify: `test/media_centarr/error_reports/redactor_test.exs`

- [ ] **Step 1: Add the failing tests**

Append inside the top-level `describe` block or a new describe block:

```elixir
  describe "normalize/1 active-config strip" do
    setup do
      # Stub Config values. The real Config is `:persistent_term`-backed,
      # so we overwrite the key for the test and restore it after.
      original = :persistent_term.get({MediaCentarr.Config, :config})

      patched =
        original
        |> Map.put(:tmdb_api_key, MediaCentarr.Secret.wrap("super_secret_abcdef_1234"))
        |> Map.put(:prowlarr_url, "http://prowlarr.local:9696")
        |> Map.put(:download_client_url, "http://qbit.local:8080")

      :persistent_term.put({MediaCentarr.Config, :config}, patched)

      on_exit(fn ->
        :persistent_term.put({MediaCentarr.Config, :config}, original)
      end)

      :ok
    end

    test "redacts the active TMDB API key" do
      input = "TMDB request failed with key=super_secret_abcdef_1234 at endpoint"
      assert Redactor.normalize(input) =~ "<redacted:api_key>"
      refute Redactor.normalize(input) =~ "super_secret_abcdef_1234"
    end

    test "redacts configured Prowlarr URL" do
      input = "GET http://prowlarr.local:9696/api/v1/foo returned 500"
      assert Redactor.normalize(input) =~ "<redacted:url>"
      refute Redactor.normalize(input) =~ "prowlarr.local"
    end

    test "redacts configured download-client URL" do
      input = "POST http://qbit.local:8080/api/v2/torrents/add failed"
      assert Redactor.normalize(input) =~ "<redacted:url>"
    end

    test "no-op on short/missing API key" do
      original = :persistent_term.get({MediaCentarr.Config, :config})
      patched = Map.put(original, :tmdb_api_key, MediaCentarr.Secret.wrap(""))
      :persistent_term.put({MediaCentarr.Config, :config}, patched)

      on_exit(fn -> :persistent_term.put({MediaCentarr.Config, :config}, original) end)

      input = "error contains the literal string a"
      # empty key must not replace every 'a' in the input
      assert Redactor.normalize(input) == "error contains the literal string a"
    end
  end

  describe "configured_urls/0" do
    test "returns the set of non-nil configured external URLs" do
      original = :persistent_term.get({MediaCentarr.Config, :config})

      patched =
        original
        |> Map.put(:prowlarr_url, "http://p")
        |> Map.put(:download_client_url, nil)

      :persistent_term.put({MediaCentarr.Config, :config}, patched)
      on_exit(fn -> :persistent_term.put({MediaCentarr.Config, :config}, original) end)

      urls = Redactor.configured_urls()
      assert "http://p" in urls
      refute Enum.any?(urls, &is_nil/1)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centarr/error_reports/redactor_test.exs`
Expected: FAIL — active-config tests fail because the strip isn't implemented.

- [ ] **Step 3: Implement the strip**

Replace the Redactor module body with:

```elixir
defmodule MediaCentarr.ErrorReports.Redactor do
  @moduledoc """
  Strips sensitive and variable substrings from error text so that
  two users hitting the same bug produce the same fingerprint.

  Two passes:

  1. Active-config strip — exact-literal replacement of the TMDB API key
     and every configured external URL (Prowlarr, download client, etc.)
     with `<redacted:api_key>` / `<redacted:url>`.
  2. Regex substitutions — paths, UUIDs, IPs, emails, long digit runs.

  Unicode-aware; callers can assume input has been NFC-normalized.
  """

  alias MediaCentarr.Config
  alias MediaCentarr.Secret

  @min_secret_len 8

  @configured_url_keys [:prowlarr_url, :download_client_url]

  @path_re ~r|(?<![A-Za-z0-9_])/(?:[^\s/"']+/){1,}[^\s/"']*|u
  @uuid_re ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/iu
  @ipv4_re ~r/\b(?:\d{1,3}\.){3}\d{1,3}\b/u
  @email_re ~r/\b[\w.+-]+@[\w.-]+\.\w{2,}\b/u
  @digits_re ~r/\b\d{3,}\b/u
  @ws_re ~r/\s+/u

  @spec normalize(binary()) :: binary()
  def normalize(message) when is_binary(message) do
    message
    |> :unicode.characters_to_nfc_binary()
    |> strip_active_config()
    |> apply_regex_rules()
    |> collapse_ws()
    |> String.trim()
  end

  @spec configured_urls() :: [binary()]
  def configured_urls do
    @configured_url_keys
    |> Enum.map(&Config.get/1)
    |> Enum.reject(&blank?/1)
  end

  defp strip_active_config(text) do
    text
    |> strip_api_key()
    |> strip_configured_urls()
  end

  defp strip_api_key(text) do
    case Config.get(:tmdb_api_key) do
      %Secret{} = secret ->
        value = Secret.expose(secret)

        if is_binary(value) and byte_size(value) >= @min_secret_len do
          String.replace(text, value, "<redacted:api_key>")
        else
          text
        end

      _ ->
        text
    end
  end

  defp strip_configured_urls(text) do
    Enum.reduce(configured_urls(), text, fn url, acc ->
      String.replace(acc, url, "<redacted:url>")
    end)
  end

  defp apply_regex_rules(text) do
    text
    |> then(&Regex.replace(@uuid_re, &1, "<uuid>"))
    |> then(&Regex.replace(@path_re, &1, "<path>"))
    |> then(&Regex.replace(@email_re, &1, "<email>"))
    |> then(&Regex.replace(@ipv4_re, &1, "<ip>"))
    |> then(&Regex.replace(@digits_re, &1, "<N>"))
  end

  defp collapse_ws(text), do: Regex.replace(@ws_re, text, " ")

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centarr/error_reports/redactor_test.exs`
Expected: all pass (regex + active-config + configured_urls).

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(error_reports): Redactor active-config strip"
jj new
```

---

## Task 5: `MediaCentarr.ErrorReports.Fingerprint`

**Files:**
- Create: `lib/media_centarr/error_reports/fingerprint.ex`
- Test: `test/media_centarr/error_reports/fingerprint_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentarr.ErrorReports.FingerprintTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ErrorReports.Fingerprint

  describe "fingerprint/2" do
    test "returns a 16-char lowercase hex key" do
      %{key: key} = Fingerprint.fingerprint(:tmdb, "request failed")
      assert String.length(key) == 16
      assert key =~ ~r/^[0-9a-f]{16}$/
    end

    test "same component + same normalized message produces the same key" do
      a = Fingerprint.fingerprint(:tmdb, "TMDB returned 429: rate limited (retry after 2s)")
      b = Fingerprint.fingerprint(:tmdb, "TMDB returned 500: rate limited (retry after 9s)")
      # Both normalize to "TMDB returned <N>: rate limited (retry after <N>s)" → same key
      assert a.key == b.key
    end

    test "different error class produces a different key" do
      a = Fingerprint.fingerprint(:tmdb, "TMDB returned 429: rate limited")
      b = Fingerprint.fingerprint(:tmdb, "TMDB returned 500: upstream error")
      refute a.key == b.key
    end

    test "different component produces a different key" do
      a = Fingerprint.fingerprint(:tmdb, "connection refused")
      b = Fingerprint.fingerprint(:watcher, "connection refused")
      refute a.key == b.key
    end

    test "display_title prefixes the component label" do
      %{display_title: title} =
        Fingerprint.fingerprint(:tmdb, "TMDB returned 429: rate limited")

      assert title =~ ~r/^\[TMDB\] /
    end

    test "display_title uses known labels for known components" do
      assert Fingerprint.fingerprint(:library, "foo").display_title =~ ~r/^\[Library\]/
      assert Fingerprint.fingerprint(:pipeline, "foo").display_title =~ ~r/^\[Pipeline\]/
      assert Fingerprint.fingerprint(:watcher, "foo").display_title =~ ~r/^\[Watcher\]/
      assert Fingerprint.fingerprint(:playback, "foo").display_title =~ ~r/^\[Playback\]/
      assert Fingerprint.fingerprint(:phoenix, "foo").display_title =~ ~r/^\[Phoenix\]/
      assert Fingerprint.fingerprint(:ecto, "foo").display_title =~ ~r/^\[Ecto\]/
      assert Fingerprint.fingerprint(:live_view, "foo").display_title =~ ~r/^\[LiveView\]/
      assert Fingerprint.fingerprint(:system, "foo").display_title =~ ~r/^\[System\]/
    end

    test "display_title falls back to capitalized atom for unknown components" do
      assert Fingerprint.fingerprint(:some_new_thing, "foo").display_title =~
               ~r/^\[Some_new_thing\]/
    end

    test "normalized_message reflects Redactor output" do
      %{normalized_message: normalized} =
        Fingerprint.fingerprint(:tmdb, "failed at /data/media/foo.mkv")

      assert normalized =~ "<path>"
    end

    test "display_title truncated to 200 chars" do
      long = String.duplicate("a", 500)
      %{display_title: title} = Fingerprint.fingerprint(:system, long)
      assert String.length(title) <= 200
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centarr/error_reports/fingerprint_test.exs`
Expected: FAIL — module not defined.

- [ ] **Step 3: Implement `Fingerprint`**

```elixir
defmodule MediaCentarr.ErrorReports.Fingerprint do
  @moduledoc """
  Computes a stable fingerprint for an error so that two users hitting
  the same bug produce the same bucket key and the same GitHub issue title.

  `fingerprint/2` returns `%{key, display_title, normalized_message}`:

    - `key` — 16 lowercase hex chars of `sha256(component || 0 || normalized)`.
    - `display_title` — `"[<Component>] <normalized message>"`, truncated to 200.
    - `normalized_message` — `Redactor.normalize/1` output.
  """

  alias MediaCentarr.ErrorReports.Redactor

  @title_limit 200

  @component_labels %{
    tmdb: "TMDB",
    library: "Library",
    pipeline: "Pipeline",
    watcher: "Watcher",
    playback: "Playback",
    phoenix: "Phoenix",
    ecto: "Ecto",
    live_view: "LiveView",
    system: "System"
  }

  @type result :: %{
          key: binary(),
          display_title: binary(),
          normalized_message: binary()
        }

  @spec fingerprint(atom(), binary()) :: result()
  def fingerprint(component, raw_message)
      when is_atom(component) and is_binary(raw_message) do
    normalized = Redactor.normalize(raw_message)
    key = compute_key(component, normalized)
    title = build_title(component, normalized)

    %{key: key, display_title: title, normalized_message: normalized}
  end

  defp compute_key(component, normalized) do
    :crypto.hash(:sha256, [Atom.to_string(component), 0, normalized])
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp build_title(component, normalized) do
    label = component_label(component)

    "[#{label}] #{normalized}"
    |> String.slice(0, @title_limit)
  end

  defp component_label(component) do
    Map.get_lazy(@component_labels, component, fn ->
      component |> Atom.to_string() |> String.capitalize()
    end)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centarr/error_reports/fingerprint_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(error_reports): Fingerprint pure module"
jj new
```

---

## Task 6: `MediaCentarr.ErrorReports.EnvMetadata`

**Files:**
- Create: `lib/media_centarr/error_reports/env_metadata.ex`
- Test: `test/media_centarr/error_reports/env_metadata_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentarr.ErrorReports.EnvMetadataTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ErrorReports.EnvMetadata

  describe "collect/0" do
    test "returns a map with required keys" do
      meta = EnvMetadata.collect()
      assert is_binary(meta.app_version)
      assert is_binary(meta.otp_release)
      assert is_binary(meta.elixir_version)
      assert is_binary(meta.os)
      assert is_binary(meta.locale)
      assert is_binary(meta.uptime)
    end

    test "app_version matches the running app spec" do
      assert EnvMetadata.collect().app_version == to_string(Application.spec(:media_centarr, :vsn))
    end

    test "uptime format is human readable (e.g. '2h 14m')" do
      assert EnvMetadata.collect().uptime =~ ~r/^\d+[dhms]/
    end
  end

  describe "render/1" do
    test "emits a fixed-column text block" do
      rendered =
        EnvMetadata.render(%{
          app_version: "0.21.0",
          otp_release: "27",
          elixir_version: "1.17.0",
          os: "Linux 6.19.12-arch1-1 (x86_64)",
          locale: "en_US.UTF-8",
          uptime: "2h 14m"
        })

      assert rendered =~ "App:"
      assert rendered =~ "0.21.0"
      assert rendered =~ "Erlang:"
      assert rendered =~ "OS:"
      assert rendered =~ "Uptime:"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centarr/error_reports/env_metadata_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement `EnvMetadata`**

```elixir
defmodule MediaCentarr.ErrorReports.EnvMetadata do
  @moduledoc """
  Collects environment fields for an error report — app version,
  Erlang/Elixir, OS, locale, uptime. Pure: no PubSub, no DB.
  """

  @type t :: %{
          app_version: binary(),
          otp_release: binary(),
          elixir_version: binary(),
          os: binary(),
          locale: binary(),
          uptime: binary()
        }

  @spec collect() :: t()
  def collect do
    %{
      app_version: to_string(Application.spec(:media_centarr, :vsn)),
      otp_release: to_string(:erlang.system_info(:otp_release)),
      elixir_version: System.version(),
      os: os_string(),
      locale: System.get_env("LANG") || "unknown",
      uptime: uptime_string()
    }
  end

  @spec render(t()) :: binary()
  def render(%{} = meta) do
    """
    App:     media-centarr #{meta.app_version}
    Erlang:  OTP #{meta.otp_release} / Elixir #{meta.elixir_version}
    OS:      #{meta.os}
    Locale:  #{meta.locale}
    Uptime:  #{meta.uptime}
    """
    |> String.trim_trailing()
  end

  defp os_string do
    {family, name} = :os.type()
    version = :os.version() |> format_os_version()
    arch = to_string(:erlang.system_info(:system_architecture))
    "#{family}/#{name} #{version} (#{arch})"
  end

  defp format_os_version({maj, min, patch}), do: "#{maj}.#{min}.#{patch}"
  defp format_os_version(other) when is_binary(other) or is_list(other), do: to_string(other)
  defp format_os_version(_), do: "unknown"

  defp uptime_string do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    seconds = div(uptime_ms, 1_000)

    cond do
      seconds >= 86_400 ->
        "#{div(seconds, 86_400)}d #{div(rem(seconds, 86_400), 3_600)}h"

      seconds >= 3_600 ->
        "#{div(seconds, 3_600)}h #{div(rem(seconds, 3_600), 60)}m"

      seconds >= 60 ->
        "#{div(seconds, 60)}m #{rem(seconds, 60)}s"

      true ->
        "#{seconds}s"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centarr/error_reports/env_metadata_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(error_reports): EnvMetadata collector"
jj new
```

---

## Task 7: `MediaCentarr.ErrorReports.IssueUrl`

**Files:**
- Create: `lib/media_centarr/error_reports/issue_url.ex`
- Test: `test/media_centarr/error_reports/issue_url_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentarr.ErrorReports.IssueUrlTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ErrorReports.{Bucket, IssueUrl}

  defp sample_bucket(overrides \\ %{}) do
    bucket = %Bucket{
      fingerprint: "3f9c1a2b4e5d6f70",
      component: :tmdb,
      normalized_message: "TMDB returned <N>: rate limited (retry after <N>s)",
      display_title: "[TMDB] TMDB returned <N>: rate limited (retry after <N>s)",
      count: 12,
      first_seen: ~U[2026-04-24 13:48:02Z],
      last_seen: ~U[2026-04-24 14:00:19Z],
      sample_entries: []
    }

    Map.merge(bucket, overrides)
    |> then(&struct!(Bucket, Map.from_struct(&1)))
  end

  defp sample_env do
    %{
      app_version: "0.21.0",
      otp_release: "27",
      elixir_version: "1.17.0",
      os: "Linux 6.19.12-arch1-1 (x86_64)",
      locale: "en_US.UTF-8",
      uptime: "2h 14m"
    }
  end

  describe "build/2" do
    test "returns a valid github new-issue URL" do
      {:ok, url, flags} = IssueUrl.build(sample_bucket(), sample_env())
      parsed = URI.parse(url)
      assert parsed.host == "github.com"
      assert parsed.path == "/media-centarr/media-centarr/issues/new"
      assert is_list(flags)
    end

    test "title encodes the display title" do
      {:ok, url, _} = IssueUrl.build(sample_bucket(), sample_env())
      query = URI.parse(url).query |> URI.decode_query()
      assert query["title"] =~ "[TMDB]"
      assert query["title"] =~ "rate limited"
    end

    test "body contains environment + fingerprint + counts" do
      {:ok, url, _} = IssueUrl.build(sample_bucket(), sample_env())
      body = URI.parse(url).query |> URI.decode_query() |> Map.get("body")
      assert body =~ "0.21.0"
      assert body =~ "Fingerprint: 3f9c1a2b4e5d6f70"
      assert body =~ "Count:"
      assert body =~ "12"
    end

    test "drops log-context lines when too long; returns :truncated_log_context flag" do
      many_entries =
        for i <- 1..500 do
          %{timestamp: ~U[2026-04-24 14:00:00Z], message: "error line #{i} " <> String.duplicate("x", 50)}
        end

      bucket = sample_bucket(%{sample_entries: many_entries})
      {:ok, url, flags} = IssueUrl.build(bucket, sample_env())
      assert :truncated_log_context in flags
      assert byte_size(url) <= 7_500
    end

    test "always preserves environment + fingerprint even under extreme pressure" do
      # 100 KB bucket message
      huge = String.duplicate("x", 100_000)
      bucket = sample_bucket(%{normalized_message: huge, display_title: "[TMDB] " <> huge})
      {:ok, url, _flags} = IssueUrl.build(bucket, sample_env())
      body = URI.parse(url).query |> URI.decode_query() |> Map.get("body")
      assert body =~ "0.21.0"
      assert body =~ "Fingerprint:"
      assert byte_size(url) <= 7_500
    end
  end

  describe "format_title/1" do
    test "uses the bucket display_title verbatim, truncated to 140 chars" do
      long_title = "[TMDB] " <> String.duplicate("x", 500)
      bucket = sample_bucket(%{display_title: long_title})
      assert IssueUrl.format_title(bucket) |> String.length() <= 140
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centarr/error_reports/issue_url_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement `IssueUrl`**

```elixir
defmodule MediaCentarr.ErrorReports.IssueUrl do
  @moduledoc """
  Builds a GitHub `new/issue` URL for an `ErrorReports.Bucket`.

  All submission is browser-side: the URL is handed to `window.open`.
  Size-budgeting is load-bearing — browsers typically accept up to about
  8 KB of URL. This module targets ≤ 7,500 bytes and, when over budget,
  drops content in priority order: log context → recurrences detail →
  (never) environment and fingerprint.
  """

  alias MediaCentarr.ErrorReports.{Bucket, EnvMetadata}

  @repo_url "https://github.com/media-centarr/media-centarr"
  @max_url_bytes 7_500
  @title_limit 140

  @type flag :: :truncated_log_context | :truncated_recurrences
  @type build_result :: {:ok, binary(), [flag()]}

  @spec build(Bucket.t(), EnvMetadata.t()) :: build_result()
  def build(%Bucket{} = bucket, %{} = env) do
    title = format_title(bucket)
    build_body(bucket, env, title, length(bucket.sample_entries), [])
  end

  @spec format_title(Bucket.t()) :: binary()
  def format_title(%Bucket{display_title: title}) do
    String.slice(title, 0, @title_limit)
  end

  # Progressive truncation: start with full bucket, then drop log entries
  # one at a time (oldest first) until fit, then drop recurrences detail.
  defp build_body(bucket, env, title, log_limit, flags) do
    sample = Enum.take(bucket.sample_entries, log_limit)
    body = format_body(bucket, env, sample, flags)
    url = encode_url(title, body)

    cond do
      byte_size(url) <= @max_url_bytes ->
        {:ok, url, flags}

      log_limit > 0 ->
        new_flags = if :truncated_log_context in flags, do: flags, else: [:truncated_log_context | flags]
        build_body(bucket, env, title, log_limit - 1, new_flags)

      :truncated_recurrences not in flags ->
        build_body(bucket, env, title, 0, [:truncated_recurrences | flags])

      true ->
        # Last resort: return the smallest possible URL even if > 7_500.
        # Environment + fingerprint are always preserved.
        {:ok, url, flags}
    end
  end

  @spec format_body(Bucket.t(), EnvMetadata.t(), [Bucket.sample_entry()], [flag()]) :: binary()
  def format_body(%Bucket{} = bucket, %{} = env, sample_entries, flags) do
    [
      "## Environment\n",
      EnvMetadata.render(env),
      "\n\n",
      "## Error\n",
      "Fingerprint: ", bucket.fingerprint, "\n",
      "Component:   ", Atom.to_string(bucket.component), "\n",
      recurrences_block(bucket, flags),
      "\nNormalized message:\n\n",
      indent(bucket.normalized_message),
      "\n\n## Recent log context (normalized)\n\n",
      format_samples(sample_entries),
      "\n\n---\nReported via Media Centarr's in-app error reporter.\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp recurrences_block(bucket, flags) do
    if :truncated_recurrences in flags do
      ["Count:       ", Integer.to_string(bucket.count), " (in the last window)\n"]
    else
      [
        "Count:       ", Integer.to_string(bucket.count), " (in the last window)\n",
        "First seen:  ", DateTime.to_iso8601(bucket.first_seen), "\n",
        "Last seen:   ", DateTime.to_iso8601(bucket.last_seen), "\n"
      ]
    end
  end

  defp format_samples([]), do: "(no log context included)\n"

  defp format_samples(entries) do
    Enum.map_join(entries, "\n", fn entry ->
      ts = entry.timestamp |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
      "    #{ts} error " <> entry.message
    end)
  end

  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &("    " <> &1))
  end

  defp encode_url(title, body) do
    qs = URI.encode_query(%{"title" => title, "body" => body})
    @repo_url <> "/issues/new?" <> qs
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/media_centarr/error_reports/issue_url_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(error_reports): IssueUrl builder with size fallback"
jj new
```

---

## Task 8: `MediaCentarr.ErrorReports.Buckets` GenServer

**Files:**
- Create: `lib/media_centarr/error_reports/buckets.ex`
- Create: `lib/media_centarr/error_reports.ex` (facade — minimal at this point)
- Test: `test/media_centarr/error_reports/buckets_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentarr.ErrorReports.BucketsTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Console.Entry
  alias MediaCentarr.ErrorReports.{Bucket, Buckets}
  alias MediaCentarr.Topics

  setup do
    # Use an isolated name so tests don't collide with the app supervisor.
    start_supervised!({Buckets, name: :buckets_test, window_minutes: 60})
    :ok
  end

  defp error_entry(id, component, message, ts \\ DateTime.utc_now()) do
    Entry.new(%{
      id: id,
      timestamp: ts,
      level: :error,
      component: component,
      message: message,
      metadata: %{}
    })
  end

  describe "listing and insertion" do
    test "starts empty" do
      assert Buckets.list_buckets(:buckets_test) == []
    end

    test "records an :error entry into a fingerprinted bucket" do
      Buckets.ingest(:buckets_test, error_entry(1, :tmdb, "TMDB returned 429"))

      [%Bucket{} = bucket] = Buckets.list_buckets(:buckets_test)
      assert bucket.component == :tmdb
      assert bucket.count == 1
      assert bucket.display_title =~ "[TMDB]"
    end

    test "ignores non-error entries" do
      info_entry = %{
        error_entry(1, :tmdb, "TMDB returned 429")
        | level: :info
      }

      Buckets.ingest(:buckets_test, info_entry)
      assert Buckets.list_buckets(:buckets_test) == []
    end

    test "increments the count when the same fingerprint repeats" do
      Buckets.ingest(:buckets_test, error_entry(1, :tmdb, "TMDB returned 429 at 2s"))
      Buckets.ingest(:buckets_test, error_entry(2, :tmdb, "TMDB returned 429 at 5s"))

      [bucket] = Buckets.list_buckets(:buckets_test)
      assert bucket.count == 2
    end

    test "keeps up to 5 sample_entries" do
      for i <- 1..10 do
        Buckets.ingest(:buckets_test, error_entry(i, :tmdb, "TMDB returned 429 at #{i}s"))
      end

      [bucket] = Buckets.list_buckets(:buckets_test)
      assert length(bucket.sample_entries) == 5
    end
  end

  describe "window-based eviction" do
    test "list_buckets/1 filters buckets whose last_seen is outside the window" do
      old = DateTime.add(DateTime.utc_now(), -2 * 3_600, :second)
      new_now = DateTime.utc_now()
      Buckets.ingest(:buckets_test, error_entry(1, :tmdb, "old error", old))
      Buckets.ingest(:buckets_test, error_entry(2, :tmdb, "new error", new_now))

      buckets = Buckets.list_buckets(:buckets_test)
      messages = Enum.map(buckets, & &1.normalized_message)
      assert "new error" in messages
      refute "old error" in messages
    end
  end

  describe "broadcasts" do
    test "broadcasts a throttled :buckets_changed message" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.error_reports())

      Buckets.ingest(:buckets_test, error_entry(1, :tmdb, "TMDB returned 429"))
      assert_receive {:buckets_changed, _snapshot}, 1_500

      # Rapid second insertion within throttle window: no second message
      Buckets.ingest(:buckets_test, error_entry(2, :tmdb, "TMDB returned 429"))
      refute_receive {:buckets_changed, _}, 500
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centarr/error_reports/buckets_test.exs`
Expected: FAIL — module not defined.

- [ ] **Step 3: Create the facade module (minimal — expanded in Task 10)**

```elixir
# lib/media_centarr/error_reports.ex
defmodule MediaCentarr.ErrorReports do
  use Boundary,
    deps: [MediaCentarr.Console, MediaCentarr.Config, MediaCentarr.Topics, MediaCentarr.Secret],
    exports: [Bucket, EnvMetadata, Fingerprint, IssueUrl, Redactor]

  @moduledoc """
  Bounded context for error report aggregation and GitHub issue submission.

  Subscribes to the Console log stream, groups `:error`-level entries by a
  normalized-message fingerprint, and exposes a 1-hour rolling snapshot.
  Submission is browser-side: `IssueUrl.build/2` produces a GitHub
  new-issue URL that the status page opens via `window.open`.
  """

  alias MediaCentarr.ErrorReports.Buckets
  alias MediaCentarr.Topics

  @spec list_buckets() :: [__MODULE__.Bucket.t()]
  defdelegate list_buckets(), to: Buckets

  @spec get_bucket(binary()) :: __MODULE__.Bucket.t() | nil
  defdelegate get_bucket(fingerprint), to: Buckets

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.error_reports())
end
```

- [ ] **Step 4: Implement `Buckets`**

```elixir
# lib/media_centarr/error_reports/buckets.ex
defmodule MediaCentarr.ErrorReports.Buckets do
  @moduledoc """
  GenServer that ingests Console `:error` entries, groups them by
  fingerprint, and serves a windowed snapshot to the Status page.

  - Subscribes to `Topics.console_logs()` on start and receives
    `{:log_entry, entry}` messages.
  - Each error entry is fingerprinted via `Fingerprint.fingerprint/2`,
    then appended to a `%Bucket{}` in `state.buckets`.
  - Broadcasts on `Topics.error_reports()` at most once per second.
  - Prunes buckets whose `last_seen` is outside the retention window
    every 60 seconds; `list_buckets/0` filters at call time so the UI
    is never more than the broadcast-throttle stale.

  Public API (per ADR-026): `list_buckets/0`, `get_bucket/1`, `ingest/2`
  (exposed for tests; in production `ingest` is invoked from the
  `handle_info/2` clause that receives PubSub messages). Never call
  `:sys.get_state` or `GenServer.call` directly in tests.
  """

  use GenServer
  require MediaCentarr.Log

  alias MediaCentarr.Console
  alias MediaCentarr.Console.Entry
  alias MediaCentarr.ErrorReports.{Bucket, Fingerprint}
  alias MediaCentarr.Topics

  @default_window_minutes 60
  @broadcast_throttle_ms 1_000
  @prune_interval_ms 60_000
  @max_sample_entries 5
  @max_active_buckets 200

  # --- Public API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec list_buckets() :: [Bucket.t()]
  @spec list_buckets(GenServer.server()) :: [Bucket.t()]
  def list_buckets(server \\ __MODULE__) do
    GenServer.call(server, :list_buckets)
  end

  @spec get_bucket(binary()) :: Bucket.t() | nil
  @spec get_bucket(GenServer.server(), binary()) :: Bucket.t() | nil
  def get_bucket(server \\ __MODULE__, fingerprint) when is_binary(fingerprint) do
    GenServer.call(server, {:get_bucket, fingerprint})
  end

  # Exposed for tests and for the Console handler that forwards errors.
  @spec ingest(GenServer.server(), Entry.t()) :: :ok
  def ingest(server \\ __MODULE__, %Entry{} = entry) do
    GenServer.cast(server, {:ingest, entry})
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    Console.subscribe()
    Process.send_after(self(), :prune, @prune_interval_ms)

    {:ok,
     %{
       buckets: %{},
       window_minutes: Keyword.get(opts, :window_minutes, @default_window_minutes),
       last_broadcast_at: 0,
       broadcast_pending: false
     }}
  end

  @impl true
  def handle_call(:list_buckets, _from, state) do
    {:reply, visible_buckets(state), state}
  end

  @impl true
  def handle_call({:get_bucket, fp}, _from, state) do
    bucket =
      state
      |> visible_buckets()
      |> Enum.find(&(&1.fingerprint == fp))

    {:reply, bucket, state}
  end

  @impl true
  def handle_cast({:ingest, %Entry{level: :error} = entry}, state) do
    {:noreply, do_ingest(state, entry)}
  end

  @impl true
  def handle_cast({:ingest, _non_error}, state), do: {:noreply, state}

  @impl true
  def handle_info({:log_entry, %Entry{level: :error} = entry}, state) do
    {:noreply, do_ingest(state, entry)}
  end

  @impl true
  def handle_info({:log_entry, _}, state), do: {:noreply, state}

  @impl true
  def handle_info(:prune, state) do
    Process.send_after(self(), :prune, @prune_interval_ms)
    cutoff = cutoff(state)
    new_buckets = Map.filter(state.buckets, fn {_, b} -> DateTime.compare(b.last_seen, cutoff) == :gt end)
    {:noreply, %{state | buckets: new_buckets}}
  end

  @impl true
  def handle_info(:flush_broadcast, state) do
    snapshot = visible_buckets(state)
    Phoenix.PubSub.broadcast(MediaCentarr.PubSub, Topics.error_reports(), {:buckets_changed, snapshot})
    {:noreply, %{state | last_broadcast_at: now_ms(), broadcast_pending: false}}
  end

  @impl true
  def handle_info(_other, state), do: {:noreply, state}

  # --- Internals ---

  defp do_ingest(state, %Entry{} = entry) do
    %{key: key, display_title: title, normalized_message: normalized} =
      Fingerprint.fingerprint(entry.component, entry.message)

    sample = %{
      timestamp: entry.timestamp,
      message: normalized
    }

    bucket =
      case Map.get(state.buckets, key) do
        nil ->
          %Bucket{
            fingerprint: key,
            component: entry.component,
            normalized_message: normalized,
            display_title: title,
            count: 1,
            first_seen: entry.timestamp,
            last_seen: entry.timestamp,
            sample_entries: [sample]
          }

        %Bucket{} = existing ->
          %Bucket{
            existing
            | count: existing.count + 1,
              last_seen: max_dt(existing.last_seen, entry.timestamp),
              first_seen: min_dt(existing.first_seen, entry.timestamp),
              sample_entries: take_samples([sample | existing.sample_entries])
          }
      end

    new_buckets =
      state.buckets
      |> Map.put(key, bucket)
      |> enforce_cap()

    schedule_broadcast(%{state | buckets: new_buckets})
  end

  defp visible_buckets(state) do
    cutoff = cutoff(state)

    state.buckets
    |> Map.values()
    |> Enum.filter(&(DateTime.compare(&1.last_seen, cutoff) == :gt))
    |> Enum.sort_by(& &1.last_seen, {:desc, DateTime})
  end

  defp cutoff(state) do
    DateTime.add(DateTime.utc_now(), -state.window_minutes * 60, :second)
  end

  defp take_samples(list), do: Enum.take(list, @max_sample_entries)

  defp enforce_cap(buckets) when map_size(buckets) <= @max_active_buckets, do: buckets

  defp enforce_cap(buckets) do
    {drop_key, _} =
      buckets
      |> Enum.min_by(fn {_, b} -> DateTime.to_unix(b.last_seen, :microsecond) end)

    Map.delete(buckets, drop_key)
  end

  defp schedule_broadcast(%{broadcast_pending: true} = state), do: state

  defp schedule_broadcast(state) do
    since_last = now_ms() - state.last_broadcast_at

    cond do
      since_last >= @broadcast_throttle_ms ->
        send(self(), :flush_broadcast)
        %{state | broadcast_pending: true}

      true ->
        Process.send_after(self(), :flush_broadcast, @broadcast_throttle_ms - since_last)
        %{state | broadcast_pending: true}
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp max_dt(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)
  defp min_dt(a, b), do: if(DateTime.compare(a, b) == :lt, do: a, else: b)
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/media_centarr/error_reports/buckets_test.exs`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(error_reports): Buckets GenServer + facade"
jj new
```

---

## Task 9: Register `Buckets` in the supervision tree

**Files:**
- Modify: `lib/media_centarr/application.ex`

- [ ] **Step 1: Add `ErrorReports` to the Application boundary deps**

In `lib/media_centarr/application.ex`, locate the `use Boundary, top_level?: true, deps: [...]` block and add `MediaCentarr.ErrorReports` alphabetically (between `MediaCentarr.Console` and `MediaCentarr.Library`, or in the existing order pattern):

```elixir
  use Boundary,
    top_level?: true,
    deps: [
      MediaCentarr.Library,
      MediaCentarr.Pipeline,
      MediaCentarr.Review,
      MediaCentarr.Watcher,
      MediaCentarr.Settings,
      MediaCentarr.ReleaseTracking,
      MediaCentarr.Playback,
      MediaCentarr.Console,
      MediaCentarr.ErrorReports,
      MediaCentarr.Acquisition,
      MediaCentarr.WatchHistory,
      MediaCentarr.SelfUpdate,
      MediaCentarr.TMDB,
      MediaCentarrWeb
    ]
```

- [ ] **Step 2: Add `Buckets` child to the supervision list**

In the `start/2` function's `children` list, after `MediaCentarr.Console.Buffer` (Buckets subscribes to Console, so Buffer must be running when Buckets starts):

```elixir
        MediaCentarr.Console.Buffer,
        MediaCentarr.Console.JournalSource,
        MediaCentarr.ErrorReports.Buckets,
        {Task.Supervisor, name: MediaCentarr.TaskSupervisor},
```

- [ ] **Step 3: Verify compile + app start**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`
Expected: no warnings.

Run: `mix test test/media_centarr/error_reports/buckets_test.exs` again to make sure the named-process-in-supervision-tree doesn't collide with the test-supervisor usage.
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
jj describe -m "feat(error_reports): register Buckets in supervision tree"
jj new
```

---

## Task 10: `StatusLive` — render the summary card

**Files:**
- Modify: `lib/media_centarr_web/live/status_live.ex`
- Modify: `lib/media_centarr_web/live/status_helpers.ex`

- [ ] **Step 1: Remove `merge_recent_errors/2`**

In `lib/media_centarr_web/live/status_helpers.ex`, delete the `merge_recent_errors/2` function (lines 148 and following — locate by `grep -n "merge_recent_errors"`).

- [ ] **Step 2: Write the integration test (summary card assigns)**

Create `test/media_centarr_web/live/status_live/error_summary_test.exs`:

```elixir
defmodule MediaCentarrWeb.StatusLive.ErrorSummaryTest do
  use MediaCentarrWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MediaCentarr.Console.Entry
  alias MediaCentarr.ErrorReports.Buckets
  alias MediaCentarr.Topics

  defp error_entry(id, component, message) do
    Entry.new(%{
      id: id,
      timestamp: DateTime.utc_now(),
      level: :error,
      component: component,
      message: message,
      metadata: %{}
    })
  end

  test "mount populates error_buckets assign", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")
    assert has_element?(view, "[data-testid='error-summary-card']")
  end

  test "receives :buckets_changed broadcasts", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")
    Buckets.ingest(error_entry(1, :tmdb, "TMDB returned 429"))

    # Wait for the throttled broadcast; UI should reflect the bucket
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.error_reports(),
      {:buckets_changed, Buckets.list_buckets()}
    )

    :timer.sleep(50)
    assert has_element?(view, "[data-testid='error-summary-card']")
  end
end
```

Note: the test uses `data-testid` to locate the card — a neutral, stable selector that doesn't assert on HTML structure.

- [ ] **Step 3: Run the test to verify failure**

Run: `mix test test/media_centarr_web/live/status_live/error_summary_test.exs`
Expected: FAIL — `data-testid='error-summary-card'` not present.

- [ ] **Step 4: Replace `recent_errors_table` with `error_summary_card`**

In `lib/media_centarr_web/live/status_live.ex`:

a) Update the `mount/3` callback — remove `|> assign(recent_errors: merge_recent_errors(...))` and the fallback `|> assign(recent_errors: [])`. Replace with a subscription + fetch:

```elixir
        Watcher.Supervisor.subscribe()
        Library.subscribe()
        Playback.subscribe()
        WatchHistory.subscribe()
        ErrorReports.subscribe()        # NEW

        Process.send_after(self(), :tick_pipeline, 1_000)
        Process.send_after(self(), :refresh_storage, @storage_refresh_ms)

        pipeline_stats = Stats.get_snapshot()
        image_stats = ImagePipeline.Stats.get_snapshot()

        start_async_status_stats()
        start_async_watch_history()
        start_async_storage()

        socket
        |> assign_defaults()
        |> assign(error_buckets: ErrorReports.list_buckets())   # NEW
        |> assign(pipeline_stats: pipeline_stats)
        |> assign(image_pipeline_stats: image_stats)
        # (remove the `recent_errors:` assign line)
        ...
```

b) At the top of the module, add the alias:

```elixir
  alias MediaCentarr.{Library, Playback, Status, Storage, WatchHistory, ErrorReports}
```

c) Update `assign_defaults/1` — replace `|> assign(recent_errors: [])` with `|> assign(error_buckets: [])`.

d) Add a `handle_info/2` clause for the broadcast. Locate the existing `handle_info(:tick_pipeline, ...)` clause and add above or below it (matching the file's existing grouping):

```elixir
  @impl true
  def handle_info({:buckets_changed, snapshot}, socket) do
    {:noreply, assign(socket, error_buckets: snapshot)}
  end
```

e) Replace the call site `<.recent_errors_table files={@recent_errors} />` with `<.error_summary_card buckets={@error_buckets} />`.

f) Replace the `recent_errors_table/1` component (entire function body, lines ~693-730) with:

```elixir
  defp error_summary_card(assigns) do
    ~H"""
    <div class="card glass-surface" data-testid="error-summary-card">
      <div class="card-body">
        <div class="flex justify-between items-start gap-4">
          <h2 class="card-title text-lg">Errors</h2>

          <button
            :if={@buckets != []}
            class="btn btn-sm btn-outline"
            phx-click="open_error_report_modal"
          >
            Report errors
          </button>
        </div>

        <p :if={@buckets == []} class="text-base-content/60">
          No errors in the last hour.
        </p>

        <div :if={@buckets != []} class="mt-1">
          <div class="text-sm text-base-content/70">
            <span class="text-error font-semibold">{total_count(@buckets)}</span>
            errors in the last hour, across {length(@buckets)} distinct issues.
          </div>

          <ul class="mt-2 space-y-1">
            <li :for={bucket <- top_buckets(@buckets)} class="text-sm">
              <span class="font-mono text-xs truncate" title={bucket.display_title}>
                {bucket.display_title}
              </span>
              <span class="badge badge-sm badge-ghost ml-1">×{bucket.count}</span>
              <span class="text-xs text-base-content/50 ml-1">
                {bucket.component} · {relative_time(bucket.last_seen)}
              </span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp total_count(buckets), do: Enum.reduce(buckets, 0, &(&1.count + &2))

  defp top_buckets(buckets) do
    buckets
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(3)
  end

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3_600)}h ago"
    end
  end
```

- [ ] **Step 5: Run all StatusLive tests**

Run: `mix test test/media_centarr_web/live/status_live/`
Expected: all pass (including the new `data-testid` test).

- [ ] **Step 6: Run the full test suite + precommit**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`
Expected: no warnings.

Run: `mix test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
jj describe -m "feat(status): replace recent_errors table with error summary card"
jj new
```

---

## Task 11: `ReportModal` LiveComponent — radio list + preview

**Files:**
- Create: `lib/media_centarr_web/live/status_live/report_modal.ex`
- Create: `test/media_centarr_web/live/status_live/report_modal_test.exs`
- Modify: `lib/media_centarr_web/live/status_live.ex`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentarrWeb.StatusLive.ReportModalTest do
  use MediaCentarrWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MediaCentarr.Console.Entry
  alias MediaCentarr.ErrorReports.Buckets
  alias MediaCentarr.Topics

  defp error_entry(id, component, message) do
    Entry.new(%{
      id: id,
      timestamp: DateTime.utc_now(),
      level: :error,
      component: component,
      message: message,
      metadata: %{}
    })
  end

  setup do
    Buckets.ingest(error_entry(1, :tmdb, "TMDB returned 429 rate limited"))
    Buckets.ingest(error_entry(2, :watcher, "permission denied on watch dir"))
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.error_reports(),
      {:buckets_changed, Buckets.list_buckets()}
    )
    :timer.sleep(50)
    :ok
  end

  test "clicking Report errors opens the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")
    view |> element("button", "Report errors") |> render_click()
    assert has_element?(view, "[data-testid='report-modal']")
  end

  test "confirm emits error_reports:open_issue push_event", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")
    view |> element("button", "Report errors") |> render_click()
    render_click(view, "report_confirm", %{"fingerprint" => hd(Buckets.list_buckets()).fingerprint})

    assert_push_event(view, "error_reports:open_issue", %{url: url})
    assert url =~ "https://github.com/media-centarr/media-centarr/issues/new"
  end

  test "cancel dismisses the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/status")
    view |> element("button", "Report errors") |> render_click()
    render_click(view, "report_cancel", %{})
    refute has_element?(view, "[data-testid='report-modal']")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/media_centarr_web/live/status_live/report_modal_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the LiveComponent**

```elixir
defmodule MediaCentarrWeb.StatusLive.ReportModal do
  @moduledoc """
  Modal shown when the user clicks "Report errors" on the Status page.

  Presents the active buckets in a radio list, shows a redacted payload
  preview, and on confirm emits a `push_event("error_reports:open_issue",
  %{url: url})` that the `ErrorReport` JS hook handles with `window.open`.
  """
  use MediaCentarrWeb, :live_component

  alias MediaCentarr.ErrorReports.{EnvMetadata, IssueUrl}

  @impl true
  def update(assigns, socket) do
    selected =
      case assigns.buckets do
        [first | _] -> first.fingerprint
        _ -> nil
      end

    {:ok, assign(socket, Map.put(assigns, :selected, selected))}
  end

  @impl true
  def handle_event("select", %{"fingerprint" => fp}, socket) do
    {:noreply, assign(socket, :selected, fp)}
  end

  # `report_confirm` and `report_cancel` are NOT handled here — they
  # bubble up to StatusLive because the template omits `target: @myself`
  # on those bindings. Keeping the submission logic in the parent keeps
  # the modal a pure view.

  @impl true
  def render(assigns) do
    selected_bucket =
      Enum.find(assigns.buckets, &(&1.fingerprint == assigns.selected))

    env = EnvMetadata.collect()

    preview =
      if selected_bucket do
        {:ok, _url, flags} = IssueUrl.build(selected_bucket, env)

        %{
          title: IssueUrl.format_title(selected_bucket),
          body: IssueUrl.format_body(selected_bucket, env, selected_bucket.sample_entries, flags),
          flags: flags
        }
      else
        nil
      end

    assigns = assign(assigns, :preview, preview)

    ~H"""
    <div
      id="error-report-modal"
      class="modal-backdrop"
      data-state="open"
      data-testid="report-modal"
      phx-click="report_cancel"
      phx-window-keydown="report_cancel"
      phx-key="Escape"
    >
      <div class="modal-panel" phx-click={%Phoenix.LiveView.JS{}}>
        <h2 class="text-lg font-semibold">
          Send this error report to the Media Centarr developer?
        </h2>

        <div class="alert alert-warning mt-3 text-sm">
          <span>
            Review the report below before submitting. It's been automatically
            scrubbed of paths, UUIDs, API keys, IPs, emails, and configured URLs —
            but please glance for anything else personal (titles of private files,
            usernames in error messages, etc.) before confirming.
            This will open a public GitHub issue.
          </span>
        </div>

        <fieldset class="mt-4 space-y-2">
          <legend class="text-sm text-base-content/70 mb-1">Which error?</legend>
          <label
            :for={bucket <- @buckets}
            class="flex items-start gap-2 cursor-pointer p-2 rounded hover:bg-base-200"
          >
            <input
              type="radio"
              class="radio radio-sm mt-1"
              name="bucket"
              value={bucket.fingerprint}
              checked={bucket.fingerprint == @selected}
              phx-click={JS.push("select", value: %{fingerprint: bucket.fingerprint}, target: @myself)}
            />
            <span class="flex-1 min-w-0">
              <span class="font-mono text-xs block truncate">{bucket.display_title}</span>
              <span class="text-xs text-base-content/60">
                ×{bucket.count} · {bucket.component}
              </span>
            </span>
          </label>
        </fieldset>

        <div
          :if={@preview}
          class="mt-4 bg-base-200 rounded p-4 font-mono text-xs whitespace-pre-wrap max-h-96 overflow-y-auto"
        >
          <div class="text-base-content/70 mb-2 font-sans text-sm">Preview</div>
          <div><span class="font-semibold">Title:</span> {@preview.title}</div>
          <div class="mt-2">{@preview.body}</div>
        </div>

        <div
          :if={@preview && :truncated_log_context in @preview.flags}
          class="alert alert-info mt-3 text-sm"
        >
          <span>Log context truncated to fit GitHub's URL size limit.</span>
        </div>

        <div class="mt-6 flex flex-col items-center gap-2">
          <button
            class="btn btn-primary"
            phx-click={JS.push("report_confirm", value: %{fingerprint: @selected})}
            disabled={is_nil(@selected)}
          >
            Confirm &amp; open GitHub
          </button>
          <a
            href="#"
            class="link link-hover text-sm text-base-content/60"
            phx-click="report_cancel"
          >
            No, don't send
          </a>
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 4: Wire the modal into `StatusLive`**

In `lib/media_centarr_web/live/status_live.ex`:

a) Import the component at the top alongside other aliases:

```elixir
  alias MediaCentarrWeb.StatusLive.ReportModal
```

b) In `assign_defaults/1`, add `|> assign(show_report_modal: false)`.

c) Add event handlers:

```elixir
  @impl true
  def handle_event("open_error_report_modal", _params, socket) do
    {:noreply, assign(socket, show_report_modal: true)}
  end

  @impl true
  def handle_event("report_cancel", _params, socket) do
    {:noreply, assign(socket, show_report_modal: false)}
  end

  @impl true
  def handle_event("report_confirm", %{"fingerprint" => fingerprint}, socket) do
    bucket = Enum.find(socket.assigns.error_buckets, &(&1.fingerprint == fingerprint))

    socket =
      case bucket do
        nil ->
          socket

        bucket ->
          env = MediaCentarr.ErrorReports.EnvMetadata.collect()
          {:ok, url, _flags} = MediaCentarr.ErrorReports.IssueUrl.build(bucket, env)
          push_event(socket, "error_reports:open_issue", %{url: url})
      end

    {:noreply, assign(socket, show_report_modal: false)}
  end
```

d) In the render template, after the main status grid, add the modal mount:

```heex
<.live_component
  :if={@show_report_modal}
  id="report-modal-component"
  module={ReportModal}
  buckets={@error_buckets}
/>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/media_centarr_web/live/status_live/`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(status): ReportModal LiveComponent"
jj new
```

---

## Task 12: JS hook for `window.open`

**Files:**
- Create: `assets/js/hooks/error_report.js`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Create the hook**

```javascript
// assets/js/hooks/error_report.js
//
// Listens for `error_reports:open_issue` events pushed by StatusLive and
// opens the prefilled GitHub issue URL in a new tab. The hook is attached
// to a stable element on /status (the error summary card).

export const ErrorReport = {
  mounted() {
    this.handleEvent("error_reports:open_issue", ({url}) => {
      window.open(url, "_blank", "noopener")
    })
  }
}
```

- [ ] **Step 2: Register the hook in `app.js`**

In `assets/js/app.js`, add to the imports:

```javascript
import {ErrorReport} from "./hooks/error_report"
```

And add to the `hooks:` block inside `new LiveSocket(...)`:

```javascript
  hooks: {
    ...colocatedHooks,
    InputSystem: createInputHook(),
    Console,
    LogTail,
    CopyButton,
    ErrorReport,
    ScrollToResume: { ... },
    ScrollForward: { ... },
  },
```

- [ ] **Step 3: Attach the hook to the error summary card**

In `lib/media_centarr_web/live/status_live.ex`, update the `error_summary_card/1` component's top-level `<div>`:

```elixir
    <div
      class="card glass-surface"
      data-testid="error-summary-card"
      id="error-summary-card"
      phx-hook="ErrorReport"
    >
```

- [ ] **Step 4: Manual smoke-test in dev browser**

Start the dev server (`systemctl --user restart media-centarr-dev` or `mix phx.server`). Trigger an error in IEx:

```elixir
iex --name repl@127.0.0.1 --remsh media_centarr_dev@127.0.0.1
# Then in the shell:
require MediaCentarr.Log
MediaCentarr.Log.error(:system, "demo error for testing report flow")
```

In the browser, open `/status`, wait for the bucket to appear, click **Report errors**, select the bucket, click **Confirm & open GitHub**. A new browser tab should open on `github.com/media-centarr/media-centarr/issues/new` with the title and body prefilled. Close that tab without filing.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(status): ErrorReport JS hook to open github issue"
jj new
```

---

## Task 13: Precommit + wiki updates

**Files:**
- Create (wiki): `../media-centarr.wiki/Troubleshooting.md` (append section)
- Create (wiki): `../media-centarr.wiki/FAQ.md` (append question)

- [ ] **Step 1: Run full precommit**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit`
Expected: all steps pass (compile --warnings-as-errors, format, credo --strict, sobelow, deps.audit, test).

If any step fails, fix the root cause; do not skip.

- [ ] **Step 2: Append to wiki `Troubleshooting.md`**

In `~/src/media-centarr/media-centarr.wiki/Troubleshooting.md`, append:

```markdown
## Reporting errors to the developer

When something's going wrong, the **Status** page (⚙ Status in the nav)
shows a summary of recent errors grouped by the underlying cause. If an
error is blocking you, click **Report errors** at the top of that card.

A modal pops up showing the exact payload that will be sent as a GitHub
issue. The payload is automatically scrubbed of file paths, UUIDs, API
keys, IP addresses, emails, and any URLs you've configured (Prowlarr,
download clients). **Please review it before confirming** — private file
titles or usernames inside error messages are not auto-scrubbed.

On confirm, a new browser tab opens on the Media Centarr GitHub repo
pre-filled with the title and body. You can still edit the issue or
back out before submitting.
```

- [ ] **Step 3: Append to wiki `FAQ.md`**

```markdown
### What gets sent to GitHub when I click "Report errors"?

The environment block (app version, Erlang/Elixir, OS, locale, uptime),
the error fingerprint, occurrence counts, and up to 5 recent log lines
from the same error bucket. All of this is shown in a preview panel
before you confirm, so you can read every character that would be sent
and cancel if anything looks personal.

Automatically scrubbed before display: file paths, UUIDs, API keys,
IP addresses, emails, configured external URLs. Not automatically
scrubbed: file titles if they appear inside a free-form error message.

Nothing is sent unless you click **Confirm & open GitHub**. The
submission is your own browser opening a pre-filled GitHub issue form.
There is no server-side telemetry.
```

- [ ] **Step 4: Commit wiki**

```bash
cd ~/src/media-centarr/media-centarr.wiki
jj describe -m "wiki: document status-page error reporting"
jj bookmark set master -r @
jj git push
cd -
```

- [ ] **Step 5: Final app-repo commit**

No app-code changes in this step. If any fix-up edits were needed from precommit, commit them separately with a descriptive message.

```bash
# In app repo:
jj st   # verify clean
```

---

## Self-review

**Spec coverage check:**

| Spec section | Implementing task(s) |
|---|---|
| §Architecture / new context | Tasks 2-8 |
| §Module layout | Tasks 2-8 |
| §Boundary dependencies | Tasks 8, 9 |
| §Data flow | Tasks 8, 10, 11, 12 |
| §Bucket struct | Task 2 |
| §Retention + memory cap | Task 8 (Buckets) |
| §Fingerprinting | Task 5 |
| §Redaction rules | Tasks 3, 4 |
| §GitHub issue URL + fallback | Task 7 |
| §Status card UI | Task 10 |
| §Report modal UI | Task 11 |
| §JS hook | Task 12 |
| §Error handling / edge cases | Tasks 3, 4, 7, 8 (covered by tests) |
| §Testing | Tasks 3, 4, 5, 6, 7, 8, 10, 11 |
| §Migration / removal | Task 10 (removes merge_recent_errors/2 + recent_errors_table/1) |
| §Wiki updates | Task 13 |

**Placeholder scan:** No TBDs, no "add appropriate X", no "similar to Task N" references. Every code step has the full code. Every command step has the exact command and expected outcome.

**Type consistency check:** `Bucket` struct fields match across all references (`fingerprint`, `component`, `normalized_message`, `display_title`, `count`, `first_seen`, `last_seen`, `sample_entries`). Fingerprint API is `%{key, display_title, normalized_message}` across every call site. `IssueUrl.build/2` signature matches both its test and its use in ReportModal.

---
