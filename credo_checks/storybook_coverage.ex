defmodule MediaCentarr.Credo.Checks.StorybookCoverage do
  use Credo.Check,
    id: "MC0009",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Every Phoenix function component in `lib/media_centarr_web/components/**`
      must have either:

        1. A story file matching `<func>.story.exs` somewhere under `storybook/`.
           The conventional placement is `storybook/<area>/<func>.story.exs`
           (where `<area>` is the component file's directory under
           `lib/media_centarr_web/components/`), but cross-cutting areas like
           `storybook/composites/` or `storybook/foundations/` are also
           discovered by basename.
        2. A `@storybook_status` module attribute with a `@storybook_reason`
           explaining why no story exists.

      Valid status values:

        * `:skip` — component will never have a story (sticky LiveView state,
           orchestration-only, or otherwise not visual). Reason required.
        * `:static_example` — depends on context state in ways that prevent live
           storying; a static specimen will be added. Reason required.
        * `:pending` — story is planned but not yet written. Reason required.
           Treated as a warning; does not fail precommit.

      Story files in `storybook/**/*.story.exs` must additionally:

        * Use the `MediaCentarrWeb.Storybook.*` namespace (boundary requirement).
        * Define `function/0` for `:component` stories.
        * Use `render_source :function` for `:component` stories (or omit it).

      Additionally, for every `attr :name, _type, values: [...]` declaration in
      a covered component, every value in the list must appear *somewhere* in
      the corresponding story source. This catches the common drift where a
      new `values:` entry is added to a component's attr but no variation
      is added to exercise it (the story file exists, so v1 coverage passes,
      but the new variant is silently un-storied).

      The matcher is intentionally a textual literal scan, not a Variation-
      attribute walk. Stories idiomatically use comprehensions
      (`for v <- ~w(primary secondary), do: %Variation{...}`) to generate
      matrices, and the source-text scan handles those without trying to
      evaluate sigils or partially evaluate the AST. False positives — where
      the literal appears in a docstring or comment but not in a Variation —
      are accepted as a tradeoff for keeping the check simple and robust.

      Source: `docs/storybook.md`, `.claude/skills/storybook/SKILL.md`.
      """
    ]

  @valid_statuses [:skip, :static_example, :pending]
  @namespace_prefix "Elixir.MediaCentarrWeb.Storybook."
  # Maps to Credo.Priority.to_integer(:low) == -10. Hard-coded to keep the
  # check's runtime free of internal Credo modules.
  @low_priority -10

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    cond do
      component_file?(filename) ->
        run_component_check(source_file, issue_meta, params)

      story_file?(filename) ->
        run_story_check(source_file, issue_meta)

      true ->
        []
    end
  end

  # =============================================================
  # COMPONENT FILE CHECK (v1)
  # =============================================================

  defp component_file?(filename) do
    String.contains?(filename, "lib/media_centarr_web/components/") and
      String.ends_with?(filename, ".ex")
  end

  defp run_component_check(source_file, issue_meta, params) do
    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        {functions, status, reason} = scan_component_module(ast)
        attr_values = scan_component_attr_values(ast)

        cond do
          # No function components in this file → skip silently
          functions == [] ->
            []

          # Story file exists for at least one of the components → covered.
          # Layer the attr-value coverage check on top: every constrained
          # `values:` value in the component must appear in at least one
          # corresponding story source.
          any_story_exists?(functions, params) ->
            check_attr_value_coverage(functions, attr_values, issue_meta, params)

          # Status declared
          status != nil ->
            validate_status(status, reason, issue_meta)

          # No story, no status → error
          true ->
            [missing_story_issue(issue_meta, functions)]
        end

      {:error, _} ->
        []
    end
  end

  # Walks the AST and returns:
  #   {[component_function_names :: atom], status :: atom | nil, reason :: String.t() | nil}
  defp scan_component_module(ast) do
    {_, {functions, _had_attr, status, reason}} =
      Macro.prewalk(ast, {[], false, nil, nil}, &component_walker/2)

    {functions |> Enum.reverse() |> Enum.uniq(), status, reason}
  end

  # An `attr ...` call (any arity) flips had_attr=true so that the next def is
  # treated as a function component. Definitions are checked before being
  # accumulated so we don't capture defs unrelated to attrs (e.g. helper
  # functions in a multi-component module before the first attr).
  defp component_walker({:attr, _, args} = node, {fns, _had_attr, st, rs})
       when is_list(args) and args != [] do
    {node, {fns, true, st, rs}}
  end

  defp component_walker({:@, _, [{:storybook_status, _, [value]}]} = node, {fns, had_attr, _, rs}) do
    {node, {fns, had_attr, value, rs}}
  end

  defp component_walker({:@, _, [{:storybook_reason, _, [value]}]} = node, {fns, had_attr, st, _})
       when is_binary(value) do
    {node, {fns, had_attr, st, value}}
  end

  defp component_walker({:def, _, [head | _]} = node, {fns, true, st, rs}) do
    case extract_def_name(head) do
      {:ok, name} -> {node, {[name | fns], false, st, rs}}
      :error -> {node, {fns, true, st, rs}}
    end
  end

  defp component_walker(node, acc), do: {node, acc}

  # `def name(args), do: body` → head is `{name, _, args_list}`.
  # `def name() do … end` → same shape with args_list = [].
  # `def name when guard, do: …` → head is `{:when, _, [{name, _, args}, _guard]}`.
  defp extract_def_name({name, _, _}) when is_atom(name) and name not in [:when], do: {:ok, name}

  defp extract_def_name({:when, _, [{name, _, _} | _]}) when is_atom(name), do: {:ok, name}

  defp extract_def_name(_), do: :error

  defp any_story_exists?(functions, params) do
    basenames = story_basenames(params)

    Enum.any?(functions, fn fname ->
      MapSet.member?(basenames, "#{fname}.story.exs")
    end)
  end

  # Lists every `*.story.exs` file under `storybook/` and reduces them to a
  # set of basenames. Matching by basename means stories under cross-cutting
  # directories (e.g. `storybook/composites/`) cover components that don't
  # share their parent directory.
  #
  # `params[:story_paths]` is a test-only override that injects the path list
  # directly. Both the override and the production call site flow through
  # `story_basenames_from/1` so they exercise the same matching logic.
  #
  # No memoization: `Path.wildcard/1` over ~30 paths is sub-millisecond and
  # disappears in the noise floor of Credo's AST work. Avoiding a process- or
  # node-scoped cache keeps the check stateless across long-lived iex sessions.
  defp story_basenames(params) do
    case story_paths_override(params) do
      {:ok, paths} -> story_basenames_from(paths)
      :error -> story_basenames_from(Path.wildcard("storybook/**/*.story.exs"))
    end
  end

  defp story_basenames_from(paths) do
    MapSet.new(paths, &Path.basename/1)
  end

  # Credo passes params as a keyword list when constructed via run_check/3 in
  # tests. In production they may be wrapped in a Params struct, so fall back
  # to :error gracefully.
  defp story_paths_override(params) when is_list(params) do
    Keyword.fetch(params, :story_paths)
  end

  defp story_paths_override(_), do: :error

  defp validate_status(status, reason, issue_meta) do
    cond do
      status not in @valid_statuses ->
        [unknown_status_issue(issue_meta, status)]

      status in [:skip, :static_example] and blank?(reason) ->
        [missing_reason_issue(issue_meta, status)]

      status == :pending and blank?(reason) ->
        [missing_reason_issue(issue_meta, :pending)]

      status == :pending ->
        [pending_warning_issue(issue_meta, reason)]

      true ->
        []
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  defp missing_story_issue(issue_meta, functions) do
    names = Enum.map_join(functions, ", ", &inspect/1)

    format_issue(issue_meta,
      message:
        "Component(s) #{names} have no story file and no @storybook_status attribute. " <>
          "Add a story under storybook/ or declare @storybook_status :skip / " <>
          ":pending / :static_example with a @storybook_reason.",
      line_no: 1
    )
  end

  # =============================================================
  # ATTR-VALUE COVERAGE CHECK (v3)
  # =============================================================
  # For every `attr :name, _type, values: [...]` in a covered component,
  # check that each value appears textually in at least one corresponding
  # story source. Catches the "story file exists but new attr value is
  # un-storied" drift that v1 missed.

  # Returns `[{attr_name, [literal_value, ...]}, ...]`. Skips attrs without
  # a `values:` constraint, and skips values whose AST shape we can't
  # statically evaluate (module attrs, function calls, etc).
  defp scan_component_attr_values(ast) do
    {_, attrs} = Macro.prewalk(ast, [], &attr_value_walker/2)
    Enum.reverse(attrs)
  end

  # Phoenix `attr` macro: `attr name, type, opts \\ []`
  # AST: {:attr, _, [name_atom, type_atom, opts_keyword_list]}
  defp attr_value_walker({:attr, _, [name | rest]} = node, acc) when is_atom(name) and rest != [] do
    case extract_values_constraint(rest) do
      [] -> {node, acc}
      values -> {node, [{name, values} | acc]}
    end
  end

  defp attr_value_walker(node, acc), do: {node, acc}

  defp extract_values_constraint(args) do
    case List.last(args) do
      kw when is_list(kw) ->
        if Keyword.keyword?(kw) do
          kw |> Keyword.get(:values) |> evaluate_values_ast()
        else
          []
        end

      _ ->
        []
    end
  end

  # Plain literal list: `values: [:row, :stacked]`
  defp evaluate_values_ast(list) when is_list(list) do
    list
    |> Enum.map(&literal_value/1)
    |> Enum.reject(&is_nil/1)
  end

  # Sigil_w: `values: ~w(primary secondary)` (strings) or `~w(primary secondary)a` (atoms).
  # AST shape: {:sigil_w, _, [{:<<>>, _, parts}, modifiers]}
  defp evaluate_values_ast({:sigil_w, _, [{:<<>>, _, parts}, modifiers]}) do
    cond do
      not Enum.all?(parts, &is_binary/1) ->
        # Interpolated sigil — can't evaluate statically.
        []

      modifiers == [?a] ->
        parts |> Enum.join() |> String.split(~r/\s+/, trim: true) |> Enum.map(&String.to_atom/1)

      modifiers == [] ->
        parts |> Enum.join() |> String.split(~r/\s+/, trim: true)

      true ->
        # 'c' charlists, 's' strings (default), other modifiers — leave alone.
        []
    end
  end

  defp evaluate_values_ast(_), do: []

  defp literal_value(atom) when is_atom(atom), do: atom
  defp literal_value(str) when is_binary(str), do: str
  defp literal_value(int) when is_integer(int), do: int
  defp literal_value(_), do: nil

  defp check_attr_value_coverage(_functions, [], _issue_meta, _params), do: []

  defp check_attr_value_coverage(functions, attr_values, issue_meta, params) do
    case combined_story_source(functions, params) do
      "" ->
        # No story content available (production path with no FS access, or
        # tests omitting :story_sources). Don't second-guess v1 coverage.
        []

      source ->
        Enum.flat_map(attr_values, fn {attr_name, values} ->
          Enum.flat_map(values, fn value ->
            if literal_in_source?(value, source) do
              []
            else
              [missing_attr_value_issue(issue_meta, attr_name, value)]
            end
          end)
        end)
    end
  end

  # Pull every story source that matches one of the component's function
  # names by basename, concatenated. Multiple components in one module
  # (e.g. core_components.ex) share their stories' search space.
  defp combined_story_source(functions, params) do
    sources_map = story_sources_map(params)

    functions
    |> Enum.map(fn fname -> Map.get(sources_map, "#{fname}.story.exs") end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  # Tests inject `:story_sources` directly as a `%{basename => content}` map.
  # In production we read from disk via `:story_paths` (or wildcard the FS).
  defp story_sources_map(params) when is_list(params) do
    case Keyword.get(params, :story_sources) do
      map when is_map(map) ->
        map

      nil ->
        case story_paths_override(params) do
          {:ok, paths} -> read_story_sources(paths)
          :error -> read_story_sources(Path.wildcard("storybook/**/*.story.exs"))
        end
    end
  end

  defp story_sources_map(_), do: %{}

  defp read_story_sources(paths) do
    paths
    |> Enum.flat_map(fn path ->
      case File.read(path) do
        {:ok, content} -> [{Path.basename(path), content}]
        {:error, _} -> []
      end
    end)
    |> Map.new()
  end

  # Negative lookbehind/lookahead on `[a-zA-Z0-9_]` enforces a complete-token
  # match. `:stacked` matches `:stacked` but not `:stacked_v2`; `primary`
  # matches the bare word in `~w(primary secondary)` and inside `"primary"`
  # but not inside `primary_color`.
  defp literal_in_source?(atom, source) when is_atom(atom) do
    pattern = ~r/(?<![a-zA-Z0-9_]):#{Regex.escape(Atom.to_string(atom))}(?![a-zA-Z0-9_])/
    Regex.match?(pattern, source)
  end

  defp literal_in_source?(str, source) when is_binary(str) do
    pattern = ~r/(?<![a-zA-Z0-9_])#{Regex.escape(str)}(?![a-zA-Z0-9_])/
    Regex.match?(pattern, source)
  end

  defp literal_in_source?(int, source) when is_integer(int) do
    pattern = ~r/(?<![a-zA-Z0-9_])#{int}(?![a-zA-Z0-9_])/
    Regex.match?(pattern, source)
  end

  defp missing_attr_value_issue(issue_meta, attr_name, value) do
    format_issue(issue_meta,
      message:
        "attr #{inspect(attr_name)} value #{inspect(value)} is not exercised in the " <>
          "corresponding story. Add a Variation with " <>
          "`attributes: %{#{attr_name}: #{inspect(value)}}` or include #{inspect(value)} " <>
          "in a comprehension over a literal collection.",
      line_no: 1
    )
  end

  defp unknown_status_issue(issue_meta, status) do
    format_issue(issue_meta,
      message:
        "Unknown @storybook_status #{inspect(status)}. " <>
          "Valid values: #{inspect(@valid_statuses)}.",
      line_no: 1
    )
  end

  defp missing_reason_issue(issue_meta, status) do
    format_issue(issue_meta,
      message: "@storybook_status #{inspect(status)} requires a non-empty @storybook_reason.",
      line_no: 1
    )
  end

  defp pending_warning_issue(issue_meta, reason) do
    format_issue(issue_meta,
      message: "Component is :pending — #{reason}. Write a story to clear this warning.",
      priority: @low_priority,
      exit_status: 0,
      line_no: 1
    )
  end

  # =============================================================
  # STORY FILE CHECK (v2)
  # =============================================================

  defp story_file?(filename) do
    String.contains?(filename, "storybook/") and
      String.ends_with?(filename, ".story.exs")
  end

  defp run_story_check(source_file, issue_meta) do
    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        story = scan_story_module(ast)

        []
        |> maybe_add_namespace_issue(story, issue_meta)
        |> maybe_add_function_issue(story, issue_meta)
        |> maybe_add_render_source_issue(story, issue_meta)

      {:error, _} ->
        []
    end
  end

  defp scan_story_module(ast) do
    {_, acc} =
      Macro.prewalk(ast, %{module: nil, type: nil, callbacks: [], render_source: nil}, &story_walker/2)

    acc
  end

  defp story_walker({:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc) when is_list(parts) do
    {node, %{acc | module: Module.concat(parts)}}
  end

  defp story_walker({:use, _, [{:__aliases__, _, [:PhoenixStorybook, :Story]}, type]} = node, acc)
       when is_atom(type) do
    {node, %{acc | type: type}}
  end

  defp story_walker({:def, _, [{:render_source, _, _ctx}, [do: value]]} = node, acc) do
    callbacks = [:render_source | acc.callbacks]
    {node, %{acc | callbacks: callbacks, render_source: value}}
  end

  defp story_walker({:def, _, [head | _]} = node, acc) do
    case extract_def_name(head) do
      {:ok, :function} ->
        {node, %{acc | callbacks: [:function | acc.callbacks]}}

      {:ok, :render_source} ->
        # Body wasn't a [do: value] keyword (e.g. multi-clause); record
        # presence but leave render_source value as-is (nil = unknown).
        {node, %{acc | callbacks: [:render_source | acc.callbacks]}}

      _ ->
        {node, acc}
    end
  end

  defp story_walker(node, acc), do: {node, acc}

  defp maybe_add_namespace_issue(issues, %{module: nil}, _issue_meta), do: issues

  defp maybe_add_namespace_issue(issues, %{module: module}, issue_meta) do
    if String.starts_with?(Atom.to_string(module), @namespace_prefix) do
      issues
    else
      issue =
        format_issue(issue_meta,
          message:
            "Story module #{inspect(module)} must be under " <>
              "MediaCentarrWeb.Storybook.* — boundary requirement.",
          line_no: 1
        )

      [issue | issues]
    end
  end

  defp maybe_add_function_issue(issues, %{type: :component, callbacks: callbacks}, issue_meta) do
    if :function in callbacks do
      issues
    else
      issue =
        format_issue(issue_meta,
          message:
            "A :component story must define function/0 returning a function reference " <>
              "(e.g. `def function, do: &MyComponents.button/1`).",
          line_no: 1
        )

      [issue | issues]
    end
  end

  defp maybe_add_function_issue(issues, _story, _issue_meta), do: issues

  defp maybe_add_render_source_issue(issues, %{type: :component, render_source: value}, issue_meta)
       when value not in [nil, :function] do
    issue =
      format_issue(issue_meta,
        message:
          "A :component story should use `def render_source, do: :function` " <>
            "(got #{inspect(value)}). Module source is too noisy for function components.",
        line_no: 1
      )

    [issue | issues]
  end

  defp maybe_add_render_source_issue(issues, _story, _issue_meta), do: issues
end
