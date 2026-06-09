defmodule MediaCentaur.SelfUpdate.Changelog do
  @moduledoc """
  Per-version release notes embedded from the project `CHANGELOG.md` at compile
  time, for the Updates status tile. `split/1` is the pure splitter (changelog
  markdown → per-version chunks); `all/0` / `for_version/1` / `recent/1` operate
  over the embedded file. Newer-than-build updates are NOT here — those use the
  GitHub release body (`latest_release.body`). Each entry's `body` is raw
  markdown rendered by `MediaCentaurWeb.Live.SettingsLive.ReleaseNotes`.
  """
  @external_resource "CHANGELOG.md"
  @raw File.read!("CHANGELOG.md")

  # Matches a single changelog version header line, e.g. "## v0.86.1 — 2026-06-09".
  @version_header ~r/^##\s+v(?<version>\d+\.\d+\.\d+)\s+—\s+(?<date>\d{4}-\d{2}-\d{2})\s*$/

  @type entry :: %{version: String.t(), date: String.t(), body: String.t()}

  @doc "All embedded changelog entries, newest-first."
  @spec all() :: [entry()]
  def all, do: split(@raw)

  @doc "The N most recent embedded entries."
  @spec recent(non_neg_integer()) :: [entry()]
  def recent(n) when is_integer(n) and n >= 0, do: Enum.take(all(), n)

  @doc "The raw markdown body for `version`, or nil when absent."
  @spec for_version(String.t()) :: String.t() | nil
  def for_version(version) when is_binary(version) do
    case Enum.find(all(), &(&1.version == version)) do
      %{body: body} -> body
      nil -> nil
    end
  end

  @doc "Splits changelog markdown into per-version entries (newest-first as written)."
  @spec split(String.t()) :: [entry()]
  def split(markdown) when is_binary(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      case Regex.named_captures(@version_header, line) do
        %{"version" => version, "date" => date} ->
          [%{version: version, date: date, body_lines: []} | acc]

        nil ->
          case acc do
            [%{body_lines: lines} = current | rest] -> [%{current | body_lines: [line | lines]} | rest]
            [] -> acc
          end
      end
    end)
    |> Enum.map(fn %{version: version, date: date, body_lines: lines} ->
      body = lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()
      %{version: version, date: date, body: body}
    end)
    |> Enum.reverse()
  end
end
