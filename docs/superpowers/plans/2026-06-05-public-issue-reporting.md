# Public-issue error reporting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-aim the in-app error reporter from a (never-wired, privacy-promised) private GitHub repo to a redacted **public** GitHub issue the user posts under their own login — no token, no relay, no auto-submission.

**Architecture:** The redacted markdown + 3-step review modal already exist. We (1) build a prefilled `…/issues/new` URL, (2) rework `ErrorReports` to return `%{title, body, issue_url}` instead of submitting, (3) rewrite the modal result view to Copy (existing `CopyButton` hook) + Open-issue (anchor), (4) flip the consent-flow copy from "private" to "public + redacted", (5) delete the transport/token machinery.

**Tech Stack:** Elixir/Phoenix LiveView, daisyUI, Phoenix Storybook, ExUnit (DataCase), existing `CopyButton` JS hook.

**Spec:** `docs/superpowers/specs/2026-06-05-public-issue-reporting-design.md`

**Note vs spec:** the spec proposed a new `ReportPost` JS hook; we instead reuse the existing tested `CopyButton` + an anchor link (less new surface, same UX: copy then open & paste). The spec is updated to match in Task 7.

---

### Task 1: `IssueUrl.new_issue_url/2` + public-repo config

**Files:**
- Modify: `lib/media_centaur/error_reports/issue_url.ex`
- Modify: `config/config.exs` (add `:diagnostics_issues_repo`)
- Test: `test/media_centaur/error_reports/issue_url_test.exs`

- [ ] **Step 1: Write failing tests** — append to `issue_url_test.exs`:

```elixir
describe "new_issue_url/2" do
  test "targets the configured public repo with title + labels + paste placeholder" do
    url = IssueUrl.new_issue_url("Boom happened", ["incident", "auto-reported"])

    assert url =~ "https://github.com/media-centaur/media-centaur/issues/new?"
    assert url =~ "title=Boom+happened"
    assert url =~ "labels=incident%2Cauto-reported"
    assert url =~ "body=" and url =~ "clipboard"
  end

  test "percent-encodes special characters in the title" do
    url = IssueUrl.new_issue_url("crash: a/b #4 — é", [])
    assert url =~ "title=crash%3A+a%2Fb+%234+%E2%80%94+%C3%A9"
    refute url =~ "labels="
  end

  test "honors a :diagnostics_issues_repo override" do
    original = Application.get_env(:media_centaur, :diagnostics_issues_repo)
    Application.put_env(:media_centaur, :diagnostics_issues_repo, "acme/widgets")
    on_exit(fn -> Application.put_env(:media_centaur, :diagnostics_issues_repo, original) end)

    assert IssueUrl.new_issue_url("x", []) =~ "https://github.com/acme/widgets/issues/new?"
  end
end
```

- [ ] **Step 2: Run, verify fail**

Run: `mix test test/media_centaur/error_reports/issue_url_test.exs`
Expected: FAIL — `new_issue_url/2` undefined.

- [ ] **Step 3: Implement** — in `issue_url.ex`, update the moduledoc first line to "Renders the redacted Markdown for an incident report and builds the prefilled GitHub new-issue URL." and add:

```elixir
@default_repo "media-centaur/media-centaur"
@paste_placeholder "<!-- Paste your report below — it's on your clipboard (Ctrl/Cmd+V). -->\n\n"

@doc """
Builds the prefilled public GitHub new-issue URL. The full report body travels
via the clipboard (not the URL — sidesteps length limits); the `body` param
carries only a paste prompt. `labels` are best-effort (GitHub drops `labels=`
for reporters without triage rights).
"""
@spec new_issue_url(binary(), [binary()]) :: binary()
def new_issue_url(title, labels \\ []) do
  repo = Application.get_env(:media_centaur, :diagnostics_issues_repo, @default_repo)

  params =
    %{"title" => title, "body" => @paste_placeholder}
    |> then(fn p -> if labels == [], do: p, else: Map.put(p, "labels", Enum.join(labels, ",")) end)

  "https://github.com/#{repo}/issues/new?" <> URI.encode_query(params)
end
```

- [ ] **Step 4: Run, verify pass**

Run: `mix test test/media_centaur/error_reports/issue_url_test.exs`
Expected: PASS.

- [ ] **Step 5: Add the config default** — in `config/config.exs`, near the diagnostics block:

```elixir
# Public repo the in-app reporter opens a new issue against (user posts under
# their own GitHub login). Overridable for tests/showcase.
config :media_centaur, :diagnostics_issues_repo, "media-centaur/media-centaur"
```

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/error_reports/issue_url.ex config/config.exs test/media_centaur/error_reports/issue_url_test.exs
git commit -m "feat(error-reports): build prefilled public GitHub new-issue URL"
```

---

### Task 2: Move the `payload` type off the doomed `ReportTransport`

**Files:**
- Modify: `lib/media_centaur/error_reports/report_payload.ex`
- Modify: `lib/media_centaur/error_reports.ex:136`

`ReportTransport` is deleted in Task 6, but `payload()` (used by `ReportPayload` and `ErrorReports.build_generic_report/0`) must survive. Move it to `ReportPayload`.

- [ ] **Step 1: Add the type + drop the alias in `report_payload.ex`**

Replace `alias MediaCentaur.ErrorReports.ReportTransport` with nothing, and add under the aliases:

```elixir
@type payload :: %{title: String.t(), body: String.t(), labels: [String.t()]}
```

Change both `@spec` lines from `:: ReportTransport.payload()` to `:: payload()`.

- [ ] **Step 2: Update `error_reports.ex`**

Remove `alias MediaCentaur.ErrorReports.ReportTransport` (line 34). Change line 136 spec to:

```elixir
@spec build_generic_report() :: %{snapshot: map(), payload: ReportPayload.payload()}
```

- [ ] **Step 3: Compile clean**

Run: `mix compile --warnings-as-errors`
Expected: compiles (ReportTransport still exists, now only referenced by GithubTransport + its test — removed in Task 6).

- [ ] **Step 4: Commit**

```bash
git add lib/media_centaur/error_reports/report_payload.ex lib/media_centaur/error_reports.ex
git commit -m "refactor(error-reports): move payload type to ReportPayload"
```

---

### Task 3: Rework `ErrorReports` — finalize instead of submit

**Files:**
- Modify: `lib/media_centaur/error_reports.ex`
- Test: `test/media_centaur/error_reports/report_submission_test.exs` (rewrite)

- [ ] **Step 1: Rewrite the submission test** — replace the `OkTransport`/`FailTransport` modules and the `submit_payload` describe blocks. Keep any `ReportPayload.build/2` rendering tests **only if** not already covered in `report_payload_test.exs` (they are — so drop them here). New body:

```elixir
defmodule MediaCentaur.ErrorReports.ReportSubmissionTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ErrorReports

  describe "finalize_report/1" do
    test "returns the title, body, and a prefilled public issue URL" do
      payload = %{title: "Boom", body: "the body", labels: ["incident"]}
      assert %{title: "Boom", body: "the body", issue_url: url} = ErrorReports.finalize_report(payload)
      assert url =~ "github.com/media-centaur/media-centaur/issues/new?"
      assert url =~ "title=Boom"
    end
  end

  describe "persist_user_incident/1" do
    test "persists an open :user incident" do
      snapshot = MediaCentaur.ErrorReports.ContextSnapshot.assemble(:user, %{})
      :ok = ErrorReports.persist_user_incident(%{user_description: "it broke", snapshot: snapshot})

      assert [incident | _] = ErrorReports.list_incidents()
      assert incident.origin == :user
    end

    test "never raises if the local write fails" do
      assert :ok = ErrorReports.persist_user_incident(%{user_description: "x", snapshot: %{}})
    end
  end
end
```

> Verify the incident field/value (`origin == :user`) against `Incident` schema; adjust the assertion to the real field if it differs.

- [ ] **Step 2: Run, verify fail**

Run: `mix test test/media_centaur/error_reports/report_submission_test.exs`
Expected: FAIL — `finalize_report/1`, `persist_user_incident/1` undefined.

- [ ] **Step 3: Implement in `error_reports.ex`** — remove `submit_report/2`, `submit_payload/2`, `create_user_report/2`, `configured_transport/0`, and the `GithubTransport` alias. Add:

```elixir
@doc """
Finalizes a (possibly user-edited) payload for browser-side posting: returns the
title, body, and the prefilled public GitHub new-issue URL. No network call.
"""
@spec finalize_report(ReportPayload.payload()) ::
        %{title: String.t(), body: String.t(), issue_url: String.t()}
def finalize_report(%{title: title, body: body} = payload) do
  %{title: title, body: body, issue_url: IssueUrl.new_issue_url(title, Map.get(payload, :labels, []))}
end

@doc """
Best-effort persistence of the `:user` incident (submission is never blocked by a
local write failure).
"""
@spec persist_user_incident(map()) :: :ok
def persist_user_incident(%{user_description: desc, snapshot: snapshot}) do
  _ = create_user_incident(%{user_description: desc, first_context: snapshot})
  :ok
end
```

Add `alias MediaCentaur.ErrorReports.IssueUrl`. Update the moduledoc (Task 7).

- [ ] **Step 4: Run, verify pass**

Run: `mix test test/media_centaur/error_reports/report_submission_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/error_reports.ex test/media_centaur/error_reports/report_submission_test.exs
git commit -m "refactor(error-reports): finalize_report + persist_user_incident, drop transport submission"
```

---

### Task 4: Rewrite `ReportModal` send handler + result view

**Files:**
- Modify: `lib/media_centaur_web/live/status_live/report_modal.ex`
- Test: existing `*_live_test.exs` covering the report modal (locate via `grep -rln "report-modal\|ReportModal\|Send to the developer" test/`)

- [ ] **Step 1: Write/extend the LiveView test** — drive the modal to step 3, consent, send; assert the result view shows the Open-issue link and Copy affordance, and (snapshot case) that an incident was persisted. Assert on rendered links/data attributes and on `ErrorReports.list_incidents/0`, never on internal HTML structure. Example assertion core:

```elixir
# after stepping to 3, toggling consent, and clicking "send":
assert html =~ "issues/new"           # the GitHub anchor href
assert html =~ "Copy report"
# generic/snapshot path also persisted an incident:
assert ErrorReports.list_incidents() != []
```

- [ ] **Step 2: Run, verify fail**

Run: `mix test <that live test file>`
Expected: FAIL (old flow asserted `{:ok}`/fallback or old labels).

- [ ] **Step 3: Implement** — rewrite the `"send"` handler and `result/1`:

```elixir
def handle_event("send", _p, %{assigns: %{consent: false}} = socket), do: {:noreply, socket}

def handle_event("send", _p, socket) do
  assembled = %{
    title: socket.assigns.title,
    body: ErrorReports.assemble_body(socket.assigns.narrative, socket.assigns.body),
    labels: @labels
  }

  if snapshot = socket.assigns.snapshot do
    ErrorReports.persist_user_incident(%{user_description: socket.assigns.narrative, snapshot: snapshot})
  end

  {:noreply, assign(socket, :report_result, ErrorReports.finalize_report(assembled))}
end
```

Replace `result/1` (drop the `{:ok}`/`{:fallback}` match; attr is now the outcome map):

```elixir
attr :result, :map, required: true, doc: "%{title, body, issue_url} from ErrorReports.finalize_report/1"

defp result(assigns) do
  ~H"""
  <div class="p-6 flex flex-col gap-3">
    <h2 class="text-lg font-semibold">Post this report to GitHub</h2>
    <p class="text-sm text-base-content/70">
      This opens a <span class="font-medium">public issue</span> under your GitHub account.
      Copy the report, open the issue, and paste it in.
    </p>
    <textarea
      data-testid="report-fallback"
      readonly
      rows="12"
      class="textarea textarea-bordered w-full font-mono text-xs"
    >{@result.body}</textarea>
    <div class="flex items-center gap-2">
      <button
        type="button"
        id="report-copy"
        phx-hook="CopyButton"
        data-copy-text={@result.body}
        class="btn btn-sm"
      >Copy report</button>
      <a href={@result.issue_url} target="_blank" rel="noopener" class="btn btn-sm btn-primary">
        Open GitHub issue
      </a>
      <div class="flex-1"></div>
      <.button variant="dismiss" phx-click="report_cancel">Close</.button>
    </div>
  </div>
  """
end
```

- [ ] **Step 4: Run, verify pass**

Run: `mix test <that live test file>`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/status_live/report_modal.ex test/...
git commit -m "feat(error-reports): modal posts a public GitHub issue (copy + open)"
```

---

### Task 5: Flip the consent-flow copy (private → public + redacted)

**Files:**
- Modify: `lib/media_centaur_web/components/consent_components.ex`
- Verify: `storybook/status/consent_*.story.exs` still render (attrs unchanged → no edits expected)

- [ ] **Step 1: Rewrite step 1** — replace the intro `<p>` and the four `<li>` promises:

```heex
<p class="text-sm text-base-content/70 leading-relaxed">
  Media Centaur gathered the technical details of this problem. It will be posted
  as a <span class="font-medium text-base-content">public issue on GitHub</span>
  so it can be tracked and fixed — and you'll review and edit the exact text first.
</p>
<ul class="flex flex-col gap-2 text-sm">
  <li>You'll see exactly what gets posted.</li>
  <li>We've removed file paths, API keys, IP addresses, and emails.</li>
  <li>You can edit or remove anything before posting.</li>
  <li>It posts to GitHub under your account, only when you choose to.</li>
</ul>
```

- [ ] **Step 2: Rewrite step 3** — replace the private-inbox box and checkbox label:

```heex
<div class="glass-inset rounded-lg p-3 text-sm text-base-content/70 leading-relaxed">
  This opens a <span class="font-medium text-base-content">public GitHub issue</span>
  under your account. It contains exactly what you reviewed, including anything you
  wrote or edited. Give it one more glance — once posted, it's public.
</div>
```

Change the checkbox `<span>` to: `I've reviewed this and I'm posting it publicly on GitHub.`

Update the three `@doc` strings on the components to drop "private" framing.

- [ ] **Step 3: Verify stories + render tests**

Run: `mix test test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/storybook_compile_test.exs`
Expected: PASS (attrs unchanged; copy-only change). If a story asserts on old copy text, update it.

- [ ] **Step 4: Commit**

```bash
git add lib/media_centaur_web/components/consent_components.ex storybook/status/
git commit -m "feat(error-reports): consent flow framed as public, redacted posting"
```

---

### Task 6: Delete the transport / token machinery

**Files:**
- Delete: `lib/media_centaur/error_reports/github_transport.ex`
- Delete: `test/media_centaur/error_reports/github_transport_test.exs`
- Delete: `lib/media_centaur/error_reports/report_transport.ex`
- Modify: `config/config.exs` (remove `:diagnostics_report_repo`, `:diagnostics_report_token`, the long comment)
- Modify: `config/runtime.exs` (remove the `MEDIA_CENTAUR_DIAGNOSTICS_REPORT_TOKEN/_REPO` block added in `000bae42`)

- [ ] **Step 1: Delete the files**

```bash
git rm lib/media_centaur/error_reports/github_transport.ex \
       test/media_centaur/error_reports/github_transport_test.exs \
       lib/media_centaur/error_reports/report_transport.ex
```

- [ ] **Step 2: Strip config** — in `config/config.exs` remove the `diagnostics_report_repo`/`diagnostics_report_token` lines and their comment block (keep `:diagnostics_issues_repo` from Task 1). In `config/runtime.exs` remove the entire `MEDIA_CENTAUR_DIAGNOSTICS_REPORT_TOKEN` / `_REPO` `if` block.

- [ ] **Step 3: Compile clean (catches stragglers)**

Run: `mix compile --warnings-as-errors`
Expected: clean. If `GithubTransport`/`ReportTransport` still referenced anywhere, fix it.

- [ ] **Step 4: Full precommit**

Run: `mix precommit`
Expected: green (4300+ tests). The `boundaries`/credo/format passes confirm no dangling refs.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(error-reports): remove private-repo transport, token config, and runtime wiring"
```

---

### Task 7: Docs — moduledocs, spec, wiki

**Files:**
- Modify: `lib/media_centaur/error_reports.ex` (moduledoc), `lib/media_centaur/error_reports/report_payload.ex` (moduledoc), `lib/media_centaur_web/live/status_live/report_modal.ex` (moduledoc), `lib/media_centaur/error_reports/issue_url.ex` (moduledoc — done in Task 1)
- Modify: `docs/superpowers/specs/2026-06-01-consent-flow-design.md` (superseded banner), `docs/superpowers/specs/2026-06-05-public-issue-reporting-design.md` (drop the `ReportPost` hook line; note CopyButton + anchor)
- Modify: wiki (`../media-centaur.wiki/`) — Troubleshooting / FAQ

- [ ] **Step 1: Update moduledocs** — `ErrorReports` moduledoc: replace the "Submission is server-side … GithubTransport posts it to a private GitHub repo … {:fallback}" paragraph with: submission is browser-side — `finalize_report/1` returns the redacted text + a prefilled public new-issue URL; the user posts it under their own GitHub login. `ReportPayload` moduledoc: drop the "REST API body budget" line. `ReportModal` moduledoc: "submits via …copy-fallback" → "produces redacted text + public new-issue URL; user copies and posts."

- [ ] **Step 2: Supersede banner** — add to the top of `2026-06-01-consent-flow-design.md`:

```markdown
> **Superseded 2026-06-05** by [`2026-06-05-public-issue-reporting-design.md`](2026-06-05-public-issue-reporting-design.md). The private-inbox model and its privacy promises are withdrawn; reports now post to a public GitHub issue.
```

Edit the new spec's Components section: remove the `ReportPost` hook bullet; state the result view reuses `CopyButton` + an anchor link.

- [ ] **Step 3: Wiki** — in `../media-centaur.wiki/`, update the error-reporting section (Troubleshooting and/or FAQ): the reporter now opens a **public** GitHub issue under the user's account; remove any "private / only the developer can read it" language; note that paths/keys/IPs/emails are auto-redacted and the user reviews before posting.

```bash
cd ../media-centaur.wiki && git add -A && git commit -m "wiki: error reporter posts a public, redacted GitHub issue" && git push && cd -
```

- [ ] **Step 4: Commit docs**

```bash
git add lib/ docs/
git commit -m "docs(error-reports): public-issue model in moduledocs + supersede private-inbox spec"
```

---

## Self-Review

**Spec coverage:**
- Public new-issue URL → Task 1. ✓
- Copy + open mechanism → Task 4 (CopyButton + anchor; spec note reconciled in Task 7). ✓
- Messaging rewrite → Task 5. ✓
- Retire transport/token/runtime wiring → Task 6. ✓
- `payload` type survival → Task 2. ✓
- Incident still persisted → Task 3 (`persist_user_incident/1`). ✓
- No-network/clipboard-fail degradation → Task 4 result view (readonly textarea always present). ✓
- Wiki + moduledocs → Task 7. ✓

**Placeholder scan:** Two intentional verification caveats (Task 3 `origin` field, Task 4 live-test locator) — the worker confirms the real symbol against the schema/test before asserting; both name the exact check. No blind TODOs.

**Type consistency:** `finalize_report/1` returns `%{title, body, issue_url}` (Tasks 3, 4 agree). `new_issue_url/2` = `(title, labels)` (Tasks 1, 3 agree). `payload()` type defined in Task 2, used in Tasks 2/3. `persist_user_incident/1` takes `%{user_description, snapshot}` (Tasks 3, 4 agree).
