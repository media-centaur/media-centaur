defmodule MediaCentaur.ContextMap.Report do
  @moduledoc """
  Joins findings with verdicts, serialises them and checks them.

  Verdicts live in `docs/context-map/verdicts.json` as a list of
  `{"key", "verdict", "reason"}`; `verdict` is `leak` or `allowed`. A
  *rule wrong* verdict is never stored — it changes the rule (spec § 7).
  `check/2` fails on a finding without a verdict or a verdict without a
  finding, so every new crossing lands with its line in the same change.
  """

  alias MediaCentaur.ContextMap.Finding

  @verdicts ["leak", "allowed"]

  @doc "Each finding as a JSON-ready map: its verdict key, names as strings, and its verdict and reason (nil when unverdicted)."
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
        detail: finding.detail && Map.new(finding.detail, fn {key, value} -> {key, name(value)} end),
        verdict: verdict["verdict"],
        reason: verdict["reason"]
      }
    end
  end

  @doc "`:ok` when every finding has a verdict and every verdict has a finding; otherwise the sorted keys on each side."
  @spec check([Finding.t()], %{String.t() => map()}) ::
          :ok | {:error, %{unverdicted: [String.t()], stale: [String.t()]}}
  def check(findings, verdicts) do
    keys = MapSet.new(findings, &Finding.key/1)
    verdict_keys = MapSet.new(Map.keys(verdicts))
    unverdicted = keys |> MapSet.difference(verdict_keys) |> Enum.sort()
    stale = verdict_keys |> MapSet.difference(keys) |> Enum.sort()

    if unverdicted == [] and stale == [],
      do: :ok,
      else: {:error, %{unverdicted: unverdicted, stale: stale}}
  end

  @doc ~s(Parses the verdicts JSON into `%{key => %{"verdict", "reason"}}`; raises `ArgumentError` on a verdict other than `leak` or `allowed`.)
  @spec parse_verdicts(String.t()) :: %{String.t() => map()}
  def parse_verdicts(json) do
    json
    |> Jason.decode!()
    |> Map.new(fn %{"key" => key, "verdict" => verdict, "reason" => reason} ->
      if verdict not in @verdicts do
        raise ArgumentError,
              "verdict #{inspect(verdict)} for #{key}: only #{inspect(@verdicts)} are stored; \"rule wrong\" changes the rule instead"
      end

      {key, %{"verdict" => verdict, "reason" => reason}}
    end)
  end

  @doc "Reads and parses the verdicts file at `path`; a missing file is no verdicts."
  @spec read_verdicts(String.t()) :: %{String.t() => map()}
  def read_verdicts(path) do
    case File.read(path) do
      {:ok, json} -> parse_verdicts(json)
      {:error, :enoent} -> %{}
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
