defmodule MediaCentaur.Pipeline.ExtraRederive do
  @moduledoc """
  Re-derives `Extra.name` from each extra's `content_url` by re-parsing the path,
  so a parser-rule improvement heals records already on disk — the recomputable
  half of [ADR-057](../../decisions/architecture/2026-06-14-057-derived-data-is-recomputable.md).

  Pure and network-free: it reads filenames, never TMDB. Idempotent: a name is
  only updated when the freshly-derived value differs from what's stored. It
  parses with the same `extras_dirs` hint import used, and **only touches extras
  whose path still parses as an extra** — a `content_url` that now parses as a
  movie/episode (e.g. a collection-backfilled extra) is left untouched rather
  than overwritten with a wrong name.

  Mirrors `MediaCentaur.Pipeline.ImageRepair` and is exposed to operators via
  `MediaCentaur.Maintenance.rederive_extra_names/0`.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.{Library, Parser}
  alias MediaCentaur.Pipeline.Stages.Parse

  @type summary :: %{
          scanned: non_neg_integer(),
          updated: non_neg_integer(),
          skipped: non_neg_integer()
        }

  @doc """
  Re-derives every extra's name. Returns a `{scanned, updated, skipped}` summary;
  `skipped` counts extras whose path no longer parses as a named extra.
  """
  @spec rederive_all() :: {:ok, summary()}
  def rederive_all do
    extras_dirs = Parse.extras_dirs_from_config()

    summary =
      Enum.reduce(Library.Extras.list_rederivable(), %{scanned: 0, updated: 0, skipped: 0}, fn extra,
                                                                                               acc ->
        rederive_one(extra, extras_dirs, %{acc | scanned: acc.scanned + 1})
      end)

    Log.info(:library, fn ->
      "extra re-derive: scanned=#{summary.scanned} updated=#{summary.updated} " <>
        "skipped=#{summary.skipped}"
    end)

    {:ok, summary}
  end

  defp rederive_one(extra, extras_dirs, acc) do
    case derive_name(extra.content_url, extras_dirs) do
      {:ok, name} when name != extra.name ->
        case Library.Extras.rename(extra, name) do
          {:ok, _} ->
            %{acc | updated: acc.updated + 1}

          {:error, _changeset} ->
            %{acc | skipped: acc.skipped + 1}
        end

      {:ok, _unchanged} ->
        acc

      :skip ->
        %{acc | skipped: acc.skipped + 1}
    end
  end

  # Only returns a name for a path that still parses as an extra with a non-empty
  # title. Anything else is `:skip` — we will not overwrite a name we cannot
  # safely re-derive.
  defp derive_name(content_url, extras_dirs) do
    case Parser.parse(content_url, extras_dirs: extras_dirs) do
      %{type: :extra, title: title} when is_binary(title) ->
        case String.trim(title) do
          "" -> :skip
          trimmed -> {:ok, trimmed}
        end

      _ ->
        :skip
    end
  end
end
