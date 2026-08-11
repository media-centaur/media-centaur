defmodule MediaCentaur.TmdbArtwork do
  @moduledoc """
  The temporary artwork cache for TMDB identities that are not (or not
  yet) in the library — the "referenced" tier of the artwork promotion
  ladder (see `campaigns/cinematic-modal-unification.md`):

    * **browsing** surfaces hotlink the TMDB CDN and download nothing;
    * **referenced** identities (a tracked item or a non-terminal
      pursuit exists) get artwork here, downloaded once and served
      locally through `/media-images/` + the derivative ladder;
    * **library** entities graduate to the permanent entity-keyed store.

  Files live under `{data_dir}/images/tmdb/{media_type}-{tmdb_id}/` —
  keyed by `(media_type, tmdb_id)` because TMDB's movie and TV id
  spaces overlap (movie 550 and show 550 are different titles; the
  bare-id legacy layout under `images/tracking/` could clobber one with
  the other). The DB stores paths *relative* to `data_dir` (e.g.
  `images/tmdb/movie-550/backdrop.jpg`); `MediaCentaurWeb.Plugs.ImageServer`
  joins them back at request time.

  ## Lifecycle

  An entry is deleted by the daily retention sweep only when **both**
  hold: nothing references the identity (no hold — see
  `TmdbArtwork.HoldProvider`), and the entry has not been used for
  `#{7}` days (directory mtime, bumped by downloads and `ensure/2`).
  Nothing deletes an entry synchronously — untracking a title leaves
  its artwork to age out, so re-tracking within the window finds it
  warm.

  Hold providers are registered under the
  `:tmdb_artwork_hold_providers` config key (runtime dispatch, so the
  referencing contexts — ReleaseTracking, Acquisition — stay upstream
  of this one in the Boundary graph).
  """

  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.Retention, MediaCentaur.TMDB],
    exports: [HoldProvider, RetentionPolicies]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Config
  alias MediaCentaur.ImageFiles
  alias MediaCentaur.Library.Image
  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.TMDB.Mapper

  @type media_type :: :movie | :tv_series
  @type role :: :poster | :backdrop | :logo

  @subdir "images/tmdb"
  @legacy_subdir "images/tracking"
  @ttl_days 7

  # All roles download TMDB `original` — masters stay full-size and the
  # `?w=` derivative ladder handles serving sizes, same as the library
  # store. Storage cost is one directory per referenced identity.
  @tmdb_cdn "https://image.tmdb.org/t/p/original"

  # Files written before the switch to `original` were typically
  # 10-20KB w300/w185 thumbnails. TMDB `original` backdrops/posters
  # land in the 80KB-500KB+ range, so 50KB cleanly separates the two.
  @stale_threshold_bytes 50_000

  # --- Identity normalization -------------------------------------------

  @doc "Normalizes the TMDB media-type spellings used across the app."
  @spec normalize_type(atom() | String.t()) :: media_type()
  def normalize_type(type) when type in [:movie, "movie"], do: :movie
  def normalize_type(type) when type in [:tv, "tv", :tv_series, "tv_series"], do: :tv_series

  @doc "Parses a TMDB id that may arrive as an integer or string. `nil` when malformed."
  @spec normalize_id(term()) :: integer() | nil
  def normalize_id(id) when is_integer(id), do: id

  def normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  def normalize_id(_id), do: nil

  # --- Paths -------------------------------------------------------------

  @doc """
  The data_dir-relative path for a role — what the DB stores and what
  `/media-images/` serves. Single owner of the cache layout.
  """
  @spec relative_path(role(), media_type(), integer()) :: String.t()
  def relative_path(role, type, tmdb_id) do
    Path.join([@subdir, "#{normalize_type(type)}-#{tmdb_id}", filename(role)])
  end

  @doc "The on-disk absolute path for a role, whether or not the file exists."
  @spec on_disk_path(role(), media_type(), integer()) :: String.t()
  def on_disk_path(role, type, tmdb_id) do
    Path.join(data_dir(), relative_path(role, type, tmdb_id))
  end

  @doc """
  The absolute cache root, or `nil` when no `data_dir` is configured
  (the sweep must not walk a cwd-relative fallback).
  """
  @spec root() :: String.t() | nil
  def root do
    case Config.get(:data_dir) do
      nil -> nil
      data_dir -> Path.join(data_dir, @subdir)
    end
  end

  # --- Reads -------------------------------------------------------------

  @doc """
  Web URLs for every role that exists on disk — local-only, safe on any
  read path. Missing roles are `nil`; callers fall back to their
  synthetic gradient / logotype / hotlink treatment.
  """
  @spec urls(atom() | String.t(), term()) :: %{
          poster_url: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil
        }
  def urls(type, tmdb_id) do
    case normalize_id(tmdb_id) do
      nil ->
        %{poster_url: nil, backdrop_url: nil, logo_url: nil}

      id ->
        type = normalize_type(type)

        %{
          poster_url: role_url(:poster, type, id),
          backdrop_url: role_url(:backdrop, type, id),
          logo_url: role_url(:logo, type, id)
        }
    end
  end

  defp role_url(role, type, id) do
    if File.exists?(on_disk_path(role, type, id)) do
      Image.web_path(relative_path(role, type, id))
    end
  end

  # --- Writes ------------------------------------------------------------

  @doc """
  `urls/2`, downloading what's missing first: one TMDB detail fetch
  (images ride along via `append_to_response`) and the standard role
  downloads. Does network — callers run it async. All failures degrade
  to `urls/2`'s nils.
  """
  @spec ensure(atom() | String.t(), term()) :: %{
          poster_url: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil
        }
  def ensure(type, tmdb_id) do
    with id when not is_nil(id) <- normalize_id(tmdb_id),
         type = normalize_type(type),
         %{poster_url: p, backdrop_url: b, logo_url: l}
         when is_nil(p) or is_nil(b) or is_nil(l) <- urls(type, id) do
      fetch_missing(type, id)
      touch(type, id)
      urls(type, id)
    else
      nil -> %{poster_url: nil, backdrop_url: nil, logo_url: nil}
      %{} = resolved -> resolved
    end
  end

  def download_poster(type, tmdb_id, tmdb_path), do: download_role(:poster, type, tmdb_id, tmdb_path)

  def download_backdrop(type, tmdb_id, tmdb_path), do: download_role(:backdrop, type, tmdb_id, tmdb_path)

  def download_logo(type, tmdb_id, tmdb_path), do: download_role(:logo, type, tmdb_id, tmdb_path)

  @doc """
  Bumps the entry's last-used stamp (directory mtime) — the TTL clock
  the sweep reads. Called by `ensure/2` and the downloads; cheap and
  best-effort.
  """
  @spec touch(media_type(), integer()) :: :ok
  def touch(type, tmdb_id) do
    dir = Path.dirname(on_disk_path(:backdrop, type, tmdb_id))
    if File.dir?(dir), do: File.touch(dir)
    :ok
  end

  @doc """
  Returns true if `path` is missing, empty, or under
  #{@stale_threshold_bytes} bytes — the size class of legacy
  `w300`/`w185` thumbnails fetched before the switch to `original`.
  """
  @spec stale_image?(String.t()) :: boolean
  def stale_image?(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size < @stale_threshold_bytes
      {:error, _} -> true
    end
  end

  @doc """
  Re-downloads a role only if the on-disk copy is stale per
  `stale_image?/1`. `nil` `tmdb_path` no-ops with `:skipped`.
  """
  @spec refresh_if_stale(role(), media_type(), integer(), String.t() | nil) ::
          :refreshed | :current | :failed | :skipped
  def refresh_if_stale(_role, _type, _tmdb_id, nil), do: :skipped

  def refresh_if_stale(role, type, tmdb_id, tmdb_path)
      when role in [:poster, :backdrop, :logo] and is_binary(tmdb_path) do
    if stale_image?(on_disk_path(role, type, tmdb_id)) do
      case download_role(role, type, tmdb_id, tmdb_path) do
        {:ok, path} when is_binary(path) -> :refreshed
        _ -> :failed
      end
    else
      :current
    end
  end

  # --- Sweep -------------------------------------------------------------

  @doc """
  The daily retention sweep: removes every cache entry that is both
  unreferenced (no registered hold on its `(media_type, tmdb_id)`) and
  unused for #{@ttl_days} days. Returns the number of entries removed.

  Derivatives of removed masters are purged so `image-derivatives/`
  doesn't accumulate orphans.
  """
  @spec sweep() :: non_neg_integer()
  def sweep do
    case root() do
      nil ->
        0

      root ->
        holds = collect_holds()
        cutoff = System.os_time(:second) - @ttl_days * 86_400

        root
        |> entries()
        |> Enum.count(fn {key, dir} ->
          not MapSet.member?(holds, key) and aged_out?(dir, cutoff) and remove_entry(dir)
        end)
    end
  end

  defp entries(root) do
    case File.ls(root) do
      {:ok, names} ->
        for name <- names,
            dir = Path.join(root, name),
            File.dir?(dir),
            key = parse_key(name),
            do: {key, dir}

      {:error, _} ->
        []
    end
  end

  # Only names this module writes (`movie-<id>` / `tv_series-<id>`) are
  # cache entries; anything else is left alone.
  defp parse_key(name) do
    with [type_str, id_str] <- String.split(name, "-", parts: 2),
         type when not is_nil(type) <- parse_type(type_str),
         {id, ""} <- Integer.parse(id_str) do
      {type, id}
    else
      _ -> nil
    end
  end

  defp parse_type("movie"), do: :movie
  defp parse_type("tv_series"), do: :tv_series
  defp parse_type(_), do: nil

  defp aged_out?(dir, cutoff) do
    case File.stat(dir, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime < cutoff
      {:error, _} -> false
    end
  end

  defp remove_entry(dir) do
    case File.ls(dir) do
      {:ok, files} -> Enum.each(files, &ImageFiles.purge_derivatives_for(Path.join(dir, &1)))
      {:error, _} -> :ok
    end

    match?({:ok, _}, File.rm_rf(dir))
  end

  defp collect_holds do
    :media_centaur
    |> Application.get_env(:tmdb_artwork_hold_providers, [])
    |> Enum.reduce(MapSet.new(), fn provider, acc ->
      MapSet.union(acc, provider.holds())
    end)
  end

  # --- Legacy layout migration ------------------------------------------

  @doc """
  One-shot boot migration from the bare-id `images/tracking/{tmdb_id}/`
  layout to the typed layout. `mapping` is `%{tmdb_id_string => media_type}`
  from the tracked items; unmapped directories are orphans (the old
  `:tracking_artwork` policy would have swept them) and are deleted.
  Idempotent: with no legacy root it is a no-op, and the legacy root is
  removed when done. Self-retiring — remove once every install is past
  the layout change.
  """
  @spec migrate_legacy!(%{optional(String.t()) => media_type()}) :: :ok
  def migrate_legacy!(mapping) do
    with data_dir when is_binary(data_dir) <- Config.get(:data_dir),
         legacy_root = Path.join(data_dir, @legacy_subdir),
         true <- File.dir?(legacy_root) do
      case File.ls(legacy_root) do
        {:ok, names} -> Enum.each(names, &migrate_legacy_entry(legacy_root, &1, mapping))
        {:error, _} -> :ok
      end

      File.rm_rf(legacy_root)
      :ok
    else
      _ -> :ok
    end
  end

  defp migrate_legacy_entry(legacy_root, name, mapping) do
    source = Path.join(legacy_root, name)

    case Map.get(mapping, name) do
      nil ->
        :ok

      type ->
        dest = Path.join([data_dir(), @subdir, "#{type}-#{name}"])

        if File.dir?(dest) do
          # A populated typed entry is newer than any legacy copy.
          :ok
        else
          File.mkdir_p!(Path.dirname(dest))

          case File.rename(source, dest) do
            :ok ->
              Log.info(:library, "migrated tracking artwork #{name} -> #{type}-#{name}")

            {:error, reason} ->
              Log.warning(:library, "artwork migration failed for #{name}: #{inspect(reason)}")
          end
        end
    end
  end

  # --- Internals ---------------------------------------------------------

  defp fetch_missing(type, id) do
    case detail(type, id) do
      {:ok, data} ->
        if path = data["poster_path"], do: download_poster(type, id, path)
        if path = data["backdrop_path"], do: download_backdrop(type, id, path)
        if path = Mapper.pick_logo_path(data), do: download_logo(type, id, path)
        :ok

      {:error, reason} ->
        Log.warning(:library, "artwork fetch failed for tmdb:#{id} — #{inspect(reason)}")
        :error
    end
  end

  defp detail(:movie, id), do: Client.get_movie(id)
  defp detail(:tv_series, id), do: Client.get_tv(id)

  defp download_role(_role, _type, _tmdb_id, nil), do: {:ok, nil}

  defp download_role(role, type, tmdb_id, tmdb_path) when is_binary(tmdb_path) do
    type = normalize_type(type)
    dest = on_disk_path(role, type, tmdb_id)

    case ImageFiles.download_raw(@tmdb_cdn <> tmdb_path, dest) do
      {:ok, _path} ->
        Log.info(:library, "downloaded tmdb #{role} for #{type}-#{tmdb_id}")
        touch(type, tmdb_id)
        {:ok, relative_path(role, type, tmdb_id)}

      {:error, _category, _reason} ->
        {:ok, nil}
    end
  end

  defp filename(:poster), do: "poster.jpg"
  defp filename(:backdrop), do: "backdrop.jpg"
  defp filename(:logo), do: "logo.png"

  # Falls back to "data" (cwd-relative) only if data_dir is not
  # configured — a misconfigured deploy still writes somewhere instead
  # of crashing. The sweep and migration refuse that fallback instead.
  defp data_dir, do: Config.get(:data_dir) || "data"
end
