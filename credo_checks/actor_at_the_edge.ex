defmodule MediaCentaur.Credo.Checks.ActorAtTheEdge do
  use Credo.Check,
    id: "MC0044",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      A `Profiles.Actor` is the proof that a person acted, and an activity
      — a review, a listing, a title watched — is sent to friends only
      with one (ADR-082). It is made only where a person is present: the
      web layer, from the session's profile (`ProfileAware.actor/1`), and
      playback, from the profile playing. Anywhere else — a context, a
      job, a sweep, a seed, a data migration — an actor would be a forged
      act, and the system would speak for the person.

          # preferred — the edge makes it, the core passes it on
          ReleaseTracking.set_rung(title, rung, ProfileAware.actor(socket))
          ReleaseTracking.set_rung(title, :off, nil)   # a system write

          # NOT preferred — a background module claiming a person acted
          ReleaseTracking.set_rung(title, rung, Actor.new(profile_id))

      Building one is `Actor.new/1`, allowed under `lib/media_centaur_web/`
      and `lib/media_centaur/playback/`. A struct literal with fields —
      `%Actor{profile_id: …}`, an update `%Actor{actor | …}`, or
      `struct/2` on the module — is a way around `new/1` and is refused
      everywhere but the module itself. Match with `%Actor{}` and read
      `actor.profile_id`.

      Exempt: `lib/media_centaur/profiles/actor.ex`; every test file.
      """
    ]

  @module_file "lib/media_centaur/profiles/actor.ex"
  @edges ["lib/media_centaur_web/", "lib/media_centaur/playback/"]
  @actor_aliases [[:Actor], [:Profiles, :Actor], [:MediaCentaur, :Profiles, :Actor]]

  if !File.exists?(Path.expand(@module_file, Path.join(__DIR__, ".."))) do
    raise CompileError,
      description:
        "MC0044 (ActorAtTheEdge) names #{@module_file}, which does not exist. " <>
          "If the module moved, update the path; if it was deleted, retire the check."
  end

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if test_file?(filename) or String.ends_with?(filename, @module_file) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      edge? = Enum.any?(@edges, &String.contains?(filename, &1))
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, edge?))
    end
  end

  defp test_file?(filename),
    do: String.starts_with?(filename, "test/") or String.contains?(filename, "/test/")

  # Actor.new(...) away from the edge.
  defp traverse(
         {{:., meta, [{:__aliases__, _, aliases}, :new]}, _, _args} = ast,
         issues,
         issue_meta,
         false
       )
       when aliases in @actor_aliases do
    {ast, [issue_for(issue_meta, "new", meta[:line]) | issues]}
  end

  # %Actor{field: ...} or %Actor{actor | ...} anywhere.
  defp traverse(
         {:%, meta, [{:__aliases__, _, aliases}, {:%{}, _, [_ | _]}]} = ast,
         issues,
         issue_meta,
         _edge?
       )
       when aliases in @actor_aliases do
    {ast, [issue_for(issue_meta, "%Actor{", meta[:line]) | issues]}
  end

  # struct(Actor, ...) / struct!(Actor, ...) anywhere.
  defp traverse(
         {function, meta, [{:__aliases__, _, aliases} | _]} = ast,
         issues,
         issue_meta,
         _edge?
       )
       when function in [:struct, :struct!] and aliases in @actor_aliases do
    {ast, [issue_for(issue_meta, Atom.to_string(function), meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta, _edge?), do: {ast, issues}

  defp issue_for(issue_meta, "new", line_no) do
    format_issue(
      issue_meta,
      message:
        "`Actor.new/1` outside the web layer and playback claims a person acted where none is " <>
          "present. Take the actor from the caller, or pass `nil` for a system write (ADR-082).",
      trigger: "new",
      line_no: line_no || 0
    )
  end

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "An `Actor` built around `Actor.new/1` escapes where actors may be made. " <>
          "Build with `Actor.new/1` at the edge; match with `%Actor{}` (ADR-082).",
      trigger: trigger,
      line_no: line_no || 0
    )
  end
end
