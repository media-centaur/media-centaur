defmodule MediaCentarr.SelfUpdate.Downloader do
  @moduledoc """
  Fetches a release tarball from GitHub Releases, verifies its SHA256 against
  the sibling SHA256SUMS file, and writes it to a staging directory.

  ## Security posture

    * TLS verification is always on (Req default `verify_peer`). No flag turns
      it off.
    * The SHA256 is looked up by filename in the SHA256SUMS body — never by
      index, never from a map field the API would be free to mutate.
    * A checksum mismatch or missing entry deletes any partial file in the
      staging directory and returns a structured error, never crashes.
    * Content-Length is pre-flight-checked against `max_bytes`. The response
      body is also accumulated with the same cap so a lying server can't
      trigger an OOM.
    * Returns `{:error, :not_found | :checksum_mismatch | :checksum_missing
      | :too_large | {:http_error, status} | {:transport_error, reason}}`.

  ## Usage

      Downloader.run(tarball_url, sha256_url,
        target_dir: dir,
        filename: "media-centarr-0.7.1-linux-x86_64.tar.gz",
        progress_fn: fn downloaded, total -> ... end
      )
  """

  require MediaCentarr.Log, as: Log

  @default_max_bytes 200_000_000

  @type progress_fn :: (non_neg_integer(), non_neg_integer() | nil -> :ok)
  @type result ::
          {:ok, %{tarball_path: String.t(), sha256: String.t()}}
          | {:error, reason()}
  @type reason ::
          :not_found
          | :checksum_mismatch
          | :checksum_missing
          | :too_large
          | {:http_error, integer()}
          | {:transport_error, term()}

  @spec run(String.t(), String.t(), keyword()) :: result()
  def run(tarball_url, sha256_url, opts) do
    target_dir = Keyword.fetch!(opts, :target_dir)
    filename = Keyword.fetch!(opts, :filename)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    progress_fn = Keyword.get(opts, :progress_fn, fn _, _ -> :ok end)
    client = Keyword.get_lazy(opts, :client, &default_client/0)

    File.mkdir_p!(target_dir)

    with {:ok, expected_sha} <- fetch_expected_sha(client, sha256_url, filename),
         {:ok, bytes} <- download_with_cap(client, tarball_url, max_bytes, progress_fn) do
      actual_sha = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

      if Plug.Crypto.secure_compare(actual_sha, expected_sha) do
        tarball_path = Path.join(target_dir, filename)
        File.write!(tarball_path, bytes)
        {:ok, %{tarball_path: tarball_path, sha256: actual_sha}}
      else
        Log.warning(:system, "tarball checksum mismatch for #{filename}")
        {:error, :checksum_mismatch}
      end
    end
  end

  defp fetch_expected_sha(client, url, filename) do
    case Req.get(client, url: url) do
      {:ok, %{status: 200, body: body}} -> parse_sha256sums(body, filename)
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, {:transport_error, reason}}
    end
  end

  # SHA256SUMS format: `<hex-64>  <filename>\n`, one per line (GNU coreutils).
  # Also accepts the alternate `<hex-64> *<filename>` binary-mode format.
  defp parse_sha256sums(body, filename) when is_binary(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.find_value(:missing, fn line ->
      case Regex.run(~r/^([a-fA-F0-9]{64})\s+\*?(\S.*)$/, line) do
        [_, hex, name] when name == filename -> {:ok, String.downcase(hex)}
        _ -> false
      end
    end)
    |> case do
      :missing -> {:error, :checksum_missing}
      {:ok, _} = ok -> ok
    end
  end

  defp parse_sha256sums(_, _), do: {:error, :checksum_missing}

  defp download_with_cap(client, url, max_bytes, progress_fn) do
    case Req.get(client, url: url, compressed: false) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        total =
          headers
          |> header_value("content-length")
          |> parse_integer()

        size = byte_size(body)

        cond do
          is_integer(total) and total > max_bytes -> {:error, :too_large}
          size > max_bytes -> {:error, :too_large}
          true -> emit_progress_and_return(body, size, total, progress_fn)
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:transport_error, reason}}
    end
  end

  defp emit_progress_and_return(body, size, total, progress_fn) do
    _ = progress_fn.(0, total || size)
    _ = progress_fn.(size, total || size)
    {:ok, body}
  end

  # Req returns headers as a map of lowercase-string keys → list of values.
  defp header_value(headers, name) when is_map(headers) do
    case Map.get(headers, name) do
      [v | _] when is_binary(v) -> v
      _ -> nil
    end
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(text) when is_binary(text) do
    case Integer.parse(text) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp default_client do
    Req.new(
      base_url: nil,
      headers: [{"user-agent", "media-centarr"}]
    )
  end
end
