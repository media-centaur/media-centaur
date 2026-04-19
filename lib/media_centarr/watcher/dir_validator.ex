defmodule MediaCentarr.Watcher.DirValidator do
  @moduledoc """
  Pure validator for watch-directory form entries.

  Returns `%{errors: [...], warnings: [...], preview: %{...}}`. Filesystem
  primitives are passed through an adapter map so the module is `async: true`
  test-safe and never touches the real disk during tests.

  ## Error shape

  - `{:dir, :not_found}` — path does not exist
  - `{:dir, :not_a_directory}` — path exists but is not a directory
  - `{:dir, :not_readable}` — path is not readable
  - `{:dir, :duplicate}` — another entry already uses this path
  - `{:dir, :nested}` — path is nested inside another entry's dir
  - `{:dir, :contains_existing}` — path contains another entry's dir
  - `{:images_dir, :inside_watch_dir}` — images_dir is inside a watch dir
  - `{:images_dir, :unwritable}` — images_dir cannot be created or written to
  - `{:name, :too_long}` — name exceeds 60 characters
  - `{:name, :duplicate}` — another entry uses the same name

  ## Warning shape

  - `{:dir, :unmounted, mount_point}` — path is under an unmounted mount point

  ## FS adapter

  The `fs` argument is a map with the following function-valued keys:

  - `exists?/1` — returns `boolean`
  - `dir?/1` — returns `boolean`
  - `readable?/1` — returns `boolean`
  - `ls/1` — returns `{:ok, [String.t()]} | {:error, any()}`
  - `touch/1` — returns `:ok | {:error, any()}`
  - `expand/1` — returns `String.t()`
  - `mount_for/1` — returns `{:ok, String.t()}`
  - `mounted?/1` — returns `boolean`

  Use `real_fs/0` in production code.
  """

  @video_exts ~w(.mkv .mp4 .avi .mov .m4v .webm .ts .wmv)

  @type rule :: atom()
  @type error :: {atom(), rule()} | {atom(), rule(), any()}
  @type fs_adapter :: %{
          required(:exists?) => (String.t() -> boolean()),
          required(:dir?) => (String.t() -> boolean()),
          required(:readable?) => (String.t() -> boolean()),
          required(:ls) => (String.t() -> {:ok, [String.t()]} | {:error, any()}),
          required(:touch) => (String.t() -> :ok | {:error, any()}),
          required(:expand) => (String.t() -> String.t()),
          required(:mount_for) => (String.t() -> {:ok, String.t()}),
          required(:mounted?) => (String.t() -> boolean())
        }

  @doc """
  Validates a watch-dir entry against all 11 rules.

  Returns `%{errors: [error()], warnings: [error()], preview: nil | map()}`.
  """
  @spec validate(map(), [map()], fs_adapter()) :: %{
          errors: [error()],
          warnings: [error()],
          preview: nil | map()
        }
  def validate(%{} = entry, existing, fs) do
    dir = normalize(entry["dir"], fs)
    errors = []
    warnings = []

    {errors, dir_ok?} = validate_dir_existence(errors, dir, fs)
    {errors, _} = maybe_validate_dir_shape(errors, dir, fs, dir_ok?)
    {errors, _} = maybe_validate_dir_readable(errors, dir, fs, dir_ok?)
    errors = validate_duplicate(errors, entry, existing, fs)
    errors = validate_nesting(errors, entry, existing, fs)
    warnings = validate_mount(warnings, dir, fs)
    errors = validate_images_dir(errors, entry, existing, fs)
    errors = validate_name(errors, entry, existing)

    preview = if dir_ok?, do: build_preview(dir, fs)

    %{errors: errors, warnings: warnings, preview: preview}
  end

  @doc "Returns the production filesystem adapter."
  @spec real_fs() :: fs_adapter()
  def real_fs do
    %{
      exists?: &File.exists?/1,
      dir?: &File.dir?/1,
      readable?: fn path ->
        case File.stat(path) do
          {:ok, %File.Stat{access: access}} when access in [:read, :read_write] -> true
          _ -> false
        end
      end,
      ls: &File.ls/1,
      touch: fn path ->
        case File.touch(path) do
          :ok ->
            _ = File.rm(path)
            :ok

          error ->
            error
        end
      end,
      expand: &Path.expand/1,
      mount_for: &mount_for/1,
      mounted?: &mounted?/1
    }
  end

  # --- rules ---

  defp validate_dir_existence(errors, nil, _fs), do: {[{:dir, :not_found} | errors], false}

  defp validate_dir_existence(errors, dir, fs) do
    if fs.exists?.(dir), do: {errors, true}, else: {[{:dir, :not_found} | errors], false}
  end

  defp maybe_validate_dir_shape(errors, _dir, _fs, false), do: {errors, false}

  defp maybe_validate_dir_shape(errors, dir, fs, true) do
    if fs.dir?.(dir), do: {errors, true}, else: {[{:dir, :not_a_directory} | errors], false}
  end

  defp maybe_validate_dir_readable(errors, _dir, _fs, false), do: {errors, false}

  defp maybe_validate_dir_readable(errors, dir, fs, true) do
    if fs.readable?.(dir), do: {errors, true}, else: {[{:dir, :not_readable} | errors], false}
  end

  defp validate_duplicate(errors, entry, existing, fs) do
    dir = normalize(entry["dir"], fs)
    id = entry["id"]

    duplicate? =
      Enum.any?(existing, fn existing_entry ->
        existing_entry["id"] != id and normalize(existing_entry["dir"], fs) == dir
      end)

    if duplicate?, do: [{:dir, :duplicate} | errors], else: errors
  end

  defp validate_nesting(errors, entry, existing, fs) do
    dir = normalize(entry["dir"], fs)
    id = entry["id"]

    others = Enum.reject(existing, &(&1["id"] == id))

    errors
    |> maybe_add(
      Enum.any?(others, fn other -> nested_under?(dir, normalize(other["dir"], fs)) end),
      {:dir, :nested}
    )
    |> maybe_add(
      Enum.any?(others, fn other -> nested_under?(normalize(other["dir"], fs), dir) end),
      {:dir, :contains_existing}
    )
  end

  defp nested_under?(a, b) when is_binary(a) and is_binary(b) do
    a != b and String.starts_with?(a, b <> "/")
  end

  defp nested_under?(_, _), do: false

  defp validate_mount(warnings, nil, _fs), do: warnings

  defp validate_mount(warnings, dir, fs) do
    with {:ok, mount} <- fs.mount_for.(dir),
         false <- fs.mounted?.(mount) do
      [{:dir, :unmounted, mount} | warnings]
    else
      _ -> warnings
    end
  end

  defp validate_images_dir(errors, %{"images_dir" => nil}, _existing, _fs), do: errors

  defp validate_images_dir(errors, %{"images_dir" => images_dir} = entry, existing, fs) do
    normalized_images_dir = normalize(images_dir, fs)

    errors
    |> maybe_add(
      inside_any_watch_dir?(normalized_images_dir, entry, existing, fs),
      {:images_dir, :inside_watch_dir}
    )
    |> maybe_add(not writable?(normalized_images_dir, fs), {:images_dir, :unwritable})
  end

  defp inside_any_watch_dir?(images_dir, entry, existing, fs) do
    watch_dirs =
      [entry | existing]
      |> Enum.uniq_by(& &1["id"])
      |> Enum.map(&normalize(&1["dir"], fs))

    Enum.any?(watch_dirs, fn dir -> nested_under?(images_dir, dir) end)
  end

  defp writable?(path, fs) do
    if fs.exists?.(path) do
      fs.touch.(Path.join(path, ".media-centarr-write-test")) == :ok
    else
      parent = Path.dirname(path)

      fs.exists?.(parent) and
        fs.touch.(Path.join(parent, ".media-centarr-write-test")) == :ok
    end
  end

  defp validate_name(errors, %{"name" => nil}, _), do: errors
  defp validate_name(errors, %{"name" => ""}, _), do: errors

  defp validate_name(errors, %{"name" => name, "id" => id}, existing) do
    trimmed = String.trim(name)

    errors
    |> maybe_add(String.length(trimmed) > 60, {:name, :too_long})
    |> maybe_add(
      Enum.any?(existing, fn existing_entry ->
        existing_entry["id"] != id and existing_entry["name"] == trimmed
      end),
      {:name, :duplicate}
    )
  end

  defp build_preview(dir, fs) do
    case fs.ls.(dir) do
      {:ok, entries} ->
        video_count =
          Enum.count(entries, fn name ->
            ext = name |> Path.extname() |> String.downcase()
            ext in @video_exts
          end)

        subdir_count =
          Enum.count(entries, fn name -> fs.dir?.(Path.join(dir, name)) end)

        %{video_count: video_count, subdir_count: subdir_count}

      _ ->
        nil
    end
  end

  defp maybe_add(errors, true, item), do: [item | errors]
  defp maybe_add(errors, false, _), do: errors

  defp normalize(nil, _fs), do: nil
  defp normalize(path, fs), do: fs.expand.(path)

  # --- real FS helpers ---

  defp mount_for(path) do
    case File.read("/proc/mounts") do
      {:ok, contents} ->
        mount =
          contents
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            [_dev, mount_point | _] = String.split(line, " ", parts: 3)
            mount_point
          end)
          |> Enum.filter(fn mount_point ->
            path == mount_point or String.starts_with?(path, mount_point <> "/")
          end)
          |> Enum.max_by(&String.length/1, fn -> "/" end)

        {:ok, mount}

      _ ->
        {:ok, "/"}
    end
  end

  defp mounted?(mount) do
    case File.read("/proc/mounts") do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.any?(fn line -> String.contains?(line, " " <> mount <> " ") end)

      _ ->
        true
    end
  end
end
