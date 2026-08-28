%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "priv/repo/migrations/", "priv/repo/data_migrations/"],
        excluded: [
          ~r"/_build/",
          ~r"/deps/",
          ~r"/node_modules/",
          ~r"/priv/static/",
          ~r"/assets/node_modules/"
        ]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # Consistency
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},

          # Design
          {Credo.Check.Design.AliasUsage,
           [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 2]},
          {Credo.Check.Design.SkipTestWithoutComment, []},
          {Credo.Check.Design.TagFIXME, []},
          {Credo.Check.Design.TagTODO, [exit_status: 2]},

          # Readability
          {Credo.Check.Readability.FunctionNames, []},
          {Credo.Check.Readability.LargeNumbers, []},
          # Bumped from 98 (formatter default) to 105 — comments and regex
          # patterns in Parser, plus a handful of long strings, occasionally
          # overrun by 1–6 characters and aren't worth the wrap churn. The
          # formatter still reins in code lines.
          {Credo.Check.Readability.MaxLineLength,
           [priority: :low, max_length: 105, ignore_definitions: true]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleDoc,
           [
             ignore_names: [
               ~r/Test$/,
               ~r/^MediaCentaur\.Credo\.Checks\..+$/,
               ~r/^Mix\.Tasks\..+$/
             ]
           ]},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Readability.OneArityFunctionInPipe, []},
          {Credo.Check.Readability.ParenthesesInCondition, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
          # PredicateFunctionNames intentionally disabled — replaced by
          # MediaCentaur.Credo.Checks.PredicateNaming, which enforces the
          # AGENTS.md rule (`?` suffix, no `is_` prefix).
          {Credo.Check.Readability.PredicateFunctionNames, false},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.RedundantBlankLines, []},
          {Credo.Check.Readability.Semicolons, []},
          {Credo.Check.Readability.SinglePipe, []},
          {Credo.Check.Readability.SpaceAfterCommas, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.VariableNames, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Readability.WithSingleClause, []},

          # Refactor
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CondStatements, []},
          # Bumped from the planned 12 to 22 to cover existing top-level
          # dispatchers (LiveView `handle_params`, configuration parsers).
          # Refactoring those into smaller pieces is high-risk for low value
          # and belongs in a focused change, not the Credo rollout.
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 22]},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.FilterCount, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.FilterReject, []},
          # Three existing functions take 7 args (Pipeline.Stats helpers,
          # ReleaseTracking.Scanner). Bumped to 7 to accept current code.
          {Credo.Check.Refactor.FunctionArity, [max_arity: 7]},
          # IoPuts catches debug print statements left in production code, but
          # `MediaCentaur.Diagnostics` and Mix tasks legitimately print to
          # stdout — that's their job. Exclude those from the check.
          {Credo.Check.Refactor.IoPuts,
           [
             files: %{excluded: ["lib/media_centaur/diagnostics.ex", "lib/mix/tasks/"]}
           ]},
          {Credo.Check.Refactor.LongQuoteBlocks, [max_line_count: 250]},
          {Credo.Check.Refactor.MapJoin, []},
          {Credo.Check.Refactor.MapMap, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []},
          # Bumped from the planned 3 to 5 to cover existing nested cases in
          # ReleaseTracking.Refresher and a few config parsers. New code
          # should still aim for ≤3.
          {Credo.Check.Refactor.Nesting, [max_nesting: 5]},
          {Credo.Check.Refactor.PassAsyncInTestCases, []},
          {Credo.Check.Refactor.PerceivedComplexity, [max_complexity: 22]},
          {Credo.Check.Refactor.RedundantWithClauseResult, []},
          {Credo.Check.Refactor.RejectFilter, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.UnlessWithElse, []},
          {Credo.Check.Refactor.UtcNowTruncate, []},
          {Credo.Check.Refactor.WithClauses, []},

          # Warning
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.Dbg, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.ForbiddenModule, [modules: [:gen_event]]},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          # `LeakyEnvironment` flags `System.cmd` calls that don't pass
          # `env: []` to scrub the parent environment. Mix tasks running
          # locally (boundaries → bunx) intentionally inherit PATH; that
          # subprocess never touches credentials.
          {Credo.Check.Warning.LeakyEnvironment, [files: %{excluded: ["lib/mix/tasks/"]}]},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.MixEnv, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.UnsafeExec, []},
          # UnsafeToAtom matters in lib/ where dynamic atom creation can
          # leak memory. Tests legitimately create unique GenServer names
          # (`:"buffer_#{unique_integer}"`); the atom growth is bounded by
          # test count.
          {Credo.Check.Warning.UnsafeToAtom, [files: %{excluded: ["test/"]}]},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.WrongTestFilename, []},

          # credo_naming plugin
          # `ModuleFilename` produces too many false positives for this stack:
          # Phoenix 1.7+ error handlers (`error_html.ex`/`error_json.ex`),
          # `live/`/`components/` directories, branded names that violate
          # Macro.underscore expectations (`QBittorrent` -> `q_bittorrent`),
          # and test-file analogues of all three. The bundled Phoenix plugin
          # only handles `controllers/` and `views/`. Disabled rather than
          # tuned because the surface area of exclusions exceeds what the
          # check would catch.
          # Note: `Util`/`Utils`/`Misc` were considered for the denylist but the
          # repo intentionally has `MediaCentaur.DateUtil` (a one-function
          # module), and there's no clear better name without churn. Keep only
          # `Misc` which signals genuine indecision.
          {CredoNaming.Check.Warning.AvoidSpecificTermsInModuleNames, [terms: ["Misc"]]},

          # credo_envvar plugin
          # credo_envvar's check is fooled by macros (e.g. `setup do ... end`
          # in ExUnit) — it sees `Application.get_env` outside an explicit
          # `def`/`defp` and flags it, even when the macro expands to a
          # runtime-only context. Limit to lib/.
          {CredoEnvvar.Check.Warning.EnvironmentVariablesAtCompileTime, [files: %{excluded: ["test/"]}]},

          # credo_check_error_handling_ecto_oban was dropped 2026-08-28: the
          # hex package (0.9.1, unmaintained since 2023) declares credo as
          # `only: [:dev, :test]` in its own mix.exs, so hex strips the dep
          # for consumers and the package cannot compile under Elixir 1.20's
          # stricter per-dep code paths (`Credo.Check` not loaded). It is
          # GPL-3.0, so vendoring into this MIT repo is not an option. If the
          # guarded footgun (an Oban worker returning Repo.transaction/2's
          # 4-tuple, which Oban treats as success) needs coverage again,
          # reimplement it as a custom check in credo_checks/.

          # Custom checks (this repo)
          {MediaCentaur.Credo.Checks.PredicateNaming, []},
          {MediaCentaur.Credo.Checks.NoAbbreviatedNames, []},
          {MediaCentaur.Credo.Checks.ContextSubscribeFacade, []},
          {MediaCentaur.Credo.Checks.EntityModalContract, []},
          {MediaCentaur.Credo.Checks.PlaybackEventsContract, []},
          {MediaCentaur.Credo.Checks.LibraryUpdatesContract, []},
          {MediaCentaur.Credo.Checks.TargetStatusContract, []},
          {MediaCentaur.Credo.Checks.PursuitStateContract, []},
          {MediaCentaur.Credo.Checks.NoSysIntrospection, []},
          {MediaCentaur.Credo.Checks.LogMacroPreferred, []},
          {MediaCentaur.Credo.Checks.ModalPanelNoClickAway, []},
          {MediaCentaur.Credo.Checks.ModalBackdropViaComponent, []},
          {MediaCentaur.Credo.Checks.RawButtonClass, []},
          {MediaCentaur.Credo.Checks.NoPhxValueValue, []},
          {MediaCentaur.Credo.Checks.RawBadgeClass, []},
          # MC0027 bans `data-confirm` — the native browser dialog is unthemed
          # and not d-pad reachable, which is disqualifying for a couch app.
          # The check's moduledoc carries the three-way rule that replaced it
          # (nothing / arm-in-place / persistent modal, by consequence).
          # `@exempt_files` holds the console, which is deliberately outside
          # the input system that motivates the rule.
          {MediaCentaur.Credo.Checks.NativeConfirmDialog, []},
          {MediaCentaur.Credo.Checks.StorybookCoverage, []},
          {MediaCentaur.Credo.Checks.TypedComponentAttrs, []},
          {MediaCentaur.Credo.Checks.DestructiveFileQuery, []},
          # MC0016 enforces eager + sync-decode on in-flow `<img>` tags per
          # UIDR-012. Lazy is allowed only in reveal-bounded surfaces named
          # in the check's `@exempt_files` list.
          {MediaCentaur.Credo.Checks.ImgAttributeDefaults, []},
          # MC0028 is MC0016's other half: eager + sync decode makes every
          # image block paint, so every local artwork `<img>` must also say
          # how wide it paints — `sized_image_url(url, px | :full_bleed)`.
          # Omitting it silently served the 4K master to 40px thumbnails.
          {MediaCentaur.Credo.Checks.ArtworkWidthDeclared, []},
          # MC0015 catches `execute("UPDATE …")` / `execute("DELETE …")` in
          # priv/repo/migrations/ — bulk row mutations belong in a data
          # migration per ADR-040, not in a schema migration where a dev
          # `mix ecto.migrate` against a shared DB can shadow the version
          # before prod ever sees it.
          #
          # The grandfathered list is migrations shipped before MC0015
          # existed. They're append-only per ADR-040 — annotating each
          # instance with a `credo:disable-next-line` comment counts as a
          # comment-only edit and is allowed, but a single file-level list
          # here is clearer than 40+ scattered annotations. Do not add new
          # files to this list; new mutations go in priv/repo/data_migrations/.
          {MediaCentaur.Credo.Checks.RowMutationInSchemaMigration,
           [
             files: %{
               excluded: [
                 "priv/repo/migrations/20260403000001_migrate_entity_data_to_type_tables.exs",
                 "priv/repo/migrations/20260404202512_denormalize_release_tracking_events.exs",
                 "priv/repo/migrations/20260503180000_heal_grabs_tmdb_type_tv_series.exs",
                 "priv/repo/migrations/20260504180420_backfill_entity_tmdb_id_from_external_ids.exs",
                 "priv/repo/migrations/20260504202644_drop_tmdb_external_ids.exs",
                 "priv/repo/migrations/20260511190000_pursuit_target_recipe_refactor.exs",
                 "priv/repo/migrations/20260514100000_collapse_needs_decision_into_awaiting_flag.exs",
                 "priv/repo/migrations/20260515000000_repoint_collection_child_watched_files.exs"
               ]
             }
           ]},
          # MC0017 keeps OS-divergent code under `lib/media_centaur/platform/`.
          # `:os.type/0` / `:os.cmd/1` outside that directory fail the build.
          # The grandfathered list holds files with pre-existing calls scheduled
          # for migration in later campaign phases — see
          # `campaigns/macos-platform-support.md`. The list shrinks as each seam
          # extracts to `Platform.*`; once empty, drop the option entirely.
          {MediaCentaur.Credo.Checks.PlatformBranchingDiscipline,
           [
             grandfathered: [
               "lib/media_centaur/error_reports/env_metadata.ex"
             ]
           ]},
          # MC0018 blocks DB writes inside on_exit callbacks — they run in
          # ExUnit.OnExitHandler without the test's sandbox ownership and
          # race under concurrent-test load. See
          # campaigns/test-isolation-hardening.md (Category A).
          {MediaCentaur.Credo.Checks.NoDbInOnExit, []},
          # MC0019 bans fire-and-forget
          # `Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, …)` in the
          # web layer — orphaned tasks aren't owned by the LiveView, leak past
          # navigation, and hung the test suite. Use start_async/3 (owned) or an
          # Oban job for must-outlive work. The check's grandfather list is the
          # owned-async rollout backlog. See ADR-049 /
          # campaigns/test-suite-performance.md.
          {MediaCentaur.Credo.Checks.OwnedAsyncInWeb, []},
          # MC0022 keeps a lookup's name honest about its return shape:
          # `fetch…` yields a tuple, `get…` yields the record or nil, `…!`
          # raises. It only opines where the shape is statically
          # determinable, so HTTP clients and GenServer readers named `get_*`
          # are left alone. Added by the 2026-08 audit-remediation
          # campaign; the moduledoc is the rule's spec.
          {MediaCentaur.Credo.Checks.LookupNamingContract, []},
          # MC0023 keeps test *setup* out of raw `Repo` writes — those skip
          # the changeset and act as private, drifting factories. Repo
          # *reads* stay allowed: reaching past the context to confirm a row
          # landed is a legitimate assertion. Its @grandfathered list is the
          # rollout backlog. Added by the 2026-08 audit-remediation
          # campaign; the moduledoc is the rule's spec.
          {MediaCentaur.Credo.Checks.NoRepoSetupInTests, []},
          # MC0024 scopes the old blanket "no `=~` on markup" rule to what
          # it always meant: don't substring-match HTML *attributes* —
          # `has_element?/2` parses the document and can't match the wrong
          # element. Asserting on user-visible copy with `=~` stays fine.
          # Added by the 2026-08 audit-remediation campaign.
          {MediaCentaur.Credo.Checks.NoMarkupSubstringAssertion, []},
          # MC0025 keeps the PubSub server name inside `MediaCentaur.Topics`.
          # Before ADR-060 it was hand-copied into 73 files as pure transport
          # plumbing. This is the transport rule only — MC0003 still steers
          # LiveViews to a context's `subscribe/0`, and MC0012/13/26 still
          # require the typed `Events.broadcast/1` chokepoint for the topics
          # that have one. Added by the 2026-08 audit-remediation campaign.
          {MediaCentaur.Credo.Checks.PubSubTransport, []},
          # MC0026 pins the `review:updates` chokepoint, the ADR-060 worked
          # example: every message on the topic goes through
          # `MediaCentaur.Review.Events.broadcast/1` so its four payloads keep
          # their `@enforce_keys` guarantee. Same shape as MC0012/MC0013.
          {MediaCentaur.Credo.Checks.ReviewUpdatesContract, []}
        ],
        disabled: [
          # `Readability.AliasAs` would forbid `alias Foo, as: Bar`, but the
          # codebase uses `:as` legitimately to disambiguate same-named
          # modules (e.g. `Discovery.Producer` vs `Import.Producer`) and to
          # avoid stdlib clashes (e.g. `Watcher.Supervisor` vs `Supervisor`).
          {Credo.Check.Readability.AliasAs, []},

          # `Consistency.UnusedVariableNames` flags `_` as inconsistent because
          # most unused vars in this repo follow the `_meaningful_name`
          # convention. The 397 false positives on bare `_` aren't worth
          # rewriting (especially in test fixtures and pattern matches where
          # `_` is the idiomatic choice).
          {Credo.Check.Consistency.UnusedVariableNames, []},

          # `Readability.ImplTrue` conflicts with house style. CLAUDE.md
          # explicitly says "Annotate every callback group with `@impl true`"
          # — Credo wants the opposite (`@impl MyBehaviour`).
          {Credo.Check.Readability.ImplTrue, []},

          # The directive-organization checks below would all fire on the
          # existing codebase. Quokka's `:module_directives` rewriter could
          # auto-fix them, but it's been excluded because it shadows stdlib
          # modules (e.g. `MediaCentaur.Watcher.DynamicSupervisor` lifted to
          # `DynamicSupervisor` shadows OTP). Without a safe auto-fixer the
          # 80+ manual rewrites aren't worth the noise.
          {Credo.Check.Consistency.MultiAliasImportRequireUse, []},
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.SeparateAliasRequire, []},
          {Credo.Check.Readability.StrictModuleLayout, []},

          # `LazyLogging` is a no-op on this Elixir version (the check was
          # written for Elixir < 1.7.0 — newer versions have lazy logging
          # built into `Logger` macros). Disabled to silence the
          # "requires Elixir < 1.7.0" startup warning from Credo.
          {Credo.Check.Warning.LazyLogging, []},

          # `BlockPipe` would forbid `... |> case do ... end`, but Quokka
          # actively rewrites `case foo |> bar() do` *into* the block-pipe
          # form. Disabling the Credo check keeps the two tools consistent;
          # the codebase already uses block pipes deliberately.
          {Credo.Check.Readability.BlockPipe, []},

          # `AppendSingleItem` flags `list ++ [x]` as O(n). True for hot
          # paths over large lists, but every flagged occurrence here is on
          # 3–5 element lists where the alleged inefficiency is irrelevant
          # and the `[x | list] |> Enum.reverse()` rewrite is less readable.
          {Credo.Check.Refactor.AppendSingleItem, []},

          # `NegatedIsNil` would force `when not is_nil(x)` guard clauses
          # into multi-clause pattern matches with separate nil branches.
          # The codebase consistently uses the `when not is_nil(x)` form;
          # 21 mass rewrites for a style preference is busywork.
          {Credo.Check.Refactor.NegatedIsNil, []},

          # Default-disabled and intentionally kept disabled.
          {Credo.Check.Design.DuplicatedCode, []},
          {Credo.Check.Readability.MultiAlias, []},
          {Credo.Check.Readability.NestedFunctionCalls, []},
          {Credo.Check.Readability.OnePipePerLine, []},
          {Credo.Check.Readability.SingleFunctionToBlockPipe, []},
          {Credo.Check.Readability.Specs, []},
          {Credo.Check.Refactor.ABCSize, []},
          {Credo.Check.Refactor.CondInsteadOfIfElse, []},
          {Credo.Check.Refactor.MapInto, []},
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.PipeChainStart, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.StructFieldAmount, []}
        ]
      }
    }
  ]
}
