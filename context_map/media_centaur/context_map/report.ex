defmodule MediaCentaur.ContextMap.Report do
  @moduledoc """
  Joins findings with verdicts, serialises them and checks them.

  Verdicts live in `docs/context-map/verdicts.json` as a list of
  `{"key", "verdict", "reason"}`; `verdict` is `leak` or `allowed`. A
  *rule wrong* verdict is never stored — it changes the rule (spec § 7).

  A key is either a finding's exact verdict key or a concept key, whose
  last (consumer) segment is `*`: it covers every consumer of that concept
  (`Finding.concept_key/1`). An exact key overrides the concept key.
  `check/2` fails on a finding covered by neither, or on a key matching no
  finding, so every new crossing lands with its line in the same change.
  """

  alias MediaCentaur.ContextMap.Finding

  @verdicts ["leak", "allowed"]

  @doc """
  The verdict covering `finding` and the key that supplied it: the exact
  verdict key first, then the concept key; nil when neither has a verdict.
  """
  @spec verdict_for(Finding.t(), %{String.t() => map()}) :: {String.t(), map()} | nil
  def verdict_for(finding, verdicts) do
    Enum.find_value([Finding.key(finding), Finding.concept_key(finding)], fn key ->
      if verdict = verdicts[key], do: {key, verdict}
    end)
  end

  @doc """
  Each finding as a JSON-ready map: its verdict and concept keys, names as
  strings, its excerpt, and its verdict, reason and `verdict_key` (the key
  that supplied them; all nil when unverdicted).
  """
  @spec encode_findings([Finding.t()], %{String.t() => map()}) :: [map()]
  def encode_findings(findings, verdicts) do
    for finding <- findings do
      key = Finding.key(finding)
      {verdict_key, verdict} = verdict_for(finding, verdicts) || {nil, %{}}

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
        excerpt: finding.excerpt,
        concept_key: Finding.concept_key(finding),
        detail: finding.detail && Map.new(finding.detail, fn {name, value} -> {name, name(value)} end),
        verdict: verdict["verdict"],
        reason: verdict["reason"],
        verdict_key: verdict_key
      }
    end
  end

  @doc """
  `:ok` when every finding is covered by an exact or concept key and every
  verdict key matches a finding; otherwise the sorted unverdicted finding
  keys and stale verdict keys.
  """
  @spec check([Finding.t()], %{String.t() => map()}) ::
          :ok | {:error, %{unverdicted: [String.t()], stale: [String.t()]}}
  def check(findings, verdicts) do
    matched = MapSet.new(Enum.flat_map(findings, &[Finding.key(&1), Finding.concept_key(&1)]))

    unverdicted =
      for(finding <- findings, verdict_for(finding, verdicts) == nil, do: Finding.key(finding))
      |> Enum.uniq()
      |> Enum.sort()

    stale = verdicts |> Map.keys() |> Enum.reject(&MapSet.member?(matched, &1)) |> Enum.sort()

    if unverdicted == [] and stale == [],
      do: :ok,
      else: {:error, %{unverdicted: unverdicted, stale: stale}}
  end

  @doc """
  One `path:line: RULE schema.field[ = value] — summary` line per site of
  the encoded findings, sorted by path then line, for an editor's jump list.
  """
  @spec list_lines([map()]) :: [String.t()]
  def list_lines(findings) do
    findings
    |> Enum.sort_by(&{&1.file, &1.line, list_line(&1)})
    |> Enum.map(&list_line/1)
    |> Enum.dedup()
  end

  defp list_line(finding) do
    value = if finding.value, do: " = #{finding.value}", else: ""

    "#{finding.file}:#{finding.line}: #{finding.rule} #{finding.schema}.#{finding.field}#{value} — " <>
      summary(finding)
  end

  defp summary(%{rule: "R3", consumer: consumer}), do: "reinterpreted in #{consumer}"

  defp summary(%{rule: "R1", detail: %{kind: "foreign_write"}, consumer_context: context}),
    do: "written from #{context}"

  defp summary(%{rule: "R1", detail: %{kind: "owner_never_reads"}, owner: owner}),
    do: "never read by #{owner}"

  defp summary(%{rule: "R4", detail: %{unresolved: true}}), do: "unresolved key"

  defp summary(%{rule: "R4", detail: %{target: target, in_deps: false}}),
    do: "keys into #{target} (not in deps)"

  defp summary(%{rule: "R4", detail: %{target: target}}), do: "keys into #{target}"

  @doc """
  Pretty JSON of `term` with every object's keys sorted by their string
  form, recursively, so the output does not depend on atom creation order.
  """
  @spec to_json(term()) :: String.t()
  def to_json(term), do: term |> sorted_objects() |> Jason.encode!(pretty: true)

  defp sorted_objects(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.map(fn {key, value} -> {key, sorted_objects(value)} end)
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Jason.OrderedObject.new()
  end

  defp sorted_objects(list) when is_list(list), do: Enum.map(list, &sorted_objects/1)
  defp sorted_objects(scalar), do: scalar

  @doc ~s(Parses the verdicts JSON into `%{key => %{"verdict", "reason"}}`; raises `ArgumentError` on an entry missing `key`, `verdict` or `reason`, on a verdict other than `leak` or `allowed`, or on a key with a `*` anywhere but as its whole last segment.)
  @spec parse_verdicts(String.t()) :: %{String.t() => map()}
  def parse_verdicts(json) do
    json
    |> Jason.decode!()
    |> Map.new(&parse_verdict/1)
  end

  defp parse_verdict(%{"key" => key, "verdict" => verdict, "reason" => reason}) do
    if verdict not in @verdicts do
      raise ArgumentError,
            "verdict #{inspect(verdict)} for #{key}: only #{inspect(@verdicts)} are stored; \"rule wrong\" changes the rule instead"
    end

    if wildcard_misplaced?(key) do
      raise ArgumentError,
            "verdict key #{key}: a * may only be the whole last (consumer) segment of a concept key"
    end

    {key, %{"verdict" => verdict, "reason" => reason}}
  end

  defp parse_verdict(entry) do
    raise ArgumentError,
          "verdict entry #{inspect(entry)} must have \"key\", \"verdict\" and \"reason\""
  end

  defp wildcard_misplaced?(key) do
    {leading, [last]} = key |> String.split("|") |> Enum.split(-1)
    Enum.any?(leading, &String.contains?(&1, "*")) or (last != "*" and String.contains?(last, "*"))
  end

  @doc "Reads and parses the verdicts file at `path`; a missing file is no verdicts, any other read error raises `File.Error`."
  @spec read_verdicts(String.t()) :: %{String.t() => map()}
  def read_verdicts(path) do
    case File.read(path) do
      {:ok, json} -> parse_verdicts(json)
      {:error, :enoent} -> %{}
      {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  @doc "A module or atom to its JSON name (`MediaCentaur.Library`, `web`, `rung`); nil, booleans and non-atoms pass through."
  @spec name(term()) :: term()
  def name(value) when is_nil(value) or is_boolean(value), do: value

  def name(atom) when is_atom(atom) do
    string = Atom.to_string(atom)
    if String.starts_with?(string, "Elixir."), do: inspect(atom), else: string
  end

  def name(other), do: other
end
