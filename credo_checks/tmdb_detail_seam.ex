defmodule MediaCentaur.Credo.Checks.TmdbDetailSeam do
  use Credo.Check,
    id: "MC0038",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      `MediaCentaur.TMDB.Store` is the one module that asks TMDB about a
      movie, a series or a season (ADR-071): first contact, a check, or
      the import's full fetch. `TMDB.Client.detail/2` called anywhere
      else is a fetch no policy sees — nothing decides whether the title
      was due, nothing stores the answer, nothing announces a change.

      `TMDB.Client.get_collection/2` is the one detail endpoint outside
      the store, because a collection is not a store identity yet (see
      `campaigns/collection-identity.md`); only the import stage and the
      two artwork paths may call it.

          # preferred
          {:ok, %{payload: payload}} = TMDB.Store.ensure({tmdb_id, :movie})

          # NOT preferred — a fetch outside the policy
          {:ok, %{body: body}} = TMDB.Client.detail({tmdb_id, :movie})

      Exempt: `lib/media_centaur/tmdb/store.ex` for `detail/2`; the
      collection callers for `get_collection/2`; every test file.
      """
    ]

  @store "lib/media_centaur/tmdb/store.ex"
  @collection_callers [
    "lib/media_centaur/pipeline/stages/fetch_metadata.ex",
    "lib/media_centaur/pipeline/image_refresh.ex",
    "lib/media_centaur/pipeline/image_repair.ex"
  ]
  @client_aliases [[:Client], [:TMDB, :Client], [:MediaCentaur, :TMDB, :Client]]

  for path <- [@store | @collection_callers],
      !File.exists?(Path.expand(path, Path.join(__DIR__, ".."))) do
    raise CompileError,
      description:
        "MC0038 (TmdbDetailSeam) exempts #{path}, which does not exist. " <>
          "If the module moved, update the exemption path; if it was deleted, retire the exemption."
  end

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if test_file?(filename) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, filename))
    end
  end

  defp test_file?(filename),
    do: String.starts_with?(filename, "test/") or String.contains?(filename, "/test/")

  defp traverse(
         {{:., meta, [{:__aliases__, _, aliases}, :detail]}, _, _args} = ast,
         issues,
         issue_meta,
         filename
       )
       when aliases in @client_aliases do
    if String.ends_with?(filename, @store),
      do: {ast, issues},
      else: {ast, [issue_for(issue_meta, "detail", meta[:line]) | issues]}
  end

  defp traverse(
         {{:., meta, [{:__aliases__, _, aliases}, :get_collection]}, _, _args} = ast,
         issues,
         issue_meta,
         filename
       )
       when aliases in @client_aliases do
    if Enum.any?(@collection_callers, &String.ends_with?(filename, &1)),
      do: {ast, issues},
      else: {ast, [issue_for(issue_meta, "get_collection", meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta, _filename), do: {ast, issues}

  defp issue_for(issue_meta, "detail", line_no) do
    format_issue(
      issue_meta,
      message:
        "`TMDB.Client.detail/2` outside `TMDB.Store` is a fetch no policy sees. Read the store " <>
          "(`Store.ensure/2`, `ensure_season/3`, `snapshot/1`) or, for a library entity's " <>
          "credits, `Store.fetch_full/2` (ADR-071).",
      trigger: "detail",
      line_no: line_no || 0
    )
  end

  defp issue_for(issue_meta, "get_collection", line_no) do
    format_issue(
      issue_meta,
      message:
        "`TMDB.Client.get_collection/2` is held to the import stage and the artwork paths until " <>
          "`collection-identity` decides what a collection is (design row X).",
      trigger: "get_collection",
      line_no: line_no || 0
    )
  end
end
