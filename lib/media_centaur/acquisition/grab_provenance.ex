defmodule MediaCentaur.Acquisition.GrabProvenance do
  @moduledoc """
  What a landing file was *asked for* — the identity of the title whose
  grab brought it here, if any grab did.

  The importer derives a file's identity by parsing its name and
  searching TMDB. Acquisition already knows the answer for anything it
  fetched, and until now never said so: `lib/media_centaur/pipeline/`
  held no reference to this context at all. So we could search for one
  film and file another with no signal, which is how the same wrong
  release was re-downloaded for five days — each import filed a film the
  want had not asked for, the want stayed open, and the next sweep
  grabbed it again.

  ## Why the release title is the key

  `Target.content_path` looks like the natural link and is not: it is
  populated for 19 of 29 torrent grabs and 1 of 25 usenet ones, because
  it comes from qBittorrent's own field. A seam that works for one
  protocol is not a seam.

  A target's `release_title` is always present — it is what the indexer
  called the release and what the download client names the file or
  folder after. Compared in `Search.TitleForm`'s folded form, so the
  separators a client rewrites (`A.Film.2026` vs `A Film 2026`) do not
  matter. Every path segment is tried, since clients land a release
  either as a folder of files or as a bare file.

  A miss is `nil`, never an error: most files reaching the pipeline were
  never grabbed by us at all.
  """

  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.{Target, TargetStatus}
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.TitleForm
  alias MediaCentaur.TMDB.TitleIdentity

  @doc """
  The identity the grab that produced this file was after, or `nil` when
  no grab of ours accounts for it.
  """
  @spec wanted_identity_for_file(String.t()) :: TitleIdentity.t() | nil
  def wanted_identity_for_file(file_path) when is_binary(file_path) do
    candidates = path_forms(file_path)

    if candidates != [] do
      grabbed_pursuits()
      |> Enum.find(fn {release_title, _pursuit} ->
        TitleForm.compare(release_title) in candidates
      end)
      |> case do
        {_release_title, pursuit} -> Pursuit.identity(pursuit)
        nil -> nil
      end
    end
  end

  def wanted_identity_for_file(_file_path), do: nil

  # Every segment of the path in folded form, plus the basename without
  # its extension — a release lands as a folder of files or as one file.
  defp path_forms(file_path) do
    segments =
      file_path
      |> Path.split()
      |> Enum.concat([Path.rootname(Path.basename(file_path))])

    segments
    |> Enum.map(&TitleForm.compare/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  # Only grabs that actually reached the download client, and only
  # tmdb-recipe pursuits: a prowlarr-query pursuit carries no identity
  # because the person picked the release themselves.
  defp grabbed_pursuits do
    Repo.all(
      from(t in Target,
        join: p in Pursuit,
        on: p.id == t.pursuit_id,
        where: not is_nil(t.release_title),
        where: p.recipe_type == "tmdb",
        where: t.status in ^TargetStatus.terminal_success() or t.status in ^TargetStatus.in_flight(),
        select: {t.release_title, p}
      )
    )
  end
end
